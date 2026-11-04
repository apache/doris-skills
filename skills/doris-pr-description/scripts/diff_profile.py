#!/usr/bin/env python3
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
"""Show where the lines of a Doris change go, for the Change map of its PR description.

Usage:
  diff_profile.py BASE              the change from BASE to HEAD
  diff_profile.py BASE..HEAD        the change between two commits, and the commits in between
  diff_profile.py BASE...HEAD       the same, from the merge base of BASE and HEAD
  diff_profile.py --top N RANGE     list the N largest files of each kind (default 8)
  diff_profile.py --json RANGE      machine-readable output

Run it from the repository. It prints the added and deleted lines by kind (production code,
submodule pointers, tests, generated test output, docs, build and CI), the largest files of
each kind, and the same split for each commit. The kind comes from the path alone, so check it
against what the files contain: a test utility under src/main counts as production code, for
example.

A submodule pointer, such as contrib/apache-orc, is one line in the diff but stands for the
submodule's own change. Each one is listed with its old and new commit, the repository and
branch that .gitmodules names, and the commits and lines in between when the submodule is
checked out with both commits; otherwise with a link to compare them.
"""

import argparse
import json
import os
import re
import subprocess
import sys

# The first kind whose pattern matches a path wins, so the order matters: a regression .out
# file is generated before it is a test, and the pipeline configs under regression-test/ are CI.
# Submodule pointers are recognized by their mode, not their path.
KINDS = (
    ("generated", "generated test output", (
        r"^regression-test/data/.*\.out$",
    )),
    ("build", "build and CI", (
        r"^\.[^/]+$", r"^\.[^/]+/",  # .gitignore, .github/, .claude/ and the like
        r"^[^/]+\.sh$", r"(^|/)pom\.xml$", r"(^|/)CMakeLists\.txt$", r"\.cmake$",
        r"^regression-test/pipeline/", r"^build-support/", r"^thirdparty/", r"^tools/",
        r"^hooks/", r"^bin/", r"^conf/", r"^dist/", r"^fe/check/", r"^docker/(?!thirdparties/)",
        r"^(LICENSE|NOTICE)[^/]*$",
    )),
    ("tests", "tests", (
        r"^regression-test/", r"(^|/)src/test/", r"^be/test/", r"^cloud/test/",
        r"^be/benchmark/", r"^docker/thirdparties/",
    )),
    ("docs", "docs", (
        r"\.md$", r"^docs/", r"^samples/",
    )),
)
CODE_KIND = ("code", "production code")
SUBMODULE_KIND = ("submodule", "submodule pointers")
KIND_NAMES = dict([(key, name) for key, name, _ in KINDS] + [CODE_KIND, SUBMODULE_KIND])
# The order in which kinds are shown, which differs from the matching order above.
KIND_ORDER = ["code", "submodule", "tests", "generated", "docs", "build"]
PATTERNS = [(key, [re.compile(p) for p in patterns]) for key, _, patterns in KINDS]
MAX_COMMITS = 100
GITLINK_MODE = "160000"
NULL_SHA = "0" * 40
GITHUB_REPO = re.compile(r"github\.com[:/]+([^/]+)/([^/]+?)(?:\.git)?/*$")
STATUS_NOTES = {"A": "new", "D": "deleted", "R": "renamed", "C": "copied"}


class GitError(Exception):
    pass


def git(*args):
    try:
        return subprocess.run(("git",) + args, check=True, capture_output=True,
                              text=True).stdout
    except FileNotFoundError:
        raise GitError("git is not installed")
    except subprocess.CalledProcessError as exc:
        raise GitError("git %s failed: %s" % (" ".join(args), exc.stderr.strip()))


def kind_of(path):
    for key, patterns in PATTERNS:
        if any(p.search(path) for p in patterns):
            return key
    return CODE_KIND[0]


