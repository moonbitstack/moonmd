// The syntax tree: block level first, then the inlines inside the leaves.
//
// Every container holds its children by value, so a tree is an ordinary
// immutable value once parsing is done; the parser builds it out of mutable
// scratch structures that never escape.

///|
/// How a table column lines up its cells, taken from the delimiter row.
pub(all) enum Align {
  /// No colons in the delimiter row: the column follows the page.
  Default
  /// A colon on the left only.
  Left
  /// A colon on both ends.
  Center
  /// A colon on the right only.
  Right
}

///|
/// A heading, `level` counting the ATX `#` marks or the setext underline.
pub(all) struct Heading {
  level : Int32
  content : Array[Inline]
}

///|
/// A code block, fenced or indented. `info` is the word after the opening
/// fence, empty for indented code.
pub(all) struct Code {
  info : String
  text : String
  fenced : Bool
}

///|
/// What kind of list a `ListBlock` is, together with the marks needed to write
/// it back unchanged.
pub(all) enum ListKind {
  /// `-`, `+` or `*`.
  Bullet(Char)
  /// The first number, then `.` or `)`.
  Ordered(Int32, Char)
}

///|
/// Whether a list item is a task list item, and if so whether it is done.
pub(all) enum Task {
  /// An ordinary list item.
  Plain
  /// `[ ]`.
  Unchecked
  /// `[x]` or `[X]`.
  Checked
}

///|
/// One item of a list, with the task marker that introduced it if any.
pub(all) struct Item {
  blocks : Array[Block]
  task : Task
}

///|
/// A list, with its items and whether it is tight (no blank lines between
/// items, so their paragraphs are rendered without `<p>`).
pub(all) struct ListBlock {
  kind : ListKind
  tight : Bool
  items : Array[Item]
}

///|
/// A table: the alignment of each column, the header row, then the body rows.
/// A row holds one cell per column, and a cell holds the inlines inside it.
pub(all) struct Table {
  align : Array[Align]
  head : Array[Array[Inline]]
  body : Array[Array[Array[Inline]]]
}

///|
/// A footnote, the body of one `[^label]:` definition. `label` is the label as
/// it was written. `number` is the order the footnote is shown with, assigned in
/// the order its first reference appears in the text; `backrefs` is how many
/// references point at it.
pub(all) struct Footnote {
  label : String
  blocks : Array[Block]
  /// The number the footnote is shown with, or 0 until the document is read.
  number : Int32
  /// The references that point at the footnote, in the order they appear.
  backrefs : Int32
}

///|
/// A footnote reference, `[^label]`, and where it lands: the definition's
/// `label`, the `number` that definition is shown with, and `ref_ix`, the order
/// of this reference among the ones that point at the definition.
pub(all) struct FootnoteRef {
  /// The label of the definition the reference points at, as written.
  label : String
  /// The number the definition is shown with.
  number : Int32
  /// The order of this reference among the ones pointing at the definition.
  ref_ix : Int32
}

///|
/// A block level node.
pub(all) enum Block {
  /// A heading of `level` 1 to 6.
  Heading(Heading)
  /// A paragraph, holding its inlines.
  Paragraph(Array[Inline])
  /// A code block.
  Code(Code)
  /// A block quote, holding the blocks inside it.
  Quote(Array[Block])
  /// A bullet or ordered list.
  List(ListBlock)
  /// A table.
  Table(Table)
  /// A block of raw HTML, which the renderer escapes unless asked not to.
  Html(String)
  /// A thematic break, the line of three or more `-`, `*` or `_`.
  Break
  /// The body of a footnote definition.
  Footnote(Footnote)
}

///|
/// A line break inside a paragraph.
pub(all) enum Break {
  /// A newline in the source, which HTML renders as a space or a newline.
  Soft
  /// Two trailing spaces or a trailing backslash, which HTML renders as `<br />`.
  Hard
}

///|
/// The destination, title and content of a link or image. For an image the
/// content is the alternative text.
pub(all) struct Link {
  dest : String
  title : String
  content : Array[Inline]
}

///|
/// An inline level node.
pub(all) enum Inline {
  /// Literal text.
  Text(String)
  /// A code span, already with its newlines turned into spaces.
  Code(String)
  /// Emphasis with a single `*` or `_`.
  Emphasis(Array[Inline])
  /// Strong emphasis with a double `*` or `_`.
  Strong(Array[Inline])
  /// A link.
  Link(Link)
  /// An image.
  Image(Link)
  /// Raw inline HTML.
  Html(String)
  /// Struck out text between tildes.
  Strike(Array[Inline])
  /// A soft or hard line break.
  Break(Break)
  /// A footnote reference, `[^label]`, with the number of the definition it
  /// points at and its order among the references to that definition.
  FootnoteRef(FootnoteRef)
}

///|
/// A node as `walk` hands it to its visitor: either a block or an inline.
pub(all) enum Node {
  /// A block level node, with everything inside it.
  Block(Block)
  /// An inline level node, with everything inside it.
  Inline(Inline)
}

///|
/// Visit every node of the document, each container before its children and
/// siblings in order.
pub fn walk(document : Document, visit : (Node) -> Unit) -> Unit {
  for block in document.blocks() {
    walk_block(block, visit)
  }
}

///|
fn walk_block(block : Block, visit : (Node) -> Unit) -> Unit {
  visit(Block(block))
  match block {
    Heading(heading) => walk_inlines(heading.content, visit)
    Paragraph(content) => walk_inlines(content, visit)
    Quote(children) =>
      for child in children {
        walk_block(child, visit)
      }
    List(list) =>
      for item in list.items {
        for child in item.blocks {
          walk_block(child, visit)
        }
      }
    Table(table) => {
      for cell in table.head {
        walk_inlines(cell, visit)
      }
      for row in table.body {
        for cell in row {
          walk_inlines(cell, visit)
        }
      }
    }
    Footnote(footnote) => walk_blocks(footnote.blocks, visit)
    Code(_) | Html(_) | Break => ()
  }
}

///|
fn walk_blocks(blocks : Array[Block], visit : (Node) -> Unit) -> Unit {
  for block in blocks {
    walk_block(block, visit)
  }
}

///|
fn walk_inlines(inlines : Array[Inline], visit : (Node) -> Unit) -> Unit {
  for inline in inlines {
    visit(Inline(inline))
    match inline {
      Emphasis(children) | Strong(children) | Strike(children) =>
        walk_inlines(children, visit)
      Link(link) | Image(link) => walk_inlines(link.content, visit)
      Text(_) | Code(_) | Html(_) | Break(_) | FootnoteRef(_) => ()
    }
  }
}
