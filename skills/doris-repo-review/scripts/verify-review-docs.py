#!/usr/bin/env python3
"""Validate both doris-repo-review documents and emit their agreed result.

Besides head, anchors, verdict, rounds and convergence, every finding must name its category
and state whether it is a regression against the merge base. A regression in a category whose
consequence is functional, data, resource, or performance (see CATEGORIES) is at least Major; a
regression anywhere else may stay Minor/Nit only with a written severity rationale."""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

ANCHOR_RE = re.compile(r"`([A-Za-z0-9_][A-Za-z0-9_./+-]*\.[A-Za-z0-9_+-]+):(\d+)(?:-(\d+))?`")
FINDING_RE = re.compile(r"^#{2,4}\s+(?:\[)?(F-\d+)(?:\])?\b")
SEVERITY_RE = re.compile(
    r"^-\s+\*\*(?:Severity|等级)\*\*\s*[:：]\s*(Blocker|Major|Minor|Nit)\s*$",
    re.IGNORECASE,
)
# `- **Regression**: yes` / `- **回归**：是`, optionally followed by one parenthetical note or
# the template's HTML comment.
REGRESSION_RE = re.compile(
    r"^-\s+\*\*(?:Regression|回归)\*\*\s*[:：]\s*(yes|no|是|否)\s*"
    r"(?:[(（][^()（）]*[)）]|<!--.*?-->)?\s*$",
    re.IGNORECASE,
)
REGRESSION_YES = ("yes", "是")
# `- **Category**: functional-bug (concurrency: lock order)` / `- **类别**：功能缺陷（并发）`.
# The class comes first; one parenthetical domain note or the template's HTML comment may follow.
CATEGORY_RE = re.compile(
    r"^-\s+\*\*(?:Category|类别)\*\*\s*[:：]\s*(.+?)\s*"
    r"(?:[(（][^()（）]*[)）]|<!--.*?-->)?\s*$",
    re.IGNORECASE,
)
# Canonical category -> (regression floor applies?, accepted spellings). Spellings are compared
# case-insensitively with spaces, hyphens and underscores removed, so `functional bug`,
# `functional_bug` and `功能性 bug` all resolve. Anything else is rejected: an unknown category
# would silently escape the floor.
CATEGORIES: dict[str, tuple[bool, tuple[str, ...]]] = {
    "functional-bug": (True, ("functional-bug", "功能缺陷", "功能性bug", "功能bug")),
    "functional-loss": (True, ("functional-loss", "功能缺失", "功能性缺失")),
    "data-error": (True, ("data-error", "数据错误")),
    "resource-leak": (True, ("resource-leak", "资源泄露", "资源泄漏")),
    "performance": (True, ("performance", "性能降低", "性能")),
    "observability": (False, ("observability", "可观测性")),
    "test-coverage": (False, ("test-coverage", "测试覆盖")),
    "wording": (False, ("wording", "措辞")),
    "maintainability": (False, ("maintainability", "可维护性")),
}
CATEGORY_ALIASES: dict[str, str] = {
    re.sub(r"[\s_-]", "", alias).casefold(): canonical
    for canonical, (_, aliases) in CATEGORIES.items()
    for alias in aliases
}
FLOORED_CATEGORIES = tuple(name for name, (floored, _) in CATEGORIES.items() if floored)
# A regression - behaviour that differs from the merge base without the PR declaring it
# intended - in a floored category is at least Major, whatever the width of its trigger or the
# size of its fix. In any other category it may stay below Major only with a written rationale.
REGRESSION_SEVERITY_FLOOR = ("Blocker", "Major")
RATIONALE_RE = re.compile(r"^\*\*(?:Severity rationale|定级理由)\s*[.。:：]?\s*\*\*")
HEAD_RE = re.compile(r"^\|\s*PR head\s*\|\s*`([0-9a-fA-F]{40})`")
VERDICT_RE = re.compile(r"^\|\s*(?:Verdict|结论)\s*\|\s*\*\*(APPROVE|REQUEST_CHANGES)\*\*\s*\|")
ROUNDS_RE = re.compile(r"^\|\s*(?:Rounds|轮次)\s*\|(.*?)\|\s*$")
EN_ROUNDS_VALUE_RE = re.compile(
    r"""
    \s*(?P<rounds>\d+)\s+of\s+max\s+3\s*[,;；]\s*
    (?:
        (?P<positive>converged)(?:\s*\([^()\n]*\))?
        |
        (?P<negative>did\s+not\s+converge)(?:\s*\([^()\n]*\))?
    )\s*
    """,
    re.IGNORECASE | re.VERBOSE,
)
ZH_ROUNDS_VALUE_RE = re.compile(
    r"""
    \s*共\s*(?P<rounds>\d+)\s*轮\s*(?:（\s*上限\s*3\s*）|\(\s*上限\s*3\s*\))\s*[,，;；]\s*
    (?:
        (?P<positive>已收敛)(?:\s*(?:（[^()（）\n]*）|\([^()（）\n]*\)))?
        |
        (?P<negative>未收敛)(?:\s*(?:（[^()（）\n]*）|\([^()（）\n]*\)))?
    )\s*
    """,
    re.VERBOSE,
)
CODE_FENCE_RE = re.compile(r"^\s*```")
SEVERITIES = ("Blocker", "Major", "Minor", "Nit")