def resolve_range(spec):
    """Return (base, head) commits for BASE, BASE..HEAD, or BASE...HEAD."""
    if "..." in spec:
        left, right = spec.split("...", 1)
        right = right or "HEAD"
        base = git("merge-base", left or "HEAD", right).strip()
    elif ".." in spec:
        left, right = spec.split("..", 1)
        base, right = left or "HEAD", right or "HEAD"
    else:
        base, right = spec, "HEAD"
    for rev in (base, right):
        try:
            git("rev-parse", "--verify", "--quiet", rev + "^{commit}")
        except GitError:
            raise GitError("not a commit: %s" % rev)
    return base, right


def numstat(base, head):
    """The changed files between two commits, with rename detection. A submodule pointer gets
    the kind "submodule" and its old and new commit."""
    meta = {}
    tokens = git("diff", "--raw", "--no-abbrev", "-z", "-M", base, head).split("\0")
    index = 0
    while index < len(tokens) and tokens[index]:
        old_mode, new_mode, old_sha, new_sha, status = tokens[index].lstrip(":").split(" ", 4)
        if status[0] in "RC":  # the old and new paths follow
            path = tokens[index + 2]
            index += 3
        else:
            path = tokens[index + 1]
            index += 2
        meta[path] = {"status": status[0], "gitlink": GITLINK_MODE in (old_mode, new_mode),
                      "old": old_sha, "new": new_sha}
    files = []
    tokens = git("diff", "--numstat", "-z", "-M", base, head).split("\0")
    index = 0
    while index < len(tokens):
        if not tokens[index]:
            index += 1
            continue
        added, deleted, path = tokens[index].split("\t", 2)
        old = None
        if not path:  # a rename: the old and new paths follow
            old, path = tokens[index + 1], tokens[index + 2]
            index += 3
        else:
            index += 1
        info = meta.get(path, {"status": "M", "gitlink": False})
        binary = added == "-"
        entry = {"path": path, "old_path": old, "status": info["status"],
                 "added": 0 if binary else int(added),
                 "deleted": 0 if binary else int(deleted), "binary": binary,
                 "kind": SUBMODULE_KIND[0] if info["gitlink"] else kind_of(path)}
        if info["gitlink"]:
            entry["submodule"] = {"old": info["old"], "new": info["new"]}
        files.append(entry)
    return files


def split(files):
    kinds = {key: {"added": 0, "deleted": 0, "files": 0} for key in KIND_ORDER}
    for f in files:
        k = kinds[f["kind"]]
        k["added"] += f["added"]
        k["deleted"] += f["deleted"]
        k["files"] += 1
    return kinds


def submodule_config(rev, path):
    """The url and branch that .gitmodules at `rev` gives the submodule at `path`."""
    try:
        listing = git("config", "--blob", rev + ":.gitmodules", "--get-regexp",
                      r"^submodule\..*\.(path|url|branch)$")
    except GitError:
        return {}
    entries = {}
    for line in listing.splitlines():
        key, _, value = line.partition(" ")
        name, _, field = key[len("submodule."):].rpartition(".")
        entries.setdefault(name, {})[field] = value
    for entry in entries.values():
        if entry.get("path") == path:
            return {field: entry[field] for field in ("url", "branch") if field in entry}
    return {}


def local_range(directory, old, new):
    """The commits and lines between two commits of a submodule, or None unless the submodule
    is checked out here with both of them."""
    try:
        top = git("-C", directory, "rev-parse", "--show-toplevel").strip()
    except GitError:
        return None
    if os.path.realpath(top) != os.path.realpath(directory):
        return None  # an empty submodule directory resolves to the superproject
    try:
        for sha in (old, new):
            git("-C", directory, "cat-file", "-e", sha + "^{commit}")
    except GitError:
        return None
    try:
        git("-C", directory, "merge-base", "--is-ancestor", old, new)
        forward = True
    except GitError:
        forward = False
    commits = git("-C", directory, "log", "--format=%h %s", old + ".." + new).splitlines()
    dropped = [] if forward else git("-C", directory, "log", "--format=%h %s",
                                     new + ".." + old).splitlines()
    stats = [line.split("\t", 2)
             for line in git("-C", directory, "diff", "--numstat", old, new).splitlines() if line]
    return {"forward": forward, "commits": commits, "dropped": dropped, "files": len(stats),
            "added": sum(int(a) for a, _, _ in stats if a != "-"),
            "deleted": sum(int(d) for _, d, _ in stats if d != "-")}


