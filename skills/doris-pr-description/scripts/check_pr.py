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
"""Check an Apache Doris PR title and description against the doris-pr-description standard.

Usage:
  check_pr.py DRAFT                     DRAFT: line 1 "Title: ...", a blank line, then the body
  check_pr.py --title T --body-file B   B may be "-" to read the body from stdin
  check_pr.py --pr N [--repo R]         fetch the title and body with gh (default repo apache/doris)
  check_pr.py --self-test               check the examples in references/examples/*.md and the
                                        fields documented in references/types/*.md

Add --diff BASE..HEAD to give the size of the change, which --pr gets from GitHub, and --json
for machine-readable output.

The checker verifies structure only: the title format, the declared PR type, the
sections (Background first), the required fields of that type, the Change map of a large
diff, the Check List lines (including the pre-submission status), the Feature issue rule,
leftover placeholders, and length.
It cannot tell whether an answer is true or useful.

Exit status: 0 ready for review (warnings allowed), 1 not ready, 2 usage error.
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

# Required fields are listed as alternative sets; a PR needs every field of one set.
# Keep the labels in sync with references/types/*.md (--self-test checks this).
SPEC = {
    "Bugfix": {
        "tags": ("fix",),
        "required": (("Frequency", "Root cause", "Why existing tests missed it", "Fix",
                      "Other paths and branches"),),
        "conditional": ("Configs and defaults",),
    },
    "Performance": {
        "tags": ("opt",),
        "required": (("Why it was slow", "Optimization", "Results", "Applicability and cost"),),
        "conditional": (),
    },
    "Feature": {
        "tags": ("feature",),
        "required": (("Scope", "Design", "Usage", "Default behavior", "Compatibility"),),
        "conditional": ("Persistence and failure handling", "Security and privileges",
                        "Deployment modes", "Follow-up plan"),
        "issue_required": True,
    },
    "Enhancement": {
        "tags": ("improvement",),
        "required": (("Before and after", "Configs and defaults", "Impact on existing users"),),
        "conditional": ("Results", "Migration"),
    },
    "Refactor": {
        "tags": ("refactor",),
        "required": (("Moves vs. logic changes", "Behavior change", "Compatibility",
                      "Performance impact", "Rollback"),),
        "conditional": (),
    },
    "Test": {
        "tags": ("test",),
        "required": (("Scenarios", "What existing tests miss", "Fails when broken"),
                     ("Failure", "Cause", "Stability evidence")),
        "conditional": ("External dependencies", "Removed tests"),
    },
    "Build/CI/Chore": {
        "tags": ("chore",),
        "required": (("Affected", "Developer and release impact", "License and third-party",
                      "Rollback"),),
        "conditional": ("CI permissions and secrets",),
    },
    "Revert": {
        "tags": ("revert",),
        "required": (("Why not fix forward", "Original author notified", "Follow-up"),),
        "conditional": ("Completeness", "Workaround"),
        "related_pr_required": True,
    },
    "Release/Dependency": {
        "tags": ("deps",),
        "required": (("Versions", "Upstream changes", "Compatibility", "Rollback"),),
        "conditional": (),
    },
    "Other": {
        "tags": ("other",),
        "required": (("Why Other",),),
        "conditional": (),
    },
}

# Fields any type may add. "Behavior change" explains a "Behavior changed: Yes"; "Change map"
# opens Details when the diff is large.
UNIVERSAL_CONDITIONAL = ("Behavior change", "Change map")
# A diff with more changed lines (added plus deleted) than this needs a Change map.
CHANGE_MAP_THRESHOLD = 300
CHANGE_MAP_WORD_LIMIT = 250

TYPE_FILES = {
    "bugfix": "Bugfix", "performance": "Performance", "feature": "Feature",
    "enhancement": "Enhancement", "refactor": "Refactor", "test": "Test",
    "build-ci-chore": "Build/CI/Chore", "revert": "Revert",
    "release-dependency": "Release/Dependency", "other": "Other",
}


def norm(text):
    return re.sub(r"[^a-z0-9]+", "", text.lower())


TYPE_BY_NORM = {norm(name): name for name in SPEC}
TAG_TO_TYPE = {tag: name for name, spec in SPEC.items() for tag in spec["tags"]}
# Tags seen in Doris history that are not tags of this standard, and the tag to use instead.
TAG_ALIASES = {"feat": "feature", "improve": "improvement", "enhancement": "improvement",
               "enhance": "improvement", "bug": "fix", "bugfix": "fix", "hotfix": "fix",
               "perf": "opt", "optimize": "opt", "optimization": "opt", "performance": "opt",
               "doc": "chore", "docs": "chore", "ci": "chore", "build": "chore", "tests": "test",
               "dep": "deps", "dependency": "deps"}

SECTION_KEYS = {
    norm("Background"): "background",
    norm("What problem does this PR solve?"): "problem",
    norm("Details"): "details",
    norm("Testing"): "testing",
    norm("Notes for Reviewers"): "notes",
    norm("Release note"): "release",
    norm("Release notes"): "release",
    norm("Check List (For Author)"): "checklist",
    norm("Check List"): "checklist",
    norm("AI Disclosure"): "ai",
}
SECTION_NAMES = {
    "background": "Background",
    "problem": "What problem does this PR solve?", "details": "Details", "testing": "Testing",
    "notes": "Notes for Reviewers", "release": "Release note",
    "checklist": "Check List (For Author)", "ai": "AI Disclosure",
}
REQUIRED_SECTIONS = ("background", "problem", "details", "testing", "release", "checklist", "ai")
# Background has its own length limit and is left out of the description's word count.
BACKGROUND_WORD_LIMIT = 150

# The repository's title check (.github/workflows/title-checker.yml), unanchored like its grep.
REPO_TITLE_CHECK = re.compile(r"\[([a-zA-Z0-9 _-])+\]\(([a-zA-Z0-9 _-])+\)(.*)")
TITLE_RE = re.compile(r"^\[(?P<tag>[^\]]+)\]\((?P<scope>[^)]+)\)(?P<space>\s*)(?P<summary>.*)$")
REVERT_RE = re.compile(r'^Revert\s+"(?P<orig>.+)"\s*$')
REVERT_TAG_RE = re.compile(r'^\[revert\]\((?P<scope>[^)]+)\)\s+Revert\s+"(?P<orig>.+)"\s*$')

HEADER_RE = re.compile(
    r"^\s*(?:[-*]\s+)?(?:\*\*)?(?P<label>Issue Number|Related PRs?|PR Type|Problem Summary)"
    r"(?:\*\*)?\s*:\s*(?:\*\*)?\s*(?P<value>.*?)\s*$", re.I)
FIELD_RE = re.compile(r"^[-*]\s+\*\*(?P<label>[^*\n]+?)\s*:?\s*\*\*\s*:?\s*(?P<value>.*)$")
CHECK_RE = re.compile(
    r"^\s*[-*]\s+(?:\*\*)?(?P<label>Behavior changed|Does this need documentation|"
    r"Pre-submission status)(?:\*\*)?"
    r"\s*(?:\?\s*:?|:)\s*(?:\*\*)?\s*(?P<value>.*?)\s*$", re.I)
# The pre-submission status is one of these, and the last two say what is missing or why.
STATUS_RE = re.compile(r"^(?P<status>ready|partially verified|not ready)\b(?P<rest>.*)$", re.I)
STATUS_NAMES = {"ready": "Ready", "partially verified": "Partially verified",
                "not ready": "Not ready"}
AI_RE = re.compile(
    r"^\s*[-*]\s+(?:\*\*)?(?P<label>Tool|Generated|Human review|Prompts?)(?:\*\*)?\s*:\s*(?:\*\*)?"
    r"\s*(?P<value>.*?)\s*$", re.I)
AI_REQUIRED = ("Tool", "Generated", "Human review")
# Prompts is optional: omit it when the prompts are unknown instead of writing one of these.
NOT_STATED = {"not stated", "none", "unknown", "not available"}
PROMPTS_WORD_LIMIT = 100

ISSUE_REF = re.compile(r"#\d+|/issues/\d+")
PR_REF = re.compile(r"#\d+|/pull/\d+")
# A TODO runs to the end of its sentence, so that text after it on the same line is not taken in.
TODO_RE = re.compile(r"TODO\(author\)[^\n]*?(?:[.?!](?=\s)|$)", re.I)
OLD_PLACEHOLDER_RE = re.compile(r"#xxx\b", re.I)
ANGLE_RE = re.compile(r"<(?P<inner>[^<>\n]+)>")
HTML_TAG_RE = re.compile(
    r"^/?(a|img|br|p|div|span|details|summary|sub|sup|kbd|b|i|em|strong|code|pre|table|"
    r"thead|tbody|tr|td|th|ul|ol|li|hr|h[1-6]|picture|source|video)\b", re.I)
SKELETON_WORDS = {"issue", "pr", "relation", "field", "answer", "optional", "title", "type",
                  "author", "login", "tag", "scope", "summary", "n"}
EMPTY_VALUES = {"", "-", "n/a", "na", "tbd", "todo", "...", "…", "?"}


class Report:
    def __init__(self, title):
        self.title = title
        self.type = None
        self.status = None
        self.errors, self.todos, self.warnings = [], [], []

    def error(self, where, msg):
        self.errors.append({"where": where, "message": msg})

    def todo(self, where, msg):
        self.todos.append({"where": where, "message": msg})

    def warn(self, where, msg):
        self.warnings.append({"where": where, "message": msg})

    @property
    def ready(self):
        return not self.errors and not self.todos

    def as_dict(self):
        return {"title": self.title, "type": self.type, "ready": self.ready,
                "pre_submission_status": self.status,
                "errors": self.errors, "todos": self.todos, "warnings": self.warnings}

    def as_text(self):
        out = ["Title: " + (self.title or "(empty)"), "Type:  " + (self.type or "(unknown)")]
        for kind, items in (("error", self.errors), ("todo", self.todos),
                            ("warning", self.warnings)):
            for item in items:
                out.append("%-8s %s: %s" % (kind, item["where"], item["message"]))
        verdict = "READY" if self.ready else "NOT READY"
        out.append("Result: %s (%d errors, %d todos, %d warnings)"
                   % (verdict, len(self.errors), len(self.todos), len(self.warnings)))
        return "\n".join(out)


def is_empty(value):
    return re.sub(r"\s+", " ", value).strip().rstrip(".").lower() in EMPTY_VALUES


def word_count(text):
    # "61,886,854,661" is one word, as are identifiers such as "be/src/a.cpp".
    return len(re.findall(r"[A-Za-z0-9][A-Za-z0-9'._/-]*(?:,\d{3})*", text))


def reviewer_prose(sections):
    """The prose that the length limit applies to: no Background, header lines, tables, code
    blocks, Change map, Check List, AI Disclosure, or TODO(author) markers."""
    out = []
    for sec in sections:
        if sec["key"] in ("background", "checklist", "ai"):
            continue
        in_map = False
        for text, in_fence in sec["lines"]:
            if sec["key"] == "details" and not in_fence:
                field = FIELD_RE.match(text)
                if field:
                    in_map = norm(field.group("label")) == norm("Change map")
            if in_map or in_fence or text.lstrip().startswith("|"):
                continue
            if sec["key"] == "problem":
                match = HEADER_RE.match(text)
                if match:
                    if norm(match.group("label")) != "problemsummary":
                        continue
                    text = match.group("value")
            out.append(TODO_RE.sub("", text))
    return "\n".join(out)


def strip_comments(body):
    """Remove HTML comments, which GitHub does not show, keeping one line for each input line.
    Return the visible text and the indexes of the lines that held a comment. Fenced code
    blocks and inline code are left as they are."""
    visible, commented = [], set()
    fence, in_comment = None, False
    for index, raw in enumerate(body.split("\n")):
        if fence:
            visible.append(raw)
            if re.match("^" + re.escape(fence[0]) + "{%d,}\\s*$" % fence[1], raw.strip()):
                fence = None
            continue
        kept, rest = [], raw
        while rest:
            if in_comment:
                end = rest.find("-->")
                in_comment = end < 0
                rest = "" if in_comment else rest[end + 3:]
                commented.add(index)
                continue
            masked = re.sub(r"`[^`]*`", lambda m: "x" * len(m.group(0)), rest)
            start = masked.find("<!--")
            if start < 0:
                kept.append(rest)
                break
            kept.append(rest[:start])
            rest = rest[start + 4:]
            in_comment = True
            commented.add(index)
        line = "".join(kept)
        visible.append(line)
        opening = None if in_comment else re.match(r"^(`{3,}|~{3,})", line.strip())
        if opening:
            fence = (opening.group(1)[0], len(opening.group(1)))
    return "\n".join(visible), commented


def split_sections(body, commented=frozenset()):
    """Split the body at headings, keeping fenced code blocks intact. `commented` holds the
    indexes of the lines that strip_comments removed a comment from."""
    sections = []
    current = {"key": "preamble", "heading": "(before the first heading)", "lines": [],
               "comment": False}
    fence = None
    for index, raw in enumerate(body.split("\n")):
        stripped = raw.strip()
        if fence:
            current["lines"].append((raw, True))
            if re.match("^" + re.escape(fence[0]) + "{%d,}\\s*$" % fence[1], stripped):
                fence = None
            continue
        opening = re.match(r"^(`{3,}|~{3,})", stripped)
        heading = None if opening else re.match(r"^#{1,6}\s+(.*?)\s*#*\s*$", raw)
        if heading:
            sections.append(current)
            text = heading.group(1)
            current = {"key": SECTION_KEYS.get(norm(text), "unknown"), "heading": text,
                       "lines": [], "comment": False}
        else:
            current["lines"].append((raw, bool(opening)))
            if opening:
                fence = (opening.group(1)[0], len(opening.group(1)))
        if index in commented:
            current["comment"] = True
    sections.append(current)
    return sections


def text_of(lines):
    return "\n".join(text for text, _ in lines).strip()


def check_title(rep, title, pr_type):
    where = "title"
    if not title:
        rep.error(where, "the title is empty")
        return None
    if not REPO_TITLE_CHECK.search(title):
        hint = ('use [revert](<scope>) Revert "<original title>"' if pr_type == "Revert"
                else "use [<tag>](<scope>) <Summary>")
        rep.error(where, "fails the repository title check, which requires [type](scope); " + hint)
    if REVERT_RE.match(title) or REVERT_TAG_RE.match(title):
        if pr_type and pr_type != "Revert":
            rep.error(where, "the title is a revert but PR Type is %s; use Revert" % pr_type)
        return "Revert"
    match = TITLE_RE.match(title)
    if not match:
        if pr_type == "Revert":
            rep.error(where, 'a revert title is Revert "<original title>"')
        elif REPO_TITLE_CHECK.search(title):
            rep.error(where, "the [tag](scope) prefix must start the title")
        return None
    tag, scope = match.group("tag").strip(), match.group("scope").strip()
    summary = match.group("summary").strip()
    tag_type = TAG_TO_TYPE.get(tag)
    if pr_type == "Revert":
        rep.error(where, 'a revert title is Revert "<original title>"')
    elif tag_type is None:
        if tag.lower() in TAG_TO_TYPE:
            rep.error(where, "write the tag in lowercase: [%s]" % tag.lower())
        elif tag.lower() in TAG_ALIASES:
            rep.error(where, "[%s] is not a tag of this standard; use [%s]"
                      % (tag, TAG_ALIASES[tag.lower()]))
        else:
            rep.error(where, "[%s] is not a title tag; valid tags: %s"
                      % (tag, ", ".join("[%s]" % t for t in TAG_TO_TYPE)))
    elif pr_type and tag_type != pr_type:
        rep.error(where, "[%s] is the tag for %s, but PR Type is %s; use [%s]"
                  % (tag, tag_type, pr_type, SPEC[pr_type]["tags"][0]))
    if scope != scope.lower():
        rep.warn(where, "write the scope in lowercase: (%s)" % scope.lower())
    if not match.group("space"):
        rep.warn(where, "add a space after the (scope)")
    if not summary:
        rep.error(where, "the summary after [tag](scope) is empty")
    else:
        if word_count(summary) < 3:
            rep.warn(where, "the summary is too vague to tell what changes")
        if summary.endswith("."):
            rep.warn(where, "drop the trailing period")
    if len(title) > 100:
        rep.warn(where, "%d characters; aim for about 80" % len(title))
    return tag_type


def scan_lines(rep, where, lines):
    """Placeholders, leftover template markup, and TODO(author) markers."""
    for text, in_fence in lines:
        for todo in TODO_RE.findall(text):
            rep.todo(where, todo.strip())
        if in_fence:
            continue
        plain = re.sub(r"`[^`]*`", "", text)
        if OLD_PLACEHOLDER_RE.search(plain):
            rep.error(where, "placeholder #xxx left from the old template")
        for angle in ANGLE_RE.finditer(plain):
            inner = angle.group("inner").strip()
            if inner.startswith("!--") or HTML_TAG_RE.match(inner):
                continue
            if " " in inner or inner.lower() in SKELETON_WORDS:
                rep.error(where, "template placeholder left: <%s>" % inner)
        if re.match(r"^\s*[-*]\s+\[[ xX]\]", plain):
            rep.warn(where, "checkbox left from the old template; state the answer instead")


def parse_fields(lines):
    fields, stray, current = [], [], None
    for text, in_fence in lines:
        match = None if in_fence else FIELD_RE.match(text)
        if match:
            current = {"label": match.group("label").strip(), "lines": [(match.group("value"),
                                                                          False)]}
            fields.append(current)
        elif current is not None:
            current["lines"].append((text, in_fence))
        elif text.strip():
            stray.append(text)
    return fields, stray


def check_body(rep, body, title_type, commented=frozenset(), changed_lines=None):
    sections = split_sections(body, commented)
    by_key = {}
    for sec in sections:
        if sec["comment"]:
            rep.warn(SECTION_NAMES.get(sec["key"], sec["heading"]),
                     "HTML comment left; delete the template's guidance comments")
        # Details is scanned field by field below, for better locations.
        if sec["key"] != "details":
            scan_lines(rep, SECTION_NAMES.get(sec["key"], sec["heading"]), sec["lines"])
        if sec["key"] == "unknown":
            rep.warn("## " + sec["heading"], "section not in the standard layout")
        elif sec["key"] == "preamble":
            if text_of(sec["lines"]):
                rep.warn("description", "text before the first heading")
        elif sec["key"] in by_key:
            rep.warn(SECTION_NAMES[sec["key"]], "section appears more than once")
            if sec["key"] == "details":
                scan_lines(rep, "Details", sec["lines"])
        else:
            by_key[sec["key"]] = sec

    for key in REQUIRED_SECTIONS:
        if key not in by_key:
            rep.error(SECTION_NAMES[key], "section missing")

    background = by_key.get("background")
    if background:
        first = next((sec for sec in sections if sec["key"] != "preamble"), None)
        if first is not background:
            rep.warn("Background", "open the description with it, before %s"
                     % SECTION_NAMES["problem"])
        text = text_of([(t, f) for t, f in background["lines"] if not f])
        if is_empty(text):
            rep.error("Background", "empty; give reviewers the context of the feature or module "
                      "that the PR changes")
        elif word_count(text) > BACKGROUND_WORD_LIMIT:
            rep.warn("Background", "%d words; aim for about 100, and leave the problem to "
                     "Problem Summary" % word_count(text))

    # Header lines and Problem Summary.
    header, summary_lines = {}, None
    problem = by_key.get("problem")
    if problem:
        for text, in_fence in problem["lines"]:
            if summary_lines is not None:
                summary_lines.append((text, in_fence))
                continue
            match = None if in_fence else HEADER_RE.match(text)
            if not match:
                if text.strip():
                    rep.warn("Problem Summary", "text before the Problem Summary label: %s"
                             % text.strip()[:60])
                continue
            label = norm(match.group("label"))
            label = "relatedpr" if label == "relatedprs" else label
            if label == "problemsummary":
                summary_lines = [(match.group("value"), False)]
            else:
                header[label] = match.group("value")

    declared = header.get("prtype")
    pr_type = None
    if declared is None:
        rep.error("PR Type", "line missing; add 'PR Type: <type>'")
    elif norm(declared) in TYPE_BY_NORM:
        pr_type = TYPE_BY_NORM[norm(declared)]
        if declared.strip() != pr_type:
            rep.warn("PR Type", "spell it as in the standard: %s" % pr_type)
    else:
        rep.error("PR Type", "'%s' is not a PR type; use one of: %s"
                  % (declared, ", ".join(SPEC)))
    effective = pr_type or title_type
    rep.type = pr_type or ("%s (from the title tag)" % title_type if title_type else None)

    issue = header.get("issuenumber")
    if issue is None:
        rep.error("Issue Number", "line missing; write 'Issue Number: None' if there is no issue")
    elif is_empty(issue):
        rep.error("Issue Number", "empty; write 'None' if there is no issue")
    elif (effective and SPEC[effective].get("issue_required") and not ISSUE_REF.search(issue)
          and not TODO_RE.search(issue)):
        # A TODO(author) here is reported as a TODO, as Rewrite mode writes it.
        rep.error("Issue Number", "a Feature PR must link an issue")

    related = header.get("relatedpr")
    if related is None:
        rep.error("Related PR", "line missing; write 'Related PR: None' if no related PR is known")
    elif is_empty(related):
        rep.error("Related PR", "empty; write 'None' if no related PR is known")
    elif effective and SPEC[effective].get("related_pr_required") and not PR_REF.search(related):
        rep.error("Related PR", "a Revert must name the reverted PR")

    if problem:
        if summary_lines is None:
            rep.error("Problem Summary", "label missing")
        else:
            summary = text_of([(t, f) for t, f in summary_lines if not f])
            if is_empty(summary):
                rep.error("Problem Summary", "empty")
            elif word_count(summary) > 150:
                rep.warn("Problem Summary", "%d words; aim for 120 or fewer, and move detail "
                         "into Details" % word_count(summary))

    # Details fields.
    details = by_key.get("details")
    seen = {}
    if details:
        fields, stray = parse_fields(details["lines"])
        if stray:
            scan_lines(rep, "Details", [(text, False) for text in stray])
            rep.warn("Details", "text outside a '- **Field:** answer' line: %s"
                     % stray[0].strip()[:60])
        for field in fields:
            key = norm(field["label"])
            if key in seen:
                rep.warn("Details", "field '%s' appears more than once" % field["label"])
            seen.setdefault(key, field)
            scan_lines(rep, "Details / " + field["label"], field["lines"])
        if effective:
            spec = SPEC[effective]
            required = {norm(label) for group in spec["required"] for label in group}
            conditional = {norm(label) for label in spec["conditional"] + UNIVERSAL_CONDITIONAL}
            conditional -= required
            known = required | conditional

            def answered(label):
                field = seen.get(norm(label))
                return field is not None and not is_empty(text_of(field["lines"]))

            groups = spec["required"]
            best = max(groups, key=lambda group: sum(answered(label) for label in group))
            if not all(answered(label) for label in best):
                for label in best:
                    field = seen.get(norm(label))
                    if field is None:
                        rep.error("Details", "missing required field '%s'" % label)
                    elif is_empty(text_of(field["lines"])):
                        rep.error("Details / " + label,
                                  "empty; answer it, or write 'None' if that is the answer")
                if len(groups) > 1:
                    rep.warn("Details", "%s PRs need one complete set of fields: %s"
                             % (effective, " | ".join(", ".join(g) for g in groups)))
            for field in fields:
                key = norm(field["label"])
                if key not in known:
                    rep.warn("Details", "'%s' is not a field of %s" % (field["label"], effective))
                elif key in conditional and is_empty(text_of(field["lines"])):
                    rep.warn("Details / " + field["label"],
                             "conditional field without an answer; drop it if it does not apply")
        change_map = seen.get(norm("Change map"))
        if change_map is not None:
            if fields[0] is not change_map:
                rep.warn("Details / Change map", "put it first in Details, right after Problem "
                         "Summary, where reviewers size the change")
            words = word_count(text_of([(t, f) for t, f in change_map["lines"]
                                        if not f and not t.lstrip().startswith("|")]))
            if words > CHANGE_MAP_WORD_LIMIT:
                rep.warn("Details / Change map", "%d words; keep the split and one line per part, "
                         "and move the reasons for single edits to Notes for Reviewers" % words)
        elif changed_lines is not None and changed_lines > CHANGE_MAP_THRESHOLD:
            rep.warn("Details", "%d changed lines; open Details with a '- **Change map:**' field: "
                     "the lines of production code, tests, generated files, and docs "
                     "(scripts/diff_profile.py), then the code in parts by the problem each "
                     "handles" % changed_lines)

    for key in ("testing", "notes", "release"):
        sec = by_key.get(key)
        if not sec:
            continue
        if is_empty(text_of(sec["lines"])):
            if key == "notes":
                rep.warn(SECTION_NAMES[key], "empty; drop the section if there is nothing to say")
            elif key == "release":
                rep.error(SECTION_NAMES[key], "empty; write 'None' if users see no change")
            else:
                rep.error(SECTION_NAMES[key], "empty; say what was run and what it shows")

    checklist = by_key.get("checklist")
    if checklist:
        found = {}
        for text, in_fence in checklist["lines"]:
            match = None if in_fence else CHECK_RE.match(text)
            if match:
                found[norm(match.group("label"))] = match.group("value")
        for label in ("Behavior changed", "Does this need documentation"):
            value = found.get(norm(label))
            if value is None:
                rep.error(SECTION_NAMES["checklist"], "line missing: '- %s: ...'" % label)
            elif is_empty(value):
                rep.error(SECTION_NAMES["checklist"], "'%s' has no answer" % label)
            elif not re.match(r"^(yes|no)\b", value.strip().lower()):
                rep.warn(SECTION_NAMES["checklist"], "'%s' should start with Yes or No" % label)
        status = found.get(norm("Pre-submission status"))
        if status is None:
            rep.error(SECTION_NAMES["checklist"], "line missing: '- Pre-submission status: ...'")
        elif is_empty(status):
            rep.error(SECTION_NAMES["checklist"], "'Pre-submission status' has no answer")
        elif not TODO_RE.search(status):
            match = STATUS_RE.match(status.strip())
            if not match:
                rep.warn(SECTION_NAMES["checklist"], "'Pre-submission status' should start with "
                         "Ready, Partially verified, or Not ready")
            else:
                rep.status = STATUS_NAMES[match.group("status").lower()]
                said = re.sub(r"[\s:;,.()–—-]", "", match.group("rest"))
                if rep.status != "Ready" and not said:
                    rep.warn(SECTION_NAMES["checklist"], "'Pre-submission status' is %s; say "
                             "what is not verified, or why it is not ready" % rep.status)
        changed = found.get(norm("Behavior changed"), "")
        explained = any(norm(label) in seen and not is_empty(text_of(seen[norm(label)]["lines"]))
                        for label in ("Behavior change", "Before and after"))
        if re.match(r"^yes\b", changed.strip().lower()) and details and not explained:
            rep.warn(SECTION_NAMES["checklist"], "Behavior changed is Yes; explain the change in "
                     "a '- **Behavior change:**' field in Details")

    ai = by_key.get("ai")
    if ai:
        # A line's value continues on indented lines, such as a numbered list under Prompts.
        found, current = {}, None
        for text, in_fence in ai["lines"]:
            match = None if in_fence else AI_RE.match(text)
            if match:
                label = norm(match.group("label"))
                label = "prompts" if label == "prompt" else label
                if label in found:
                    rep.warn(SECTION_NAMES["ai"], "'%s' appears more than once"
                             % match.group("label"))
                current = found.setdefault(label, [])
                current.append(match.group("value"))
            elif current is not None and (in_fence or not text.strip() or text[:1].isspace()):
                current.append(text.strip())
            else:
                current = None
        values = {label: " ".join(parts).strip() for label, parts in found.items()}
        for label in AI_REQUIRED:
            value = values.get(norm(label))
            if value is None:
                rep.error(SECTION_NAMES["ai"], "line missing: '- %s: ...'" % label)
            elif is_empty(value):
                rep.error(SECTION_NAMES["ai"], "'%s' has no answer" % label)
        prompts = values.get("prompts")
        if prompts is not None:
            if is_empty(prompts) or prompts.rstrip(".").lower() in NOT_STATED:
                rep.warn(SECTION_NAMES["ai"] + " / Prompts", "optional; omit the line when "
                         "the author's prompts are not available")
            elif word_count(prompts) > PROMPTS_WORD_LIMIT:
                rep.warn(SECTION_NAMES["ai"] + " / Prompts", "%d words; summarize the author's "
                         "prompts in about 80 words" % word_count(prompts))

    words = word_count(reviewer_prose(sections))
    limit = 900 if effective == "Feature" else 500
    if words > limit:
        rep.warn("description", "%d words of prose; cut what the diff already shows and anything "
                 "said twice, and keep what only the author can tell reviewers" % words)
    return pr_type


def check(title, body, changed_lines=None):
    """`changed_lines`, the added plus deleted lines of the diff, enables the Change map check."""
    title = (title or "").strip()
    body = (body or "").replace("\r\n", "\n").replace("\r", "\n")
    # Guidance comments from the template are invisible on GitHub, so they are not content.
    body, commented = strip_comments(body)
    rep = Report(title)
    # The declared type drives the title check, so read it first.
    declared = None
    for line in body.split("\n"):
        match = HEADER_RE.match(line)
        if match and norm(match.group("label")) == "prtype":
            declared = TYPE_BY_NORM.get(norm(match.group("value")))
            break
    title_type = check_title(rep, title, declared)
    scan_lines(rep, "title", [(title, False)])
    check_body(rep, body, title_type, commented, changed_lines)
    return rep


def read_draft(path):
    text = Path(path).read_text(encoding="utf-8").replace("\r\n", "\n")
    first, _, rest = text.partition("\n")
    if not first.startswith("Title:"):
        raise ValueError("%s: the first line must be 'Title: <title>'" % path)
    return first[len("Title:"):].strip(), rest.lstrip("\n")


def fetch_pr(number, repo):
    try:
        out = subprocess.run(["gh", "pr", "view", str(number), "--repo", repo, "--json",
                              "title,body,baseRefName,isDraft,additions,deletions"], check=True,
                             capture_output=True, text=True).stdout
    except FileNotFoundError:
        raise ValueError("gh is not installed")
    except subprocess.CalledProcessError as exc:
        raise ValueError("gh pr view failed: %s" % exc.stderr.strip())
    data = json.loads(out)
    changed = (data.get("additions") or 0) + (data.get("deletions") or 0)
    return (data.get("title", ""), data.get("body", "") or "", data.get("baseRefName", ""),
            data.get("isDraft"), changed)


def diff_size(spec):
    """Added plus deleted lines of a git range, from diff_profile.py beside this script."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import diff_profile
    try:
        return diff_profile.changed_lines(spec)
    except diff_profile.GitError as exc:
        raise ValueError(str(exc))