@dataclass(frozen=True)
class Anchor:
    path: str
    start: int
    end: int | None
    source_line: int


@dataclass
class Document:
    path: Path
    head_sha: str | None = None
    verdict: str | None = None
    rounds: int | None = None
    converged: bool | None = None
    finding_ids: list[str] = field(default_factory=list)
    severities: dict[str, str] = field(default_factory=dict)
    regressions: dict[str, bool] = field(default_factory=dict)
    categories: dict[str, str] = field(default_factory=dict)
    rationales: set[str] = field(default_factory=set)
    anchors: list[Anchor] = field(default_factory=list)
    finding_anchors: dict[str, list[Anchor]] = field(default_factory=lambda: defaultdict(list))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ctx", required=True, type=Path)
    parser.add_argument("--doc", required=True, action="append", type=Path)
    parser.add_argument("--repo-root", type=Path)
    parser.add_argument("--json", action="store_true", help="Print only the validated result as JSON.")
    return parser.parse_args()


def read_meta(ctx: Path) -> dict[str, str]:
    path = ctx / "meta.env"
    if not path.is_file():
        raise ValueError(f"missing {path}; run prepare-review-context.sh first")
    meta: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" in line:
            key, _, value = line.partition("=")
            meta[key] = value
    return meta


def load_changed_ranges(ctx: Path) -> dict[str, list[tuple[int, int]]]:
    result: dict[str, list[tuple[int, int]]] = defaultdict(list)
    path = ctx / "changed_line_ranges.tsv"
    if not path.is_file():
        return result
    for line in path.read_text(encoding="utf-8").splitlines():
        parts = line.split("\t")
        if len(parts) == 3:
            result[parts[0]].append((int(parts[1]), int(parts[2])))
    return result


def parse_rounds(value: str) -> tuple[int | None, bool | None]:
    for pattern in (EN_ROUNDS_VALUE_RE, ZH_ROUNDS_VALUE_RE):
        if match := pattern.fullmatch(value):
            return int(match.group("rounds")), match.group("positive") is not None
    return None, None


