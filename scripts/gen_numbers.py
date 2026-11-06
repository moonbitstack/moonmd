#!/usr/bin/env python3
"""Fill the figures on the home page from the corpora and the flavor record.

The numbers on a landing page go stale quietly. These are counted from the
files the suite actually replays, so a regenerated corpus moves them and the
docs workflow notices the page was not rebuilt.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PAGE = ROOT / "docs" / "index.html"
BEGIN = "<!-- numbers:begin -->"
END = "<!-- numbers:end -->"


def count_cases(path: Path) -> int:
    return path.read_text(encoding="utf-8").count("Case::{")


def count_ignored(path: Path) -> int:
    return path.read_text(encoding="utf-8").count('"<IGNORE>\\n"')


def flavor_fields(path: Path) -> int:
    text = path.read_text(encoding="utf-8")
    block = text.split("pub(all) struct Flavor {", 1)[1].split("\n}", 1)[0]
    return len(re.findall(r"^\s+\w+ : Bool$", block, re.M))


def figures() -> list[tuple[str, str]]:
    spec = count_cases(ROOT / "src" / "tests" / "spec" / "commonmark_suite.mbt")
    extensions = count_cases(ROOT / "src" / "tests" / "spec" / "gfm_suite.mbt")
    ignored = count_ignored(ROOT / "src" / "tests" / "spec" / "gfm_suite.mbt")
    boxes = flavor_fields(ROOT / "src" / "flavor.mbt")
    return [
        (f"{spec}", "specification examples"),
        (f"{extensions - ignored}", "extension examples"),
        ("0.31.2", "commonmark version"),
        (f"{boxes}", "extensions in gfm"),
    ]


def render(items: list[tuple[str, str]]) -> str:
    rows = "\n".join(
        f'          <div><b>{value}</b><span>{label}</span></div>' for value, label in items
    )
    return f"{BEGIN}\n        <div class=\"numbers\">\n{rows}\n        </div>\n        {END}"


def main() -> int:
    page = PAGE.read_text(encoding="utf-8")
    if BEGIN not in page or END not in page:
        print("index.html has no numbers region", file=sys.stderr)
        return 1
    head, rest = page.split(BEGIN, 1)
    _, tail = rest.split(END, 1)
    PAGE.write_text(head + render(figures()) + tail, encoding="utf-8", newline="\n")
    print("filled the figures on the home page")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
