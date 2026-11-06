#!/usr/bin/env python3
"""Generate the API section of the guide from the package interface.

The interface comes from `src/pkg.generated.mbti`, which `moon info` writes; the
prose comes from the `///` comments in the sources. Nothing here is typed by
hand, so the page cannot drift from the package without the docs workflow
noticing.
"""

from __future__ import annotations

import html
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MBTI = ROOT / "src" / "pkg.generated.mbti"
PAGE = ROOT / "docs" / "guide.html"
BEGIN = "<!-- api:begin -->"
END = "<!-- api:end -->"

DECL = re.compile(r"^pub(?:\(all\)|\(let\))? (?:fn|let|struct|enum|type) ([A-Za-z0-9_:]+)")

DOCS: dict[str, str] = {}


def esc(text: str) -> str:
    return html.escape(text, quote=False)


def inline(text: str) -> str:
    return re.sub(r"`([^`]+)`", r"<code>\1</code>", esc(text))


def clean(lines: list[str]) -> str:
    """Doc lines to HTML: paragraphs, with fenced blocks kept as code."""
    out: list[str] = []
    paragraph: list[str] = []
    fence: list[str] | None = None

    def flush() -> None:
        if paragraph:
            out.append(f'<p class="doc-p">{inline(" ".join(paragraph))}</p>')
            paragraph.clear()

    for line in lines:
        stripped = line.strip()
        if fence is not None:
            if stripped.startswith("```"):
                out.append(
                    '<pre class="doc-code"><code>' + esc("\n".join(fence)) + "</code></pre>"
                )
                fence = None
            else:
                fence.append(line.rstrip())
            continue
        if stripped.startswith("```"):
            flush()
            fence = []
            continue
        if stripped:
            paragraph.append(stripped)
        else:
            flush()
    flush()
    if fence is not None:
        out.append('<pre class="doc-code"><code>' + esc("\n".join(fence)) + "</code></pre>")
    return "\n".join(out)


def collect_docs() -> dict[str, str]:
    docs: dict[str, str] = {}
    for path in sorted((ROOT / "src").glob("*.mbt")):
        buf: list[str] = []
        for line in path.read_text(encoding="utf-8").split("\n"):
            if line.startswith("///"):
                text = line[3:]
                if text.startswith("|"):
                    continue
                buf.append(text[1:] if text.startswith(" ") else text)
                continue
            if not line.strip():
                continue
            if buf:
                match = DECL.match(line)
                if match:
                    docs[match.group(1)] = clean(buf)
                buf = []
    return docs


class Type:
    def __init__(self, name: str, signature: str):
        self.name = name
        self.signature = signature
        self.members: list[str] = []
        self.methods: list[tuple[str, str]] = []


def parse_mbti() -> tuple[list[tuple[str, str]], list[tuple[str, str]], dict[str, Type]]:
    values: list[tuple[str, str]] = []
    functions: list[tuple[str, str]] = []
    types: dict[str, Type] = {}
    lines = MBTI.read_text(encoding="utf-8").split("\n")
    index = 0
    while index < len(lines):
        line = lines[index].rstrip()
        if line.startswith("pub let "):
            name, _, kind = line[len("pub let "):].partition(" : ")
            values.append((name, kind))
        elif line.startswith("pub fn "):
            rest = line[len("pub fn "):]
            name = rest.split("(", 1)[0].strip()
            if "::" in name:
                owner = name.split("::", 1)[0]
                if owner in types:
                    types[owner].methods.append((name, line))
            else:
                functions.append((name, line))
        else:
            match = re.match(r"^pub(?:\(all\))? (struct|enum) ([A-Za-z0-9_]+)", line)
            if match:
                name = match.group(2)
                members: list[str] = []
                if line.endswith("{"):
                    index += 1
                    while index < len(lines) and not lines[index].startswith("}"):
                        body = lines[index].strip()
                        if body and not body.startswith("//"):
                            members.append(body)
                        index += 1
                item = Type(name, line)
                item.members = members
                types[name] = item
        index += 1
    return values, functions, types


def signature(raw: str) -> str:
    """Colour the modifier, the name, and what is left."""
    raw = raw.rstrip()
    if raw.endswith(" {"):
        raw = raw[:-2]
    match = re.match(r"^(pub(?:\(all\)|\(let\))?)\s+(fn|struct|enum|let|type)\s+", raw)
    prefix = ""
    rest = raw
    if match:
        prefix = f'<span class="kw">{match.group(1)} {match.group(2)}</span> '
        rest = raw[match.end():]
    name = re.match(r"^([A-Za-z0-9_:]+)", rest)
    if not name:
        return prefix + esc(rest)
    return (
        prefix
        + f'<span class="name">{name.group(1)}</span>'
        + f'<span class="arg">{esc(rest[name.end():])}</span>'
    )


def slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def entry(
    name: str,
    raw: str,
    doc: str,
    members: list[str],
    methods: list[tuple[str, str]],
) -> str:
    parts = [f'<div class="entry" id="api-{slug(name)}">']
    parts.append(f'  <span class="sig">{signature(raw)}</span>')
    if doc:
        for line in doc.split("\n"):
            parts.append(f"  {line}")
    if members or methods:
        parts.append('  <div class="members">')
        for member in members:
            parts.append(f'    <span class="sig"><span class="arg">{esc(member)}</span></span>')
        for _, method_raw in methods:
            parts.append(f'    <span class="sig">{signature(method_raw)}</span>')
        parts.append("  </div>")
    parts.append("</div>")
    return "\n".join(parts)


def render() -> str:
    values, functions, types = parse_mbti()
    out: list[str] = []

    out.append('<div class="api-group" id="api-values">')
    out.append("  <h3>values</h3>")
    for name, kind in values:
        out.append(entry(name, f"pub let {name} : {kind}", DOCS.get(name, ""), [], []))
    out.append("</div>")

    out.append('<div class="api-group" id="api-functions">')
    out.append("  <h3>functions</h3>")
    for name, raw in functions:
        out.append(entry(name, raw, DOCS.get(name, ""), [], []))
    out.append("</div>")

    out.append('<div class="api-group" id="api-types">')
    out.append("  <h3>types</h3>")
    for name in sorted(types):
        item = types[name]
        out.append(
            entry(name, item.signature, DOCS.get(name, ""), item.members, item.methods)
        )
    out.append("</div>")
    return "\n".join(out)


def main() -> int:
    global DOCS
    DOCS = collect_docs()
    page = PAGE.read_text(encoding="utf-8")
    if BEGIN not in page or END not in page:
        print("guide.html has no api region", file=sys.stderr)
        return 1
    head, rest = page.split(BEGIN, 1)
    _, tail = rest.split(END, 1)
    PAGE.write_text(
        head + BEGIN + "\n" + render() + "\n        " + END + tail,
        encoding="utf-8",
        newline="\n",
    )
    print("generated the API section")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