def parse_document(path: Path, errors: list[str]) -> Document:
    document = Document(path=path)
    current_finding: str | None = None
    in_fence = False

    for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if CODE_FENCE_RE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue

        if match := HEAD_RE.match(line):
            if document.head_sha is not None:
                errors.append(f"{path}:{lineno}: duplicate PR head row")
            document.head_sha = match.group(1).lower()

        if match := VERDICT_RE.match(line):
            if document.verdict is not None:
                errors.append(f"{path}:{lineno}: duplicate verdict row")
            document.verdict = match.group(1)

        if match := ROUNDS_RE.match(line):
            if document.rounds is not None:
                errors.append(f"{path}:{lineno}: duplicate rounds row")
            document.rounds, document.converged = parse_rounds(match.group(1))

        if match := FINDING_RE.match(line):
            current_finding = match.group(1)
            if current_finding in document.finding_ids:
                errors.append(f"{path}:{lineno}: duplicate finding {current_finding}")
            else:
                document.finding_ids.append(current_finding)

        if match := SEVERITY_RE.match(line):
            if current_finding is None:
                errors.append(f"{path}:{lineno}: severity is not under a finding")
            elif current_finding in document.severities:
                errors.append(f"{path}:{lineno}: duplicate severity for {current_finding}")
            else:
                document.severities[current_finding] = match.group(1).title()

        if match := REGRESSION_RE.match(line):
            if current_finding is None:
                errors.append(f"{path}:{lineno}: regression flag is not under a finding")
            elif current_finding in document.regressions:
                errors.append(f"{path}:{lineno}: duplicate regression flag for {current_finding}")
            else:
                document.regressions[current_finding] = match.group(1).lower() in REGRESSION_YES

        if match := CATEGORY_RE.match(line):
            category = canonical_category(match.group(1))
            if current_finding is None:
                errors.append(f"{path}:{lineno}: category is not under a finding")
            elif category is None:
                errors.append(
                    f"{path}:{lineno}: unknown category {match.group(1).strip()!r} for "
                    f"{current_finding}; use one of {', '.join(CATEGORIES)}"
                )
            elif current_finding in document.categories:
                errors.append(f"{path}:{lineno}: duplicate category for {current_finding}")
            else:
                document.categories[current_finding] = category

        if current_finding is not None and RATIONALE_RE.match(line):
            document.rationales.add(current_finding)

        for match in ANCHOR_RE.finditer(line):
            anchor = Anchor(
                path=match.group(1),
                start=int(match.group(2)),
                end=int(match.group(3)) if match.group(3) else None,
                source_line=lineno,
            )
            document.anchors.append(anchor)
            if current_finding is not None:
                document.finding_anchors[current_finding].append(anchor)

    if document.head_sha is None:
        errors.append(f"{path}: missing PR head row")
    if document.verdict is None:
        errors.append(f"{path}: missing Verdict/结论 row")
    if document.rounds is None:
        errors.append(f"{path}: missing Rounds/轮次 value")
    elif not 1 <= document.rounds <= 3:
        errors.append(f"{path}: rounds must be between 1 and 3")
    if document.converged is None:
        errors.append(f"{path}: rounds row must state convergence")

    for finding in document.finding_ids:
        if finding not in document.severities:
            errors.append(f"{path}: finding {finding} has no severity")
        if finding not in document.categories:
            errors.append(
                f"{path}: finding {finding} has no Category/类别 line (one of {', '.join(CATEGORIES)})"
            )
        if finding not in document.regressions:
            errors.append(
                f"{path}: finding {finding} has no Regression/回归 line (yes/no against the merge base)"
            )
        elif document.regressions[finding] and finding in document.categories:
            severity = document.severities.get(finding)
            category = document.categories[finding]
            if severity in (None, *REGRESSION_SEVERITY_FLOOR):
                pass
            elif category in FLOORED_CATEGORIES:
                errors.append(
                    f"{path}: finding {finding} is a regression in category {category} but rated "
                    f"{severity}; a {category} regression against the merge base is at least Major"
                )
            elif finding not in document.rationales:
                errors.append(
                    f"{path}: finding {finding} is a regression in category {category} rated "
                    f"{severity}; add a **Severity rationale** paragraph saying why the behaviour "
                    "change is acceptable at that severity"
                )
        if not document.finding_anchors.get(finding):
            errors.append(f"{path}: finding {finding} has no `path:line` anchor")

    counts = severity_counts(document)
    expected = "REQUEST_CHANGES" if counts["blocker"] or counts["major"] else "APPROVE"
    if document.verdict is not None and document.verdict != expected:
        errors.append(f"{path}: verdict {document.verdict} conflicts with finding severities")
    return document


def severity_counts(document: Document) -> dict[str, int]:
    return {
        name.casefold(): sum(1 for value in document.severities.values() if value == name)
        for name in SEVERITIES
    }


def canonical_category(value: str) -> str | None:
    return CATEGORY_ALIASES.get(re.sub(r"[\s_-]", "", value).casefold())


def regression_count(document: Document) -> int:
    return sum(1 for value in document.regressions.values() if value)


def floored_regression_count(document: Document) -> int:
    """Regressions whose category carries the Major floor - never present in a valid APPROVE."""
    return sum(
        1
        for finding, value in document.regressions.items()
        if value and document.categories.get(finding) in FLOORED_CATEGORIES
    )


def finding_anchor_keys(document: Document, finding: str) -> list[tuple[str, int, int]]:
    """Return stable semantic anchors, excluding document source-line metadata."""
    return sorted(
        {
            (anchor.path, anchor.start, anchor.end or anchor.start)
            for anchor in document.finding_anchors.get(finding, [])
        }
    )