def submodule_details(base, head, files):
    root = git("rev-parse", "--show-toplevel").strip()
    details = []
    for f in files:
        if f["kind"] != SUBMODULE_KIND[0]:
            continue
        old, new = f["submodule"]["old"], f["submodule"]["new"]
        detail = {"path": f["path"], "old": old, "new": new, "status": f["status"]}
        detail.update(submodule_config(base if new == NULL_SHA else head, f["path"]))
        if NULL_SHA not in (old, new):
            match = GITHUB_REPO.search(detail.get("url", ""))
            if match:
                detail["compare_url"] = "https://github.com/%s/%s/compare/%s...%s" % (
                    match.group(1), match.group(2), old, new)
            detail["local"] = local_range(os.path.join(root, f["path"]), old, new)
        details.append(detail)
    return details


def changed_lines(spec):
    """Added plus deleted lines of a range, for check_pr.py."""
    base, head = resolve_range(spec)
    return sum(f["added"] + f["deleted"] for f in numstat(base, head))


def profile(spec):
    base, head = resolve_range(spec)
    files = numstat(base, head)
    commits, merges = [], 0
    log = git("log", "--reverse", "--format=%H%x00%h%x00%P%x00%s", base + ".." + head)
    for line in log.splitlines():
        full, short, parents, subject = line.split("\0", 3)
        if len(parents.split()) > 1:
            merges += 1
            continue
        commits.append({"commit": short, "full": full, "subject": subject})
    for c in commits[:MAX_COMMITS]:
        commit_files = numstat(c["full"] + "^", c["full"])
        c["kinds"] = split(commit_files)
        c["submodules"] = [f["path"] for f in commit_files if f["kind"] == SUBMODULE_KIND[0]]
    return {
        "base": base, "head": head,
        "total": {"added": sum(f["added"] for f in files),
                  "deleted": sum(f["deleted"] for f in files), "files": len(files)},
        "kinds": split(files),
        "files": sorted(files, key=lambda f: (-(f["added"] + f["deleted"]), f["path"])),
        "submodules": submodule_details(base, head, files),
        "commits": commits, "merges_skipped": merges,
    }


def signed(added, deleted):
    return "+%d -%d" % (added, deleted)


def share(part, whole):
    if not whole:
        return "0%"
    percent = 100.0 * part / whole
    if 0 < percent < 1:
        return "<1%"
    if 99 < percent < 100:
        return ">99%"
    return "%d%%" % round(percent)


def plural(count, word):
    return "%d %s%s" % (count, word, "" if count == 1 else "s")


def submodule_lines(detail):
    old, new = detail["old"][:11], detail["new"][:11]
    source = ", ".join(part for part in (detail.get("url"), detail.get("branch") and
                                         "branch " + detail["branch"]) if part)
    if detail["status"] == "A":
        head = "  %s  added at %s" % (detail["path"], new)
    elif detail["status"] == "D":
        head = "  %s  removed; it was at %s" % (detail["path"], old)
    else:
        head = "  %s  %s -> %s" % (detail["path"], old, new)
    out = [head + ("  (%s)" % source if source else "")]
    local = detail.get("local")
    if local:
        if not local["forward"]:
            out.append("    the new commit does not descend from the old one; it leaves out %s%s"
                       % (plural(len(local["dropped"]), "commit"),
                          ":" if local["dropped"] else ""))
            out.extend("      " + commit for commit in local["dropped"][:10])
        out.append("    %s, %s in %s%s" % (plural(len(local["commits"]), "commit"),
                                             signed(local["added"], local["deleted"]),
                                             plural(local["files"], "file"),
                                             ":" if local["commits"] else ""))
        out.extend("      " + commit for commit in local["commits"][:10])
        if len(local["commits"]) > 10:
            out.append("      ... %d more" % (len(local["commits"]) - 10))
    elif "local" in detail:
        out.append("    not checked out here with both commits; compare them "
                   + ("at" if detail.get("compare_url") else "in the submodule's repository"))
        if detail.get("compare_url"):
            out.append("    " + detail["compare_url"])
    return out


