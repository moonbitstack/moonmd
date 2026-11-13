#!/usr/bin/env python3
"""Write the conformance corpora out as Markdown files.

The cases the test package replays are MoonBit literals; the differential run
against the reference implementation needs the same documents as files. Both
come from the same generated suite, so what is compared is exactly what the
tests replay.

Usage: python scripts/gen_interop_corpus.py <directory>
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SUITES = {
    "commonmark": ROOT / "src" / "tests" / "spec" / "commonmark_suite.mbt",
    "gfm": ROOT / "src" / "tests" / "spec" / "gfm_suite.mbt",
}
CASE = re.compile(
    r'Case::\{\s*example:\s*(\d+),\s*section:\s*"((?:[^"\\]|\\.)*)",\s*'
    r'markdown:\s*"((?:[^"\\]|\\.)*)",\s*html:\s*"((?:[^"\\]|\\.)*)",\s*\}',
    re.S,
)
ESCAPE = re.compile(r"\\(.)|\\u\{([0-9A-Fa-f]+)\}")


def unescape(text: str) -> str:
    def one(match: re.Match[str]) -> str:
        if match.group(2):
            return chr(int(match.group(2), 16))
        char = match.group(1)
        return {"n": "\n", "t": "\t", "r": "\r", '"': '"', "\\": "\\"}.get(char, char)

    return ESCAPE.sub(one, text)


def cases(path: Path):
    text = path.read_text(encoding="utf-8")
    for match in CASE.finditer(text):
        # A case whose expected output is <IGNORE> is a crash regression: the
        # suite does not pin what it renders, so there is nothing to compare.
        if match.group(4) == "<IGNORE>\\n":
            continue
        yield int(match.group(1)), match.group(2), unescape(match.group(3))


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    total = 0
    for name, path in SUITES.items():
        if not path.exists():
            print(f"missing suite: {path}", file=sys.stderr)
            return 1
        for number, section, markdown in cases(path):
            (out / f"{name}-{number:03d}.md").write_text(markdown, encoding="utf-8", newline="")
            total += 1
    print(f"wrote {total} documents to {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