def self_test():
    root = Path(__file__).resolve().parent.parent / "references"
    failures, examples = [], 0
    for stem, pr_type in TYPE_FILES.items():
        path = root / "types" / (stem + ".md")
        example_path = root / "examples" / (stem + ".md")
        name, example_name = "types/" + path.name, "examples/" + example_path.name
        if not path.exists():
            failures.append("%s: file missing" % name)
            continue
        text = path.read_text(encoding="utf-8")
        spec = SPEC[pr_type]
        for label in [l for g in spec["required"] for l in g] + list(spec["conditional"]):
            if "**%s**" % label not in text:
                failures.append("%s: field '%s' is not documented" % (name, label))
        if not example_path.exists():
            failures.append("%s: file missing" % example_name)
            continue
        blocks = re.findall(r"^````markdown\n(.*?)\n````\s*$",
                            example_path.read_text(encoding="utf-8"), re.S | re.M)
        if not blocks:
            failures.append("%s: no example" % example_name)
        for index, block in enumerate(blocks, 1):
            examples += 1
            first, _, rest = block.partition("\n")
            if not first.startswith("Title:"):
                failures.append("%s example %d: first line must be 'Title: ...'"
                                % (example_name, index))
                continue
            rep = check(first[len("Title:"):].strip(), rest.lstrip("\n"))
            if rep.type != pr_type:
                failures.append("%s example %d: PR Type is %s" % (example_name, index, rep.type))
            for item in rep.errors + rep.todos + rep.warnings:
                failures.append("%s example %d: %s: %s"
                                % (example_name, index, item["where"], item["message"]))
    for line in failures:
        print("FAIL " + line)
    print("Self-test: %d examples in %d files, %d problems"
          % (examples, len(TYPE_FILES), len(failures)))
    return 0 if not failures else 1


