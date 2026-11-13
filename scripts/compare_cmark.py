#!/usr/bin/env python3
"""Compare this library against the reference implementation, both ways.

Every document of the conformance corpora is rendered twice: once by this
library, once by `cmark-gfm`. The HTML has to agree. Then the Markdown this
library writes back is handed to `cmark-gfm` as well, and that HTML has to
agree with the first: the writer emits Markdown another reader accepts.

Usage:
  python scripts/compare_cmark.py --cmark <cmark-gfm> --engine <engine.js>
                                  [--node node] [--flavor gfm|commonmark]
                                  [--limit N] [--quiet]
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_interop_corpus import SUITES, cases  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
EXTENSIONS = ["table", "strikethrough", "autolink", "tasklist", "tagfilter", "footnotes"]

# The reference implements CommonMark 0.29; this library implements 0.31.2, and
# the corpora replayed here are 0.31.2's. These examples are the ones where the
# specification changed between the two, so the reference is the one that is
# behind. Each is listed in README under "Conformance".
KNOWN_DIVERGENCES = {
    "commonmark-028.md": "a character reference above U+10FFFF is text in 0.31.2, U+FFFD in 0.29",
    "commonmark-354.md": "a currency sign is not punctuation in 0.31.2, so it does not close emphasis there",
    "commonmark-389.md": "nested strong emphasis is kept by 0.31.2 and collapsed by 0.29",
    "commonmark-417.md": "nested strong emphasis is kept by 0.31.2 and collapsed by 0.29",
    "commonmark-425.md": "nested strong emphasis is kept by 0.31.2 and collapsed by 0.29",
    "commonmark-426.md": "nested strong emphasis is kept by 0.31.2 and collapsed by 0.29",
    "commonmark-427.md": "nested strong emphasis is kept by 0.31.2 and collapsed by 0.29",
    "commonmark-464.md": "nested strong emphasis is kept by 0.31.2 and collapsed by 0.29",
    "commonmark-465.md": "nested strong emphasis is kept by 0.31.2 and collapsed by 0.29",
    "commonmark-466.md": "nested strong emphasis is kept by 0.31.2 and collapsed by 0.29",
    "commonmark-468.md": "nested strong emphasis is kept by 0.31.2 and collapsed by 0.29",
}


def write_corpus(directory: Path, flavor: str) -> int:
    directory.mkdir(parents=True, exist_ok=True)
    path = SUITES[flavor]
    total = 0
    for number, _section, markdown in cases(path):
        (directory / f"{flavor}-{number:03d}.md").write_text(markdown, encoding="utf-8", newline="")
        total += 1
    return total


def render_with_library(node: str, engine: Path, directory: Path) -> dict[str, dict[str, str]]:
    result = subprocess.run(
        [node, str(ROOT / "scripts" / "render_corpus.mjs"), str(engine), str(directory)],
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        sys.stderr.write(result.stderr.decode("utf-8", "replace"))
        raise SystemExit("the library could not render the corpus")
    return json.loads(result.stdout)


def render_with_cmark(cmark: str, path: Path) -> str:
    command = [cmark, "--unsafe"]
    for extension in EXTENSIONS:
        command.extend(["-e", extension])
    command.append(str(path))
    result = subprocess.run(command, capture_output=True, check=False)
    if result.returncode != 0:
        raise SystemExit(f"cmark-gfm failed on {path.name}: {result.stderr.decode()}")
    return result.stdout.decode("utf-8")


def first_difference(left: str, right: str) -> str:
    left_lines = left.splitlines()
    right_lines = right.splitlines()
    for index in range(max(len(left_lines), len(right_lines))):
        one = left_lines[index] if index < len(left_lines) else "<nothing>"
        two = right_lines[index] if index < len(right_lines) else "<nothing>"
        if one != two:
            return f"line {index + 1}: {one!r} != {two!r}"
    return "identical lines, different bytes"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cmark", required=True, help="the cmark-gfm binary")
    parser.add_argument("--engine", required=True, help="the library built to JavaScript")
    parser.add_argument("--node", default="node")
    parser.add_argument("--flavor", default="all", choices=["all", "gfm", "commonmark"])
    parser.add_argument("--limit", type=int, default=5, help="how many differences to print")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()

    flavors = ["commonmark", "gfm"] if args.flavor == "all" else [args.flavor]
    engine = Path(args.engine).resolve()
    total_html = 0
    matched_html = 0
    total_round = 0
    matched_round = 0
    failures: list[str] = []
    known: list[str] = []

    with tempfile.TemporaryDirectory() as tmp:
        base = Path(tmp)
        for flavor in flavors:
            corpus = base / flavor
            count = write_corpus(corpus, flavor)
            rendered = render_with_library(args.node, engine, corpus)
            for name in sorted(rendered):
                original = corpus / name
                expected = render_with_cmark(args.cmark, original)
                ours = rendered[name]["html"]
                total_html += 1
                if ours == expected:
                    matched_html += 1
                elif name in KNOWN_DIVERGENCES:
                    known.append(f"{name} (html): {KNOWN_DIVERGENCES[name]}")
                else:
                    failures.append(
                        f"{name} (html): {first_difference(ours, expected)}"
                    )
                written = base / f"{flavor}-round" / name
                written.parent.mkdir(parents=True, exist_ok=True)
                written.write_text(rendered[name]["markdown"], encoding="utf-8", newline="")
                again = render_with_cmark(args.cmark, written)
                total_round += 1
                if again == expected:
                    matched_round += 1
                elif name in KNOWN_DIVERGENCES:
                    known.append(f"{name} (markdown round trip): {KNOWN_DIVERGENCES[name]}")
                else:
                    failures.append(
                        f"{name} (markdown round trip): {first_difference(again, expected)}"
                    )
            if not args.quiet:
                print(f"{flavor}: {count} documents replayed")

    for line in failures[: args.limit]:
        print(line)
    if len(failures) > args.limit:
        print(f"... and {len(failures) - args.limit} more differences")

    print(
        f"html: {matched_html}/{total_html} agree with cmark-gfm; "
        f"markdown written back: {matched_round}/{total_round} read the same; "
        f"{len(known)} known differences (0.29 against 0.31.2)"
    )
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
