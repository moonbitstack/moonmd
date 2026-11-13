// Where a block came from: the lines of the source it was read from. The
// caller that splits a document by heading, or that points a reader at the
// text behind a node, needs this and nothing finer.

///|
/// A run of source lines, counted from one, that a block was read from.
pub(all) struct LineSpan {
  /// The first line of the run.
  first : Int32
  /// The last line of the run.
  last : Int32
}

///|
/// The lines each top level block was read from, one entry per block of the
/// document as it was parsed, in the order the blocks were written.
fn top_level_lines(tree : Tree) -> Array[LineSpan] {
  let out : Array[LineSpan] = []
  let mut node = tree.nodes[0].first_child
  while node >= 0 {
    out.push({
      first: tree.nodes[node].start_line + 1,
      last: tree.nodes[node].last_line + 1,
    })
    node = tree.nodes[node].next
  }
  out
}

///|
/// The lines a definition was written on, by the label it is looked up with.
/// A definition inside a quote or a list is written inside that block, so the
/// line it is given is the one the block around it starts on.
fn collect_definition_lines(
  block : Block,
  span : LineSpan,
  out : Map[String, LineSpan],
) -> Unit {
  match block {
    Footnote(footnote) => {
      let key = normalize_label(footnote.label[:])
      if key.length() > 0 && !out.contains(key) {
        out[key] = span
      }
      for child in footnote.blocks {
        collect_definition_lines(child, span, out)
      }
    }
    Quote(children) =>
      for child in children {
        collect_definition_lines(child, span, out)
      }
    List(list) =>
      for item in list.items {
        for child in item.blocks {
          collect_definition_lines(child, span, out)
        }
      }
    _ => ()
  }
}

///|
/// Put the lines back in step with the blocks a document settled into. Reading
/// footnotes takes their definitions out of the body and writes them at the
/// end, and drops the ones nothing refers to, so the entries are taken from
/// where each term now stands rather than by their first order.
fn realign_lines(
  before : Array[Block],
  after : Array[Block],
  lines : Array[LineSpan],
) -> Array[LineSpan] {
  if before.length() != lines.length() {
    return []
  }
  let definitions : Map[String, LineSpan] = Map([])
  for i, block in before {
    collect_definition_lines(block, lines[i], definitions)
  }
  let out : Array[LineSpan] = []
  let mut cursor = 0
  for block in after {
    match block {
      Footnote(footnote) => {
        let key = normalize_label(footnote.label[:])
        out.push(definitions.get(key).unwrap_or({ first: 0, last: 0, }))
      }
      _ => {
        while cursor < before.length() && is_footnote(before[cursor]) {
          cursor = cursor + 1
        }
        if cursor < lines.length() {
          out.push(lines[cursor])
          cursor = cursor + 1
        }
      }
    }
  }
  out
}

///|
fn is_footnote(block : Block) -> Bool {
  match block {
    Footnote(_) => true
    _ => false
  }
}
