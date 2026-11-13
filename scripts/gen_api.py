#!/usr/bin/env python3
"""Generate `docs/api.html` from the package interface and the source comments.

The interface comes from `src/pkg.generated.mbti`, which `moon info` writes;
the prose comes from the `///` comments in the sources, including the ones on
fields, variants and methods. Nothing on the page is typed by hand, so it
cannot drift from the package: the docs workflow regenerates it and fails when
the result differs from what is committed.

Usage: python scripts/gen_api.py [--check]
"""

from __future__ import annotations

import argparse
import html
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MBTI = ROOT / "src" / "pkg.generated.mbti"
PAGE = ROOT / "docs" / "api.html"

DECL = re.compile(
    r"^pub(?:\(all\)|\(let\)|\(open\))? (?:fn|let|struct|enum|typealias|trait|suberror) "
)
TYPE_START = re.compile(
    r"^pub(?:\(all\)|\(open\))? (struct|enum|suberror|trait) ([A-Za-z0-9_]+)"
)
FUNCTION = re.compile(r"^pub fn(\[[^\]]*\])?\s+([A-Za-z0-9_:]+)")
VALUE = re.compile(r"^pub let ([A-Za-z0-9_]+) : (.+)$")
ALIAS = re.compile(r"^pub typealias ([A-Za-z0-9_]+)")
MODIFIER = re.compile(
    r"^(pub(?:\(all\)|\(let\)|\(open\))?)\s+(fn|struct|enum|let|typealias|trait|suberror)\s+"
)
MEMBER = re.compile(r"^([A-Za-z0-9_]+)")


def esc(text: str) -> str:
    return html.escape(text, quote=False)


def inline(text: str) -> str:
    return re.sub(r"`([^`]+)`", r"<code>\1</code>", esc(text))


def anchor(kind: str, name: str) -> str:
    return f"api-{kind}-{name.replace('::', '-')}"


# ---------------------------------------------------------------- comments


def paragraphs(lines: list[str]) -> str:
    """Doc lines to HTML: paragraphs and fenced blocks, inline code marked up."""
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
                out.append('<pre class="doc-code"><code>' + esc("\n".join(fence)) + "</code></pre>")
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


@dataclass
class Docs:
    """What the comments say, by declaration and by member of a type."""

    items: dict[str, str] = field(default_factory=dict)
    members: dict[str, dict[str, str]] = field(default_factory=dict)


def collect_docs() -> Docs:
    docs = Docs()
    for path in sorted((ROOT / "src").glob("*.mbt")):
        if path.name.endswith("_test.mbt") or path.name.endswith("_wbtest.mbt"):
            continue
        buf: list[str] = []
        owner: str | None = None
        in_type = False
        for line in path.read_text(encoding="utf-8").split("\n"):
            stripped = line.strip()
            if stripped.startswith("///"):
                text = stripped[3:]
                if not text.startswith("|"):
                    buf.append(text[1:] if text.startswith(" ") else text)
                continue
            # Attributes sit between a comment and what it describes.
            if stripped.startswith("#"):
                continue
            if not stripped:
                continue
            if in_type:
                if stripped == "}":
                    in_type = False
                    buf = []
                    continue
                if buf:
                    match = MEMBER.match(stripped)
                    if match:
                        known = docs.members.setdefault(owner or "", {})
                        known.setdefault(match.group(1), paragraphs(buf))
                buf = []
                continue
            if buf:
                match = DECL.match(line)
                if match:
                    rest = line[match.end():]
                    name = rest.split("(")[0].split(" ")[0].strip()
                    if name:
                        docs.items[name] = paragraphs(buf)
                    started = TYPE_START.match(line)
                    if started:
                        owner = started.group(2)
                        in_type = True
            buf = []
    return docs


# ---------------------------------------------------------------- interface


@dataclass
class Member:
    label: str
    doc: str


@dataclass
class Item:
    name: str
    kind: str
    signature: str
    doc: str = ""
    members: list[Member] = field(default_factory=list)
    methods: list[tuple[str, str, str]] = field(default_factory=list)


def balanced(text: str) -> bool:
    depth = 0
    for c in text:
        if c in "([":
            depth += 1
        elif c in ")]":
            depth -= 1
    return depth <= 0


@dataclass
class Interface:
    values: list[Item] = field(default_factory=list)
    functions: list[Item] = field(default_factory=list)
    types: list[Item] = field(default_factory=list)
    aliases: list[Item] = field(default_factory=list)


