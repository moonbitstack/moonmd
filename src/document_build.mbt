// Building the public tree out of the scratch tree: the block phase left
// strings, and this is where they become inlines.

///|
/// The blocks inside `parent`, in order.
fn build_blocks(
  tree : Tree,
  refs : Map[String, Reference],
  flavor : Flavor,
  parent : Int32,
  stop_at : Int32,
) -> Array[Block] {
  let out : Array[Block] = []
  let mut node = tree.nodes[parent].first_child
  while node >= 0 && node != stop_at {
    match tree.nodes[node].kind {
      Paragraph => {
        let text = tree.nodes[node].content.to_string()
        out.push(Paragraph(parse_inlines(text, refs, flavor)))
      }
      Heading => {
        let text = tree.nodes[node].content.to_string()
        out.push(
          Heading({
            level: tree.nodes[node].level,
            content: parse_inlines(text, refs, flavor),
          }),
        )
      }
      Code => {
        let text = tree.nodes[node].content.to_string()
        out.push(
          Code({
            info: tree.nodes[node].info,
            text,
            fenced: tree.nodes[node].fenced,
          }),
        )
      }
      Html => out.push(Html(tree.nodes[node].content.to_string()))
      ThematicBreak => out.push(Break)
      Quote => out.push(Quote(build_blocks(tree, refs, flavor, node, -1)))
      List => out.push(List(build_list(tree, refs, flavor, node)))
      Table => out.push(Table(build_table(tree, refs, flavor, node)))
      FootnoteDefinition => {
        let label = tree.nodes[node].info
        out.push(
          Footnote({
            label,
            blocks: build_blocks(tree, refs, flavor, node, -1),
            number: 0,
            backrefs: 0,
          }),
        )
      }
      _ => ()
    }
    node = tree.nodes[node].next
  }
  out
}

///|
fn build_list(
  tree : Tree,
  refs : Map[String, Reference],
  flavor : Flavor,
  index : Int32,
) -> ListBlock {
  let node = tree.nodes[index]
  let kind : ListKind = match node.shape {
    Bullet(marker) => ListKind::Bullet(marker)
    Ordered(start, delimiter) => ListKind::Ordered(start, delimiter)
    NoList => ListKind::Bullet('-')
  }
  let items : Array[Item] = []
  let mut item = node.first_child
  while item >= 0 {
    items.push({
      blocks: build_blocks(tree, refs, flavor, item, -1),
      task: tree.nodes[item].task,
    })
    item = tree.nodes[item].next
  }
  { kind, tight: node.tight, items, }
}

///|
fn build_table(
  tree : Tree,
  refs : Map[String, Reference],
  flavor : Flavor,
  index : Int32,
) -> Table {
  let node = tree.nodes[index]
  let head : Array[Array[Inline]] = []
  let body : Array[Array[Array[Inline]]] = []
  let mut row = node.first_child
  while row >= 0 {
    let cells : Array[Array[Inline]] = []
    let mut cell = tree.nodes[row].first_child
    while cell >= 0 {
      cells.push(
        parse_inlines(tree.nodes[cell].content.to_string(), refs, flavor),
      )
      cell = tree.nodes[cell].next
    }
    if tree.nodes[row].header {
      for cell_inlines in cells {
        head.push(cell_inlines)
      }
    } else {
      body.push(cells)
    }
    row = tree.nodes[row].next
  }
  { align: node.align, head, body, }
}
