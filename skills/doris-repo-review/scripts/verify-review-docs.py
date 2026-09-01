#!/usr/bin/env python3
"""Validate both doris-repo-review documents and emit their agreed result."""

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
HEAD_RE = re.compile(r"^\|\s*PR head\s*\|\s*`([0-9a-fA-F]{40})`")
VERDICT_RE = re.compile(r"^\|\s*(?:Verdict|结论)\s*\|\s*\*\*(APPROVE|REQUEST_CHANGES)\*\*\s*\|")
ROUNDS_RE = re.compile(r"^\|\s*(?:Rounds|轮次)\s*\|(.*?)\|\s*$")
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
    number = re.match(r"\s*(?:共\s*)?(\d+)(?:\s+of max 3|\s*轮)", value)
    lowered = value.casefold()
    if "not converged" in lowered or "未收敛" in value:
        converged = False
    elif "converged" in lowered or "已收敛" in value:
        converged = True
    else:
        converged = None
    return (int(number.group(1)) if number else None, converged)


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
