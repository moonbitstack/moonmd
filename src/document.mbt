///|
/// A parsed document: the blocks in order, and the flavor it was read with,
/// which the HTML renderer needs for the tag filter.
pub struct Document {
  priv blocks : Array[Block]
  priv flavor : Flavor
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
  { blocks: settled, flavor, }
}

///|
/// The top level blocks of the document, in order.
pub fn Document::blocks(self : Document) -> Array[Block] {
  self.blocks
}

///|
/// The flavor this document was parsed with.
pub fn Document::flavor(self : Document) -> Flavor {
  self.flavor
}