def parse_mbti() -> Interface:
    """Everything the interface declares, in the order the file lists it."""
    result = Interface()
    lines = MBTI.read_text(encoding="utf-8").split("\n")
    names = set()
    for line in lines:
        started = TYPE_START.match(line)
        if started:
            names.add(started.group(2))
    index = 0
    while index < len(lines):
        line = lines[index].rstrip()
        index += 1
        if not line.strip() or line.startswith("//"):
            continue
        while line.startswith("pub fn") and not balanced(line) and index < len(lines):
            line = line + " " + lines[index].strip()
            index += 1
        value = VALUE.match(line)
        if value:
            result.values.append(
                Item(value.group(1), "value", f"pub let {value.group(1)} : {value.group(2)}")
            )
            continue
        alias = ALIAS.match(line)
        if alias:
            result.aliases.append(Item(alias.group(1), "alias", line.rstrip(" {")))
            continue
        function = FUNCTION.match(line)
        if function:
            name = function.group(2)
            owner = name.split("::", 1)[0] if "::" in name else ""
            target = next((t for t in result.types if t.name == owner), None)
            if target is not None:
                target.methods.append((name, line, ""))
            else:
                result.functions.append(Item(name, "function", line))
            continue
        started = TYPE_START.match(line)
        if started:
            kind, name = started.group(1), started.group(2)
            members: list[Member] = []
            body = line.endswith("{")
            if body:
                while index < len(lines) and not lines[index].startswith("}"):
                    text = lines[index].strip()
                    index += 1
                    if not text or text.startswith("//"):
                        continue
                    members.append(Member(text, ""))
            item = Item(name, kind, line.rstrip(" {") if body else line)
            item.members = members
            result.types.append(item)
    # A method is listed after the type it belongs to, but not every interface
    # file is written that way; anything left over is attached now.
    strays = [item for item in result.functions if "::" in item.name]
    for item in strays:
        owner = item.name.split("::")[0]
        target = next((t for t in result.types if t.name == owner), None)
        if target is not None:
            target.methods.append((item.name, item.signature, ""))
            result.functions.remove(item)
    for item in result.types:
        item.methods.sort(key=lambda method: method[0])
    return result


# ---------------------------------------------------------------- rendering


def signature(raw: str) -> str:
    raw = raw.rstrip()
    match = MODIFIER.match(raw)
    prefix = ""
    rest = raw
    if match:
        prefix = f'<span class="kw">{match.group(1)} {match.group(2)}</span> '
        rest = raw[match.end():]
    name = re.match(r"^(\[[^\]]*\]\s*)?([A-Za-z0-9_:]+)", rest)
    if not name:
        return prefix + esc(rest)
    generic = name.group(1) or ""
    return (
        prefix
        + (f'<span class="generic">{esc(generic.strip())}</span> ' if generic else "")
        + f'<span class="name">{name.group(2)}</span>'
        + f'<span class="arg">{esc(rest[name.end():])}</span>'
    )


def render_item(item: Item, docs: Docs, kind: str) -> str:
    searchable = " ".join(
        [item.name.lower()]
        + [member.label.split(":")[0].split("(")[0].strip().lower() for member in item.members]
        + [name.split("::")[-1].lower() for name, _, _ in item.methods]
    )
    parts = [
        f'<div class="entry" id="{anchor(kind, item.name)}" '
        f'data-name="{esc(searchable)}">'
    ]
    parts.append(f'  <span class="sig">{signature(item.signature)}</span>')
    doc = docs.items.get(item.name, "")
    if doc:
        # Doc HTML is taken as written: it may hold a code block.
        parts.extend(doc.split("\n"))
    if item.members or item.methods:
        parts.append('  <div class="members">')
        for member in item.members:
            label = MEMBER.match(member.label)
            text = docs.members.get(item.name, {}).get(label.group(1) if label else "", "")
            parts.append('    <div class="member">')
            parts.append(
                f'      <span class="sig"><span class="arg">{esc(member.label)}</span></span>'
            )
            if text:
                parts.extend(text.split("\n"))
            parts.append("    </div>")
        for name, raw, _ in item.methods:
            text = docs.items.get(name, "")
            parts.append('    <div class="member">')
            parts.append(f"      <span class=\"sig\">{signature(raw)}</span>")
            if text:
                parts.extend(text.split("\n"))
            parts.append("    </div>")
        parts.append("  </div>")
    parts.append("</div>")
    return "\n".join(parts)