def as_text(prof, top):
    total = prof["total"]
    out = ["Diff %s..%s: %s, %s, %s"
           % (prof["base"][:11], prof["head"], plural(total["files"], "file"),
              signed(total["added"], total["deleted"]), plural(len(prof["commits"]), "commit"))]
    if prof["merges_skipped"]:
        out[0] += " (and %s, left out below)" % plural(prof["merges_skipped"], "merge commit")
    out.append("")
    for key in KIND_ORDER:
        k = prof["kinds"][key]
        if k["files"]:
            out.append("  %-22s %7s %6s  %s" % (KIND_NAMES[key], "+%d" % k["added"],
                                                 "-%d" % k["deleted"], plural(k["files"], "file")))
    kinds = prof["kinds"]
    tests = kinds["tests"]["added"] + kinds["generated"]["added"]
    parts = ["production code %d (%s)" % (kinds["code"]["added"],
                                          share(kinds["code"]["added"], total["added"])),
             "tests with their generated output %d (%s)" % (tests, share(tests, total["added"]))]
    if kinds["submodule"]["files"]:
        parts.append("submodule pointers %d (%s)" % (
            kinds["submodule"]["added"], share(kinds["submodule"]["added"], total["added"])))
    out.append("")
    out.append("Of the %d added lines: %s." % (total["added"], ", ".join(parts)))
    if prof["submodules"]:
        out.append("Each submodule pointer stands for the submodule's own change, listed below.")
    for key in KIND_ORDER:
        group = [f for f in prof["files"] if f["kind"] == key]
        if not group or key == SUBMODULE_KIND[0]:
            continue
        out.append("")
        out.append("%s, largest first:" % KIND_NAMES[key])
        for f in group[:top]:
            note = STATUS_NOTES.get(f["status"], "")
            path = f["path"] if not f["old_path"] else "%s (from %s)" % (f["path"], f["old_path"])
            lines = "binary" if f["binary"] else "%6s %6s" % ("+%d" % f["added"],
                                                              "-%d" % f["deleted"])
            out.append("  %13s  %-7s %s" % (lines, note, path))
        rest = group[top:]
        if rest:
            out.append("  ... %d more: %s" % (len(rest), signed(sum(f["added"] for f in rest),
                                                               sum(f["deleted"] for f in rest))))
    if prof["submodules"]:
        out.append("")
        out.append("submodules (each pointer stands for the submodule's own change):")
        for detail in prof["submodules"]:
            out.extend(submodule_lines(detail))
    if prof["commits"]:
        out.append("")
        out.append("By commit (production code | tests and generated output | the rest):")
        for c in prof["commits"]:
            if "kinds" not in c:
                out.append("  %s  (not profiled; more than %d commits)"
                           % (c["commit"], MAX_COMMITS))
                continue
            k = c["kinds"]
            rest = [k[key] for key in ("docs", "build")]
            bumps = " (bumps %s)" % ", ".join(c["submodules"]) if c["submodules"] else ""
            out.append("  %s  %-12s | %-12s | %-10s  %s%s" % (
                c["commit"], signed(k["code"]["added"], k["code"]["deleted"]),
                signed(k["tests"]["added"] + k["generated"]["added"],
                       k["tests"]["deleted"] + k["generated"]["deleted"]),
                signed(sum(r["added"] for r in rest), sum(r["deleted"] for r in rest)),
                c["subject"][:72], bumps))
    return "\n".join(out)


def main(argv):
    parser = argparse.ArgumentParser(
        description="Show where the lines of a change go: production code, submodule pointers, "
                    "tests, generated test output, docs, and build files.")
    parser.add_argument("range", help="BASE, BASE..HEAD, or BASE...HEAD")
    parser.add_argument("--top", type=int, default=8, help="largest files listed per kind")
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    args = parser.parse_args(argv)
    try:
        prof = profile(args.range)
    except GitError as exc:
        print("error: %s" % exc, file=sys.stderr)
        return 2
    if args.json:
        for c in prof["commits"]:
            c.pop("full", None)
        print(json.dumps(prof, indent=2))
    else:
        print(as_text(prof, args.top))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
