// Resolving footnotes once a whole document (or the whole remaining stream)
// has been read: a reference points at a definition by its label, a definition
// is shown in the order its first reference appears, and the referenced
// definitions are written after the rest of the document. This is the phase the
// block and inline parsers defer to, because a definition may be read after the
// reference that uses it.

///|
/// A definition as it is collected: the label as written, the body, and the
/// numbering that the pass assigns to it.
priv struct FootnoteDef {
  label : String
  mut blocks : Array[Block]
  number : Int32
  refs : Int32
}

///|
/// Settle the footnotes of a document. Resolves every reference to the number
/// of the definition it points at, removes the definitions from the body, and
/// appends the referenced ones, in the order their first references appear, at
/// the end. Returns the finished blocks; a document without footnotes is
/// handed back unchanged.
fn settle_footnotes(blocks : Array[Block], flavor : Flavor) -> Array[Block] {
  if !flavor.footnotes {
    return blocks
  }
  let defs = (Map([]) : Map[String, FootnoteDef])
  collect_footnote_defs(blocks, defs)
  // A reference without a definition is settled into the text it was written
  // as, so the pass runs even when there is nothing to collect.
  let order : Array[String] = []
  let body = resolve_footnote_blocks(blocks, defs, order)
  for key in order {
    let def = defs[key]
    body.push(
      Footnote({
        label: def.label,
        blocks: def.blocks,
        number: def.number,
        backrefs: def.refs,
      }),
    )
  }
  body
}

///|
/// Collect every definition, at any depth, by the label it is looked up with.
fn collect_footnote_defs(
  blocks : Array[Block],
  defs : Map[String, FootnoteDef],
) -> Unit {
  for block in blocks {
    match block {
      Footnote(f) => {
        let key = normalize_label(f.label[:])
        if key.length() > 0 && !defs.contains(key) {
          defs[key] = { label: f.label, blocks: f.blocks, number: 0, refs: 0, }
        }
        collect_footnote_defs(f.blocks, defs)
      }
      Quote(children) => collect_footnote_defs(children, defs)
      List(list) =>
        for item in list.items {
          collect_footnote_defs(item.blocks, defs)
        }
      _ => ()
    }
  }
}

///|
/// Rebuild the blocks, resolving the references in them and removing the
/// definitions, which are kept for re-emission at the end. The numbering is
/// assigned as the references are met, in document order.
fn resolve_footnote_blocks(
  blocks : Array[Block],
  defs : Map[String, FootnoteDef],
  order : Array[String],
) -> Array[Block] {
  let out : Array[Block] = []
  for block in blocks {
    match block {
      Footnote(f) => {
        let key = normalize_label(f.label[:])
        if defs.contains(key) {
          defs[key].blocks = resolve_footnote_blocks(f.blocks, defs, order)
        }
      }
      Quote(children) =>
        out.push(Quote(resolve_footnote_blocks(children, defs, order)))
      List(list) => {
        let items : Array[Item] = []
        for item in list.items {
          items.push({
            blocks: resolve_footnote_blocks(item.blocks, defs, order),
            task: item.task,
          })
        }
        out.push(List({ kind: list.kind, tight: list.tight, items, }))
      }
      Paragraph(inlines) =>
        out.push(Paragraph(resolve_footnote_inlines(inlines, defs, order)))
      Heading(heading) =>
        out.push(
          Heading({
            level: heading.level,
            content: resolve_footnote_inlines(heading.content, defs, order),
          }),
        )
      Table(table) => {
        let head : Array[Array[Inline]] = []
        for cell in table.head {
          head.push(resolve_footnote_inlines(cell, defs, order))
        }
        let body : Array[Array[Array[Inline]]] = []
        for row in table.body {
          let cells : Array[Array[Inline]] = []
          for cell in row {
            cells.push(resolve_footnote_inlines(cell, defs, order))
          }
          body.push(cells)
        }
        out.push(Table({ align: table.align, head, body, }))
      }
      Code(_) | Html(_) | Break => out.push(block)
    }
  }
  out
}

///|
fn resolve_footnote_inlines(
  inlines : Array[Inline],
  defs : Map[String, FootnoteDef],
  order : Array[String],
) -> Array[Inline] {
  let out : Array[Inline] = []
  for inline in inlines {
    out.push(resolve_footnote_inline(inline, defs, order))
  }
  out
}

///|
fn resolve_footnote_inline(
  inline : Inline,
  defs : Map[String, FootnoteDef],
  order : Array[String],
) -> Inline {
  match inline {
    FootnoteRef(fnref) => {
      let key = normalize_label(fnref.label[:])
      if key.length() > 0 && defs.contains(key) {
        let def = defs[key]
        let number = if def.number == 0 {
          let new_number = order.length() + 1
          order.push(key)
          new_number
        } else {
          def.number
        }
        let refs = def.refs + 1
        defs[key] = { label: def.label, blocks: def.blocks, number, refs, }
        FootnoteRef({ label: def.label, number, ref_ix: refs, })
      } else {
        // A reference without a definition keeps the text it was written as.
        Text("[^\{fnref.label}]")
      }
    }
    Emphasis(children) =>
      Emphasis(resolve_footnote_inlines(children, defs, order))
    Strong(children) => Strong(resolve_footnote_inlines(children, defs, order))
    Strike(children) => Strike(resolve_footnote_inlines(children, defs, order))
    Link(link) =>
      Link({
        dest: link.dest,
        title: link.title,
        content: resolve_footnote_inlines(link.content, defs, order),
      })
    Image(link) =>
      Image({
        dest: link.dest,
        title: link.title,
        content: resolve_footnote_inlines(link.content, defs, order),
      })
    _ => inline
  }
}