def verify_anchors(
    document: Document,
    repo_root: Path,
    changed_ranges: dict[str, list[tuple[int, int]]],
    errors: list[str],
    warnings: list[str],
) -> None:
    line_counts: dict[str, int] = {}
    for anchor in document.anchors:
        if anchor.end is not None and anchor.end < anchor.start:
            errors.append(
                f"{document.path}:{anchor.source_line}: {anchor.path}:{anchor.start}-{anchor.end} "
                "has an end before its start"
            )
            continue
        target = repo_root / anchor.path
        if not target.is_file():
            errors.append(f"{document.path}:{anchor.source_line}: anchor path does not exist -> {anchor.path}")
            continue
        if anchor.path not in line_counts:
            try:
                line_counts[anchor.path] = sum(
                    1 for _ in target.open(encoding="utf-8", errors="replace")
                )
            except OSError as exc:
                errors.append(
                    f"{document.path}:{anchor.source_line}: cannot read {anchor.path}: {exc}"
                )
                continue
        last = anchor.end or anchor.start
        if anchor.start < 1 or last > line_counts[anchor.path]:
            errors.append(
                f"{document.path}:{anchor.source_line}: {anchor.path}:{anchor.start} out of range "
                f"(file has {line_counts[anchor.path]} lines)"
            )
            continue
        ranges = changed_ranges.get(anchor.path)
        if not ranges:
            warnings.append(f"{document.path}:{anchor.source_line}: {anchor.path} is outside the changed-file set")
        elif not any(not (last < start or anchor.start > end) for start, end in ranges):
            warnings.append(f"{document.path}:{anchor.source_line}: {anchor.path}:{anchor.start} is unchanged context")


def main() -> int:
    args = parse_args()
    errors: list[str] = []
    warnings: list[str] = []
    try:
        meta = read_meta(args.ctx.resolve())
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    head_sha = meta.get("HEAD_SHA", "").lower()
    if not re.fullmatch(r"[0-9a-f]{40}", head_sha):
        errors.append("meta.env HEAD_SHA is not a full SHA")

    repo_root = (args.repo_root or Path(meta.get("REPO_ROOT", "."))).resolve()
    docs_root = Path(meta.get("DOCS_ROOT", repo_root)).resolve()
    pr_number = meta.get("PR_NUMBER", "")
    expected_paths = {
        (docs_root / "review-docs" / f"pr-{pr_number}-review.en.md").resolve(),
        (docs_root / "review-docs" / f"pr-{pr_number}-review.zh.md").resolve(),
    }
    actual_paths = {path.resolve() for path in args.doc}
    if len(args.doc) != 2 or (pr_number and actual_paths != expected_paths):
        errors.append("use exactly the standard PR-specific EN and ZH review documents")

    documents: list[Document] = []
    changed_ranges = load_changed_ranges(args.ctx.resolve())
    for path in args.doc:
        resolved = path.resolve()
        if not resolved.is_file():
            errors.append(f"{resolved}: document not found")
            continue
        document = parse_document(resolved, errors)
        verify_anchors(document, repo_root, changed_ranges, errors, warnings)
        documents.append(document)

    if len(documents) == 2:
        left, right = documents
        if left.finding_ids != right.finding_ids:
            errors.append("EN and ZH finding IDs or order differ")
        if left.severities != right.severities:
            errors.append("EN and ZH finding severities differ")
        if left.regressions != right.regressions:
            errors.append("EN and ZH regression flags differ")
        if left.categories != right.categories:
            errors.append("EN and ZH finding categories differ")
        for finding in sorted(set(left.finding_ids) & set(right.finding_ids)):
            if finding_anchor_keys(left, finding) != finding_anchor_keys(right, finding):
                errors.append(f"EN and ZH anchors differ for {finding}")
        if (left.head_sha, left.verdict, left.rounds, left.converged) != (
            right.head_sha,
            right.verdict,
            right.rounds,
            right.converged,
        ):
            errors.append("EN and ZH head, verdict, rounds, or convergence differ")
        if left.head_sha != head_sha:
            errors.append(f"review documents target {left.head_sha}, but context head is {head_sha}")

    output = sys.stderr if args.json else sys.stdout
    for warning in warnings:
        print(f"NOTE: {warning}", file=output)
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    if len(documents) != 2:
        print("ERROR: both review documents are required", file=sys.stderr)
        return 1

    result = {
        "commit": head_sha,
        "verdict": documents[0].verdict,
        "findings": severity_counts(documents[0]),
        "regressions": regression_count(documents[0]),
        "floored_regressions": floored_regression_count(documents[0]),
        "rounds": documents[0].rounds,
        "converged": documents[0].converged,
    }
    if args.json:
        print(json.dumps(result, separators=(",", ":")))
    else:
        print("OK: both review documents agree and every anchor resolves.")
        print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
