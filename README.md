# moonmd

<p align="center">
  <strong>Markdown for MoonBit.</strong><br>
  CommonMark and GitHub Flavored Markdown, read into a syntax tree and written
  back as HTML or as Markdown, whole or as it streams in.
</p>

<p align="center">
  <a href="https://moonbitstack.github.io/moonmd/"><b>Site</b></a> ·
  <a href="https://moonbitstack.github.io/moonmd/guide.html">Guide</a> ·
  <a href="https://moonbitstack.github.io/moonmd/guide.html#api">API</a> ·
  <a href="https://mooncakes.io/docs/moonbitstack/moonmd">Mooncakes</a>
</p>

<p align="center">
  <sub>
  <a href="#install">Install</a> ·
  <a href="#read-a-document">Read a document</a> ·
  <a href="#the-tree">The tree</a> ·
  <a href="#footnotes">Footnotes</a> ·
  <a href="#flavors">Flavors</a> ·
  <a href="#streaming">Streaming</a> ·
  <a href="#safety">Safety</a> ·
  <a href="#conformance">Conformance</a>
  </sub>
</p>

## Install

```sh
moon add moonbitstack/moonmd
```

## Read a document

`parse` reads a document once and hands back a `Document`. Nothing is rendered
until you ask for it, and both renderings come from the same tree.

```moonbit
test {
  let document = @moonmd.parse("# Title\n\nA *short* paragraph with a [link](/a).\n")
  assert_eq(
    document.html(safe=false),
    "<h1>Title</h1>\n<p>A <em>short</em> paragraph with a <a href=\"/a\">link</a>.</p>\n",
  )
  assert_eq(document.markdown(), "# Title\n\nA *short* paragraph with a [link](/a).\n")
}
```

`html` escapes raw HTML and refuses dangerous destinations unless you pass
`safe=false`; `markdown` writes the tree back as Markdown that reads the same
way it did.

## The tree

A `Document` holds top level `Block`s in order. There are nine block kinds and
ten inline kinds; each of the types and their fields is listed in the
[API reference](https://moonbitstack.github.io/moonmd/guide.html#api).
`walk` visits every node, each container before its children:

```moonbit
test {
  let document = @moonmd.parse("# One\n\nA [link](/a) and a *word*.\n")
  let counts = [0, 0]
  @moonmd.walk(document, fn(node) {
    match node {
      @moonmd.Block(@moonmd.Heading(_)) => counts[0] = counts[0] + 1
      @moonmd.Inline(@moonmd.Link(_)) => counts[1] = counts[1] + 1
      _ => ()
    }
  })
  assert_eq(counts, [1, 1])
}
```

## Footnotes

A `[^label]` in the text is a footnote reference; a line that opens with
`[^label]:` is its definition. The reference becomes a numbered marker, the
definition is moved to the end of the document as a notes list, and a link in
each note points back to its reference.

```moonbit
test {
  let document = @moonmd.parse("A claim[^note]\n\n[^note]: the support\n")
  let expected =
    "<p>A claim<sup class=\"footnote-ref\"><a href=\"#fn-note\" " +
    "id=\"fnref-note\" data-footnote-ref>1</a></sup></p>\n" +
    "<section class=\"footnotes\" data-footnotes>\n" +
    "<ol>\n" +
    "<li id=\"fn-note\">\n" +
    "<p>the support <a href=\"#fnref-note\" class=\"footnote-backref\" " +
    "data-footnote-backref data-footnote-backref-idx=\"1\" " +
    "aria-label=\"Back to reference 1\">\u{21A9}</a></p>\n" +
    "</li>\n</ol>\n</section>\n"
  assert_eq(document.html(safe=false), expected)
  assert_eq(document.markdown(), "A claim[^note]\n\n[^note]:\n    the support\n")
}
```

The number follows the first reference, not the definition, and a reference
with no definition stays the text it was written as. The block is a
`Footnote`; the reference is a `FootnoteRef`. Footnotes are part of `gfm` and
off in `commonmark`.

## Flavors

`Flavor` is a plain record. `gfm` is the default; `commonmark` turns every
extension off, and any field can be changed on its own:

```moonbit
test {
  assert_eq(@moonmd.parse("~~struck~~\n").html(safe=false), "<p><del>struck</del></p>\n")
  assert_eq(
    @moonmd.parse("~~struck~~\n", flavor=@moonmd.commonmark).html(safe=false),
    "<p>~~struck~~</p>\n",
  )
}
```

## Streaming

A model writes a document a token at a time. `Stream::feed` takes whatever has
arrived and returns the blocks that no later text can change; `finish` returns
the rest. A block is settled when a following line has closed it, so a chunk
may end anywhere, including in the middle of a line:

```moonbit
test {
  let stream = @moonmd.Stream::new()
  let counts = [
    stream.feed("# Hi"[:]).length(),
    stream.feed("\n\n"[:]).length(),
    stream.feed("a paragraph"[:]).length(),
    stream.finish().length(),
  ]
  assert_eq(counts, [0, 1, 0, 1])
}
```

Link reference definitions apply to the whole document, so a block that
mentions `[` waits until `finish` by default; passing `defer_links=false`
hands such a block out as soon as it closes.

## Safety

`html` defaults to `safe=true`: raw HTML is escaped, and a link whose
destination would run script keeps its text and loses its anchor.

```moonbit
test {
  assert_eq(@moonmd.parse("<div>hi</div>\n").html(), "&lt;div&gt;hi&lt;/div&gt;\n")
  assert_eq(@moonmd.parse("[bad](javascript:alert(1))\n").html(), "<p>bad</p>\n")
}
```

With `safe=false` the document is written as it was read.

## Conformance

The test suite replays the examples of the CommonMark 0.31.2 specification and
the extension corpus of the GitHub implementation. Both are generated into the
test package by `scripts/gen_spec.py`, with the version pinned.

| Corpus | Examples | Passing |
|:--|--:|--:|
| CommonMark 0.31.2 `spec.json` | 652 | 652 |
| GitHub Flavored Markdown extensions | 29 | 29 |

Every example in both corpora produces the exact HTML each expects, including
the three footnote examples (23, 24 and 25). Two further properties hold over
the same corpora:

- writing a tree back as Markdown and reading it again gives the same HTML, for
  all 652 CommonMark examples and all 29 extension examples;
- feeding an example in pieces of one, two, three, five and eight characters
  gives the same blocks as reading it whole, for the same 652 and 29 examples.

## License

Apache-2.0.
