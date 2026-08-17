#!/usr/bin/env python3
"""Verify the `path:line` anchors of the doris-repo-review output documents.

Local review has no inline GitHub comments, so every finding must carry an
anchor the reader can jump to. This script proves the anchors are real:

  * the path exists in the worktree at HEAD;
  * the line number is inside the file;
  * (informational) whether the line falls inside a range this PR touched;
  * the EN and ZH documents expose the same finding IDs, and every finding
    carries at least one anchor.

Anchors must be written inside backticks as `path:line` or `path:start-end`.

Usage:
  verify-anchors.py --ctx <context-dir> --doc <en.md> --doc <zh.md>

Exits non-zero when an anchor is broken or the two documents disagree.
"""

from __future__ import annotations

import argparse
import re
import sys
from collections import defaultdict
from pathlib import Path

ANCHOR_RE = re.compile(r"`([A-Za-z0-9_][A-Za-z0-9_./+-]*\.[A-Za-z0-9_+-]+):(\d+)(?:-(\d+))?`")
FINDING_RE = re.compile(r"^#{2,4}\s+(?:\[)?(F-\d+)(?:\])?\b")
CODE_FENCE_RE = re.compile(r"^\s*```")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--ctx", required=True, type=Path, help="Review context directory (holds meta.env).")
    parser.add_argument("--doc", required=True, action="append", type=Path, help="Review document; repeat for EN and ZH.")
    parser.add_argument("--repo-root", type=Path, default=None, help="Repo root; defaults to REPO_ROOT from meta.env.")
    return parser.parse_args()


def read_meta(ctx: Path) -> dict[str, str]:
    meta_path = ctx / "meta.env"
    if not meta_path.is_file():
        sys.exit(f"missing {meta_path}; run prepare-review-context.sh first")
    meta = {}
    for line in meta_path.read_text(encoding="utf-8").splitlines():
        if "=" in line:
            key, _, value = line.partition("=")
            meta[key] = value
    return meta


def load_changed_ranges(ctx: Path) -> dict[str, list[tuple[int, int]]]:
    ranges: dict[str, list[tuple[int, int]]] = defaultdict(list)
    tsv = ctx / "changed_line_ranges.tsv"
    if tsv.is_file():
        for line in tsv.read_text(encoding="utf-8").splitlines():
            parts = line.split("\t")
            if len(parts) == 3:
                ranges[parts[0]].append((int(parts[1]), int(parts[2])))
    return ranges


def scan_document(doc: Path) -> tuple[list[str], dict[str, list[tuple[int, int, int | None]]], list[tuple[int, int, int | None]]]:
    """Return (finding ids in order, anchors per finding, all anchors)."""
    findings: list[str] = []
    per_finding: dict[str, list[tuple[int, int, int | None]]] = defaultdict(list)
    all_anchors: list[tuple[str, int, int | None, int]] = []
    current: str | None = None
    in_fence = False

    for lineno, line in enumerate(doc.read_text(encoding="utf-8").splitlines(), start=1):
        if CODE_FENCE_RE.match(line):
            in_fence = not in_fence
            continue
        heading = FINDING_RE.match(line)
        if heading:
            current = heading.group(1)
            if current not in findings:
                findings.append(current)
        if in_fence:
            continue
        for match in ANCHOR_RE.finditer(line):
            path, start, end = match.group(1), int(match.group(2)), match.group(3)
            anchor = (path, start, int(end) if end else None, lineno)
            all_anchors.append(anchor)
            if current:
                per_finding[current].append(anchor)
    return findings, per_finding, all_anchors


def in_changed_range(ranges: list[tuple[int, int]], start: int, end: int | None) -> bool:
    last = end or start
    return any(not (last < lo or start > hi) for lo, hi in ranges)


def main() -> int:
    args = parse_args()
    ctx = args.ctx.resolve()
    meta = read_meta(ctx)
    repo_root = (args.repo_root or Path(meta.get("REPO_ROOT", "."))).resolve()
    changed_ranges = load_changed_ranges(ctx)

    errors: list[str] = []
    warnings: list[str] = []
    finding_sets: dict[Path, list[str]] = {}

    for doc in args.doc:
        doc = doc.resolve()
        if not doc.is_file():
            errors.append(f"{doc}: document not found")
            continue
        findings, per_finding, anchors = scan_document(doc)
        finding_sets[doc] = findings

        print(f"\n=== {doc} ===")
        print(f"findings: {len(findings)}  anchors: {len(anchors)}")

        for path, start, end, lineno in anchors:
            target = repo_root / path
            if not target.is_file():
                errors.append(f"{doc}:{lineno}: anchor path does not exist -> {path}")
                continue
            try:
                total = sum(1 for _ in target.open(encoding="utf-8", errors="replace"))
            except OSError as exc:
                errors.append(f"{doc}:{lineno}: cannot read {path}: {exc}")
                continue
            last = end or start
            if start < 1 or last > total:
                errors.append(f"{doc}:{lineno}: {path}:{start}{'-' + str(end) if end else ''} out of range (file has {total} lines)")
                continue
            if path in changed_ranges and not in_changed_range(changed_ranges[path], start, end):
                warnings.append(f"{doc}:{lineno}: {path}:{start}{'-' + str(end) if end else ''} is context, not a changed line (fine if intentional)")
            elif path not in changed_ranges:
                warnings.append(f"{doc}:{lineno}: {path} is not in this PR's changed-file set (fine for upstream/downstream evidence)")

        for finding in findings:
            if not per_finding.get(finding):
                errors.append(f"{doc}: finding {finding} has no `path:line` anchor")

    docs = list(finding_sets)
    if len(docs) >= 2:
        base_doc, base_ids = docs[0], set(finding_sets[docs[0]])
        for other in docs[1:]:
            other_ids = set(finding_sets[other])
            missing = sorted(base_ids - other_ids)
            extra = sorted(other_ids - base_ids)
            if missing:
                errors.append(f"{other}: missing finding IDs present in {base_doc.name}: {', '.join(missing)}")
            if extra:
                errors.append(f"{other}: has finding IDs absent from {base_doc.name}: {', '.join(extra)}")

    if warnings:
        print("\n--- notes ---")
        for note in warnings:
            print(f"  note: {note}")

    if errors:
        print("\n--- errors ---")
        for error in errors:
            print(f"  ERROR: {error}")
        print(f"\nFAILED: {len(errors)} anchor problem(s).")
        return 1

    print("\nOK: every anchor resolves and both documents expose the same findings.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
