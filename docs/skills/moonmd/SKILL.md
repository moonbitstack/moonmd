---
name: moonmd
description: Read Markdown (CommonMark and GitHub Flavored Markdown) into a syntax tree, render it as HTML or as Markdown, and parse text that is still being written a chunk at a time. Use when a MoonBit program has to display, split, convert or stream Markdown.
---

# moonmd

Reads CommonMark 0.31.2 and GitHub Flavored Markdown into a `Document`, renders
that tree as HTML or back as Markdown, and parses text incrementally.

## Install and import

```sh
moon add moonbitstack/moonmd
```

```moonbit
import {
  "moonbitstack/moonmd" @moonmd,
}
```

## Render a document as HTML

`safe` is on by default: raw HTML is escaped and links that would run script keep
their text only. Pass `safe=false` when the Markdown comes from a source you
control.

```moonbit
fn to_html(markdown : String) -> String {
  @moonmd.parse(markdown[:]).html(safe=false)
}
```

## Walk the tree

Each block and inline is visited once, containers before their children.

```moonbit
fn headings(markdown : String) -> Array[String] {
  let found : Array[String] = []
  @moonmd.walk(@moonmd.parse(markdown[:]), fn(node) {
    match node {
      @moonmd.Block(@moonmd.Heading(heading)) => {
        let text = StringBuilder()
        collect_text(heading.content, text)
        found.push(text.to_string())
      }
      _ => ()
    }
  })
  found
}

fn collect_text(inlines : Array[@moonmd.Inline], out : StringBuilder) -> Unit {
  for inline in inlines {
    match inline {
      @moonmd.Text(text) => out.write_string(text)
      @moonmd.Code(code) => out.write_string(code)
      @moonmd.Emphasis(children) | @moonmd.Strong(children) | @moonmd.Strike(children) =>
        collect_text(children, out)
      @moonmd.Link(link) | @moonmd.Image(link) => collect_text(link.content, out)
      _ => ()
    }
  }
}
```

## Parse text as it arrives

`feed` returns the blocks that no later text can change; `finish` returns the
rest. A chunk may end anywhere, including in the middle of a line or of a
character.

```moonbit
fn collect(chunks : Array[String]) -> Array[@moonmd.Block] {
  let stream = @moonmd.Stream::new()
  let blocks : Array[@moonmd.Block] = []
  for chunk in chunks {
    blocks.append(stream.feed(chunk[:])[:])
  }
  blocks.append(stream.finish()[:])
  blocks
}
```

## Footnotes

A `[^label]` in the text is a reference; a line opening `[^label]:` is its
definition. The reference becomes a numbered marker, the definition is moved to
the end as a `Footnote` block, and `markdown` writes both back.

```moonbit
fn footnote_labels(markdown : String) -> Array[String] {
  let labels : Array[String] = []
  @moonmd.walk(@moonmd.parse(markdown[:]), fn(node) {
    match node {
      @moonmd.Block(@moonmd.Footnote(footnote)) => labels.push(footnote.label)
      _ => ()
    }
  })
  labels
}
```

## Rules that catch people out

- A block that mentions `[` waits for `finish` by default, because a link
  reference definition written later still applies to it. Pass
  `defer_links=false` to `Stream::new` to get those blocks earlier; a label
  defined after its use then stays literal.
- `html` with `safe=false` is what the specification's own examples expect; the
  default is the mode a page that shows untrusted Markdown wants.
- The tree is a value: `Document::blocks` and `walk` never hand out something you
  can change. Build a document out of blocks with `Document::of_blocks`.
- Tables, strikethrough, bare links, task list items, footnotes and the tag
  filter are on by default (`Flavor` `gfm`). Pass `flavor=@moonmd.commonmark`
  for plain CommonMark.
- A footnote reference with no definition stays the text it was written as.