def render_group(anchor_name: str, heading: str, number: str, items: list[Item], docs: Docs, kind: str) -> str:
    out = [f'<section id="{anchor_name}">']
    out.append(f'  <p class="kicker"><span>§{number}</span></p>')
    out.append(f"  <h2>{heading}</h2>")
    # Entries are written at the left margin: a doc comment may hold a code
    # block, and its lines are taken as written.
    for item in items:
        out.append(render_item(item, docs, kind))
    out.append("</section>")
    return "\n".join(out)


THEME_SCRIPT = """<script>
(function () {
  try {
    var nav = performance.getEntriesByType ? performance.getEntriesByType("navigation") : [];
    var kind = nav.length ? nav[0].type : "";
    if (!kind && performance.navigation) kind = performance.navigation.type === 1 ? "reload" : "navigate";
    if (kind === "reload") {
      sessionStorage.removeItem("moonmd-theme");
      return;
    }
    var saved = sessionStorage.getItem("moonmd-theme");
    if (saved === "ink" || saved === "paper") document.documentElement.setAttribute("data-theme", saved);
  } catch (e) {}
})();
</script>"""

NAV = """<header class="masthead">
  <div class="masthead-inner">
    <a class="wordmark" href="index.html"><i class="mark"></i>moonmd <span>markdown</span></a>
    <nav class="nav" aria-label="This site">
      <a href="index.html">overview</a>
      <a href="guide.html">guide</a>
      <a href="api.html" aria-current="page">api</a>
      <a href="anatomy.html">anatomy</a>
      <a class="icon-link" href="https://github.com/moonbitstack/moonmd" aria-label="moonmd on GitHub">
        <svg viewBox="0 0 16 16" fill="currentColor" aria-hidden="true"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82a7.4 7.4 0 0 1 2-.27c.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8Z"/></svg>
      </a>
      <button class="theme-switch" type="button" aria-pressed="false" aria-label="Switch between paper and ink">
        <span class="track" aria-hidden="true"><span class="knob"></span></span><span class="label">paper</span>
      </button>
    </nav>
  </div>
</header>"""

FOOT = """<footer class="foot">
  <div class="foot-grid">
    <div class="foot-brand">
      <a class="wordmark" href="index.html"><i class="mark"></i>moonmd</a>
      <p>markdown for moonbit, read into a tree and written back out.</p>
    </div>
    <nav class="foot-col" aria-label="Pages">
      <h5>pages</h5>
      <a href="index.html">overview</a>
      <a href="guide.html">guide</a>
      <a href="api.html">api</a>
      <a href="anatomy.html">anatomy</a>
    </nav>
    <div class="foot-col">
      <h5>elsewhere</h5>
      <a href="https://github.com/moonbitstack/moonmd">github</a>
      <a href="https://mooncakes.io/docs/moonbitstack/moonmd">mooncakes</a>
      <a href="https://github.com/moonbitstack/moonmd/blob/master/LICENSE">apache-2.0</a>
    </div>
  </div>
  <div class="foot-base">
    <span>commonmark 0.31.2</span>
    <span>set in newsreader and jetbrains mono</span>
  </div>
</footer>"""


def indent(text: str, spaces: int) -> str:
    pad = " " * spaces
    return "\n".join(pad + line if line.strip() else line for line in text.split("\n"))


def rail(interface: Interface, counts: dict[str, int]) -> str:
    out = ['<aside class="rail scroll" aria-label="Contents">']
    out.append('  <label class="filter-label" for="api-filter">filter</label>')
    out.append(
        '  <input id="api-filter" class="filter" type="search" placeholder="name" '
        'autocomplete="off" spellcheck="false" aria-label="Filter the reference by name">'
    )
    out.append("  <h4>groups</h4>")
    out.append("  <ul>")
    for number, name, label, count in (
        ("01", "api-values", "values", counts["values"]),
        ("02", "api-functions", "functions", counts["functions"]),
        ("03", "api-types", "types", counts["types"]),
        ("04", "api-aliases", "aliases", counts["aliases"]),
    ):
        out.append(
            f'    <li><a href="#{name}"><span class="n">{number}</span>{label}'
            f'<span class="n count">{count}</span></a></li>'
        )
    out.append("  </ul>")
    out.append("  <h4>names</h4>")
    out.append('  <ul id="api-index">')
    listed: list[tuple[str, str]] = []
    for item in interface.values:
        listed.append((item.name, anchor("value", item.name)))
    for item in interface.functions:
        listed.append((item.name, anchor("fn", item.name)))
    for item in interface.types:
        listed.append((item.name, anchor("type", item.name)))
    for item in interface.aliases:
        listed.append((item.name, anchor("alias", item.name)))
    for name, target in sorted(listed, key=lambda pair: pair[0].lower()):
        out.append(f'    <li><a href="#{target}">{esc(name)}</a></li>')
    out.append("  </ul>")
    out.append("</aside>")
    return "\n".join(out)


