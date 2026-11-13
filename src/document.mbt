///|
/// A parsed document: the blocks in order, and the flavor it was read with,
/// which the HTML renderer needs for the tag filter.
pub struct Document {
  priv blocks : Array[Block]
  priv flavor : Flavor
  priv lines : Array[LineSpan]
}

///|
/// Assemble a document out of blocks, which is what a caller collecting the
/// output of a `Stream` needs in order to render it. Footnote references are
/// resolved against the definitions in the blocks, so a definition read after
/// the reference that uses it still applies.
pub fn Document::of_blocks(
  blocks : Array[Block],
  flavor~ : Flavor = flavor,
) -> Document {
  let settled = settle_footnotes(blocks, flavor)
  { blocks: settled, flavor, lines: [], }
}

///|
/// The same, for a document that was read from text: the lines each block came
/// from are carried along, and moved with the blocks that reading footnotes
/// rearranges.
fn Document::from_source(
  blocks : Array[Block],
  flavor : Flavor,
  lines : Array[LineSpan],
) -> Document {
  let settled = settle_footnotes(blocks, flavor)
  // Reading footnotes moves definitions to the end and drops the ones nothing
  // refers to, so the lines have to be put back in step with the blocks.
  let aligned = if flavor.footnotes {
    realign_lines(blocks, settled, lines)
  } else {
    lines
  }
  { blocks: settled, flavor, lines: aligned, }
}

///|
/// The top level blocks of the document, in order.
pub fn Document::blocks(self : Document) -> Array[Block] {
  self.blocks
}

///|
/// The lines of the source each top level block was read from, counted from
/// one, one entry per block of `blocks()` and in the same order. Blank lines
/// between blocks belong to neither. A document assembled with `of_blocks` was
/// not read from text, so its list is empty.
///
/// ```mbt check
/// test {
///   let document = @moonmd.parse("# One\n\ntwo\n")
///   let spans = document.lines()
///   assert_eq((spans[0].first, spans[0].last), (1, 1))
///   assert_eq((spans[1].first, spans[1].last), (3, 3))
/// }
/// ```
pub fn Document::lines(self : Document) -> Array[LineSpan] {
  self.lines
}

///|
/// The flavor this document was parsed with.
pub fn Document::flavor(self : Document) -> Flavor {
  self.flavor
}