def main(argv):
    parser = argparse.ArgumentParser(
        description="Check a Doris PR title and description against the doris-pr-description "
                    "standard.")
    parser.add_argument("draft", nargs="?", help="draft file: 'Title: ...', a blank line, body")
    parser.add_argument("--title", help="PR title (with --body-file)")
    parser.add_argument("--body-file", help="PR body file, or - for stdin")
    parser.add_argument("--pr", help="check an existing PR with gh")
    parser.add_argument("--repo", default="apache/doris", help="repository for --pr")
    parser.add_argument("--diff", metavar="BASE..HEAD",
                        help="the git range of the change, for the Change map check; run from the "
                             "repository (--pr takes the size from GitHub instead)")
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    parser.add_argument("--self-test", action="store_true", help="check the bundled examples")
    args = parser.parse_args(argv)

    if args.self_test:
        return self_test()
    base, is_draft, changed = None, None, None
    try:
        if args.pr:
            title, body, base, is_draft, changed = fetch_pr(args.pr, args.repo)
        elif args.draft:
            title, body = read_draft(args.draft)
        elif args.title is not None and args.body_file:
            body = (sys.stdin.read() if args.body_file == "-"
                    else Path(args.body_file).read_text(encoding="utf-8"))
            title = args.title
        else:
            parser.print_usage(sys.stderr)
            print("give a draft file, --title with --body-file, --pr, or --self-test",
                  file=sys.stderr)
            return 2
        if args.diff:
            changed = diff_size(args.diff)
    except (OSError, ValueError) as exc:
        print("error: %s" % exc, file=sys.stderr)
        return 2

    rep = check(title, body, changed)
    if base and base != "master":
        rep.warn("base branch", "the PR targets %s; this standard covers PRs against master, and "
                 "cherry-picks keep the original PR's description" % base)
    if is_draft is False and rep.status == "Not ready":
        rep.warn(SECTION_NAMES["checklist"], "the pre-submission status is Not ready; convert "
                 "the PR to a Draft")
    print(json.dumps(rep.as_dict(), indent=2) if args.json else rep.as_text())
    return 0 if rep.ready else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