def build() -> str:
    docs = collect_docs()
    interface = parse_mbti()
    for group in (interface.values, interface.functions, interface.types, interface.aliases):
        group.sort(key=lambda item: item.name.lower())
    methods = sum(len(item.methods) for item in interface.types)
    counts = {
        "values": len(interface.values),
        "functions": len(interface.functions),
        "types": len(interface.types),
        "aliases": len(interface.aliases),
    }
    body = [
        '<main class="sheet">',
        '  <div class="guide-grid">',
        indent(rail(interface, counts), 4),
        '    <div class="guide-body api-body">',
        '      <p class="kicker">the reference</p>',
        '      <h1 class="guide-title">Every public name.</h1>',
        '      <p class="lede">Generated from the package interface and the comments in the '
        "sources, so the page cannot drift from the library: the docs workflow regenerates it "
        "and fails when the result differs from what is committed.</p>",
        '      <p class="note api-count">'
        f"{counts['values']} values · {counts['functions']} functions · {methods} methods · "
        f"{counts['types']} types · one package, and the examples are not part of it.</p>",
        render_group("api-values", "values", "01", interface.values, docs, "value"),
        render_group("api-functions", "functions", "02", interface.functions, docs, "fn"),
        render_group("api-types", "types", "03", interface.types, docs, "type"),
        render_group("api-aliases", "aliases", "04", interface.aliases, docs, "alias"),
        indent(FOOT, 6),
        "    </div>",
        "  </div>",
        "</main>",
    ]

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>api — moonmd</title>
<meta name="description" content="Every public value, function and type of moonmd: generated from the package interface and the comments in the sources.">
<link rel="icon" href="favicon.svg" type="image/svg+xml">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Newsreader:ital,opsz,wght@0,6..72,300;0,6..72,400;1,6..72,300&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
<link rel="stylesheet" href="assets/style.css">
{THEME_SCRIPT}
</head>
<body>

{NAV}

{chr(10).join(body)}

<script src="assets/site.js"></script>
</body>
</html>
"""


def verify(page: str) -> list[str]:
    """Every public declaration in the interface has an entry on the page."""
    missing: list[str] = []
    names: set[tuple[str, str]] = set()
    for line in MBTI.read_text(encoding="utf-8").split("\n"):
        function = FUNCTION.match(line)
        if function:
            name = function.group(2)
            if "::" in name:
                names.add(("method", name))
            else:
                names.add(("fn", name))
        value = VALUE.match(line)
        if value:
            names.add(("value", value.group(1)))
        started = TYPE_START.match(line)
        if started:
            names.add(("type", started.group(2)))
        alias = ALIAS.match(line)
        if alias:
            names.add(("alias", alias.group(1)))
    for kind, name in sorted(names):
        if kind == "method":
            if f'<span class="name">{name}</span>' not in page:
                missing.append(name)
        elif f'id="{anchor(kind, name)}"' not in page:
            missing.append(name)
    return missing


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail if the page is out of date")
    args = parser.parse_args()
    if not MBTI.exists():
        print("run `moon info` first: src/pkg.generated.mbti is missing", file=sys.stderr)
        return 1
    page = build()
    missing = verify(page)
    if missing:
        print("these declarations have no entry: " + ", ".join(missing), file=sys.stderr)
        return 1
    if args.check:
        current = PAGE.read_text(encoding="utf-8") if PAGE.exists() else ""
        if current != page:
            print("docs/api.html is out of date: run scripts/gen_api.py", file=sys.stderr)
            return 1
        print("the reference page is up to date")
        return 0
    PAGE.write_text(page, encoding="utf-8", newline="\n")
    print(f"generated the reference page: {len(page.splitlines())} lines")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
