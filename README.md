# moonmd

<p align="center">
  <strong>Markdown for MoonBit.</strong><br>
  CommonMark and GitHub Flavored Markdown, read into a syntax tree and written
  back as HTML or as Markdown, whole or as it streams in.
</p>

<p align="center">
  <a href="#install">Install</a> ·
  <a href="#read-a-document">Read a document</a> ·
  <a href="#the-tree">The tree</a> ·
  <a href="#flavors">Flavors</a> ·
  <a href="#streaming">Streaming</a> ·
  <a href="#safety">Safety</a> ·
  <a href="#conformance">Conformance</a>
</p>

## Install

```sh
moon add moonbitstack/moonmd
```

## Read a document

`parse` reads a document once and hands back a `Document`. Nothing is rendered
until you ask for it, and both renderings come from the same tree.

<!-- nocheck -->

```moonbit
let document = @moonmd.parse("# Title\n\nA *short* paragraph with a [link](/a).\n")
let html = document.html(safe=false)
let markdown = document.markdown()
```

The HTML of that document is:

```html
<h1>Title</h1>
<p>A <em>short</em> paragraph with a <a href="/a">link</a>.</p>
```

`html` escapes raw HTML and refuses dangerous destinations unless you pass
`safe=false`; `markdown` writes the tree back as Markdown that reads the same
way it did.

## The tree

A `Document` holds top level `Block`s in order.

<!-- nocheck -->

```moonbit
pub(all) enum Block {
  Heading(Heading)          // level, content
  Paragraph(Array[Inline])  // a paragraph of inlines
  Code(Code)                // info, text, fenced
  Quote(Array[Block])       // a block quote
  List(ListBlock)           // kind, tight, items
  Table(Table)              // align, head, body
  Html(String)              // a block of raw HTML
  Break                     // a thematic break
}
```

An inline is one of the following. `Link` carries the destination, the title and
the content; the content of an image is its alternative text.

<!-- nocheck -->

```moonbit
pub(all) enum Inline {
  Text(String)
  Code(String)
  Emphasis(Array[Inline])
  Strong(Array[Inline])
  Link(Link)
  Image(Link)
  Html(String)
  Strike(Array[Inline])
  Break(Break)              // Soft or Hard
}
```

`walk` visits every node, each container before its children:

<!-- nocheck -->

```moonbit
let counts = [0, 0]
@moonmd.walk(document, fn(node) {
  match node {
    @moonmd.Block(@moonmd.Heading(_)) => counts[0] = counts[0] + 1
    @moonmd.Inline(@moonmd.Link(_)) => counts[1] = counts[1] + 1
    _ => ()
  }
})
```

## Flavors

`Flavor` is a plain record. `gfm` is the default, `commonmark` turns every
extension off, and any field can be changed on its own.

<!-- nocheck -->

```moonbit
pub(all) struct Flavor {
  tables : Bool          // pipe tables
  strikethrough : Bool   // ~~struck out~~
  autolinks : Bool       // www.example.com, https://example.com, a@b.example
  task_lists : Bool      // - [ ] and - [x]
  tag_filter : Bool      // keep <script> and friends out of a page
}
```

<!-- nocheck -->

```moonbit
let document = @moonmd.parse(text, flavor=@moonmd.commonmark)
```

## Streaming

A model writes a document a token at a time. `Stream::feed` takes whatever has
arrived and returns the blocks that no later text can change; `finish` returns
the rest.

<!-- nocheck -->

```moonbit
let stream = @moonmd.Stream::new()
for chunk in chunks {
  for block in stream.feed(chunk) {
    render(block)   // final already
  }
}
for block in stream.finish() {
  render(block)
}
```

A block is settled when a following line has closed it: a heading at the end of
its line, a paragraph after the blank line that ends it, a code block after its
closing fence. A line that is still being written is held back, so a chunk may
end anywhere, including in the middle of a line or of a character.

A block has to be read back from its text, so `feed` parses the unsettled tail
again on every call: the work per chunk is proportional to that tail, not to the
document.

Link reference definitions apply to the whole document, so a block that mentions
`[` waits until `finish` by default, when every definition is known. Passing
`defer_links=false` hands such a block out as soon as it closes, which is what a
reader that wants output as early as possible should do; a label defined after
its use then goes unresolved.

## Safety

`html` defaults to `safe=true`:

- raw HTML, block or inline, is escaped: `<div>` becomes `&lt;div&gt;`;
- a link to `javascript:`, `vbscript:`, `file:` or a non-image `data:` URL keeps
  its text and loses its anchor;
- an image with such a source keeps its alternative text only.

With `safe=false` the document is written as it was read, and the tag filter of
the flavor still escapes the tags that would change the meaning of a page
(`<script>`, `<style>`, `<iframe>` and the rest of the HTML raw text elements).

## Conformance

The test suite replays the examples of the CommonMark 0.31.2 specification and
the extension corpus of the GitHub implementation. Both are generated into the
test package by `scripts/gen_spec.py`, with the version pinned.

| Corpus | Examples | Passing |
|:--|--:|--:|
| CommonMark 0.31.2 `spec.json` | 652 | 652 |
| GitHub Flavored Markdown extensions | 29 | 26 |

The three that do not pass are the footnote examples (23, 24 and 25): footnote
definitions and references are not part of the tree this library hands out, so a
document using them is read as ordinary text. Everything else in that corpus —
tables, strikethrough, bare links, the tag filter, task list items — passes.

Two further properties are checked over the same corpora:

- writing a tree back as Markdown and reading it again gives the same HTML, for
  all 652 CommonMark examples and all 29 extension examples;
- feeding an example in pieces of one, two, three, five and eight characters
  gives the same blocks as reading it whole, for the same 652 and 29 examples.

## Interface

<!-- nocheck -->

```moonbit
pub fn parse(text : StringView, flavor~ : Flavor = flavor) -> Document
pub fn Document::html(Self, safe~ : Bool = true) -> String
pub fn Document::markdown(Self) -> String
pub fn Document::blocks(Self) -> Array[Block]
pub fn Document::flavor(Self) -> Flavor
pub fn Document::of_blocks(blocks : Array[Block], flavor~ : Flavor = flavor) -> Document
pub fn walk(Document, visit : (Node) -> Unit) -> Unit
pub fn Stream::new(flavor~ : Flavor = flavor, defer_links~ : Bool = true) -> Stream
pub fn Stream::feed(Self, chunk : StringView) -> Array[Block]
pub fn Stream::finish(Self) -> Array[Block]
```

`Document::of_blocks` assembles a document out of blocks, which is how a caller
turns what a `Stream` handed out into something it can render.

## License

Apache-2.0.
