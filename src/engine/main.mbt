// The page's entry points: four functions, each taking strings and returning a
// string, so the script that calls them carries no parsing of its own.

///|
fn flavor_of(name : String) -> @md.Flavor {
  match name {
    "commonmark" => @md.commonmark
    _ => @md.gfm
  }
}

///|
/// Render Markdown as HTML, with the same two modes `Document::html` offers.
pub fn html(source : String, flavor : String, safe : Bool) -> String {
  @md.parse(source[:], flavor=flavor_of(flavor)).html(safe~)
}

///|
/// Write Markdown back out of the tree it was read into.
pub fn markdown(source : String, flavor : String) -> String {
  @md.parse(source[:], flavor=flavor_of(flavor)).markdown()
}

///|
/// Show a string as it would be written inside a MoonBit literal, shortened so
/// the tree column stays one line per node.
fn quote(text : String) -> String {
  let out = StringBuilder()
  out.write_char('"')
  let mut width = 0
  let mut i = 0
  let n = text.length()
  while i < n {
    let c = text[:].get_char(i).unwrap()
    if width >= 42 {
      out.write_string("…")
      break
    }
    match c {
      '\n' => out.write_string("\\n")
      '\t' => out.write_string("\\t")
      '"' => out.write_string("\\\"")
      _ => out.write_char(c)
    }
    width = width + 1
    i = i + c.utf16_len()
  }
  out.write_char('"')
  out.to_string()
}

///|
/// One line of context for a node: what it carries besides its children.
fn detail_of_block(block : @md.Block) -> String {
  match block {
    @md.Heading(heading) => "level \{heading.level}"
    @md.Code(code) => {
      let kind = if code.fenced { "fenced" } else { "indented" }
      let language = if code.info.is_empty() {
        kind
      } else {
        "\{code.info} · \{kind}"
      }
      let lines = line_count(code.text)
      let unit = if lines == 1 { "line" } else { "lines" }
      "\{language} · \{lines} \{unit}"
    }
    @md.List(list) => {
      let marker = match list.kind {
        @md.Bullet(mark) => "bullet \{mark}"
        @md.Ordered(start, delimiter) => "ordered \{start}\{delimiter}"
      }
      let tight = if list.tight { "tight" } else { "loose" }
      let count = list.items.length()
      let unit = if count == 1 { "item" } else { "items" }
      "\{marker} · \{count} \{unit} · \{tight}"
    }
    @md.Table(table) =>
      "\{table.head.length()} columns · \{table.body.length()} rows"
    @md.Html(_) => "raw"
    _ => ""
  }
}

///|
fn line_count(text : String) -> Int32 {
  let mut count = 1
  for c in text {
    if c == '\n' {
      count = count + 1
    }
  }
  if text.has_suffix("\n") {
    count - 1
  } else {
    count
  }
}

///|
fn detail_of_inline(inline : @md.Inline) -> String {
  match inline {
    @md.Text(text) => quote(text)
    @md.Code(code) => quote(code)
    @md.Link(link) => link.dest
    @md.Image(link) => link.dest
    @md.Html(raw) => quote(raw)
    @md.Break(hard) =>
      match hard {
        @md.Hard => "hard"
        @md.Soft => "soft"
      }
    _ => ""
  }
}

///|
fn node(name : String, detail : String, children : Array[Json]) -> Json {
  {
    "type": Json::string(name),
    "detail": Json::string(detail),
    "children": Json::array(children),
  }
}

///|
fn inline_json(inline : @md.Inline) -> Json {
  match inline {
    @md.Emphasis(children) => node("Emphasis", "", children.map(inline_json))
    @md.Strong(children) => node("Strong", "", children.map(inline_json))
    @md.Strike(children) => node("Strike", "", children.map(inline_json))
    @md.Link(link) => node("Link", link.dest, link.content.map(inline_json))
    @md.Image(link) => node("Image", link.dest, link.content.map(inline_json))
    _ => node(inline_type(inline), detail_of_inline(inline), [])
  }
}

///|
fn inline_type(inline : @md.Inline) -> String {
  match inline {
    @md.Text(_) => "Text"
    @md.Code(_) => "Code"
    @md.Emphasis(_) => "Emphasis"
    @md.Strong(_) => "Strong"
    @md.Strike(_) => "Strike"
    @md.Link(_) => "Link"
    @md.Image(_) => "Image"
    @md.Html(_) => "Html"
    @md.Break(_) => "Break"
  }
}

///|
fn block_json(block : @md.Block) -> Json {
  match block {
    @md.Heading(heading) =>
      node("Heading", detail_of_block(block), heading.content.map(inline_json))
    @md.Paragraph(inlines) => node("Paragraph", "", inlines.map(inline_json))
    @md.Quote(blocks) => node("Quote", "", blocks.map(block_json))
    @md.List(list) => {
      let items = list.items.map(fn(item) {
        let task = match item.task {
          @md.Checked => "checked"
          @md.Unchecked => "unchecked"
          @md.Plain => ""
        }
        node("Item", task, item.blocks.map(block_json))
      })
      node("List", detail_of_block(block), items)
    }
    @md.Table(table) => {
      let cells = fn(cell : Array[@md.Inline]) {
        node("Cell", "", cell.map(inline_json))
      }
      let rows = table.body.map(fn(row) { node("Row", "", row.map(cells)) })
      let head = node("Row", "header", table.head.map(cells))
      let grid : Array[Json] = [head]
      for row in rows {
        grid.push(row)
      }
      node("Table", detail_of_block(block), grid)
    }
    @md.Code(_) => node("Code", detail_of_block(block), [])
    @md.Html(_) => node("Html", detail_of_block(block), [])
    @md.Break => node("Break", "", [])
  }
}

///|
/// The tree of the document, as JSON: one node per block and one per inline,
/// each with the one line of context that matters for it.
pub fn tree(source : String, flavor : String) -> String {
  let document = @md.parse(source[:], flavor=flavor_of(flavor))
  let blocks = document.blocks().map(block_json)
  node("Document", "", blocks).stringify()
}

///|
/// Where each character starts, plus the end: chunk boundaries fall between
/// characters, never inside one.
fn char_offsets(text : String) -> Array[Int32] {
  let offsets : Array[Int32] = []
  let n = text.length()
  let mut i = 0
  while i < n {
    offsets.push(i)
    i = i + text[:].get_char(i).unwrap().utf16_len()
  }
  offsets.push(n)
  offsets
}

///|
/// The blocks a stream hands out, chunk by chunk: for each chunk that closed
/// something, the HTML of what it closed and how much text had arrived.
pub fn stream(source : String, flavor : String, size : Int32) -> String {
  let chosen = flavor_of(flavor)
  let offsets = char_offsets(source)
  let step = if size < 1 { 1 } else if size > 64 { 64 } else { size }
  let stream = @md.Stream::new(flavor=chosen)
  let steps : Array[Json] = []
  let mut k = 0
  while k + 1 < offsets.length() {
    let next = if k + step < offsets.length() - 1 {
      k + step
    } else {
      offsets.length() - 1
    }
    let blocks = stream.feed(
      source[:].clamped_view(start=offsets[k], end=offsets[next]),
    )
    if blocks.length() > 0 {
      let settled = @md.Document::of_blocks(blocks, flavor=chosen).html(
        safe=false,
      )
      steps.push({
        "at": Json::number(offsets[next].to_double()),
        "blocks": Json::number(blocks.length().to_double()),
        "html": Json::string(settled),
      })
    }
    k = next
  }
  let rest = stream.finish()
  if rest.length() > 0 {
    let settled = @md.Document::of_blocks(rest, flavor=chosen).html(safe=false)
    steps.push({
      "at": Json::number(source.length().to_double()),
      "blocks": Json::number(rest.length().to_double()),
      "html": Json::string(settled),
    })
  }
  Json::array(steps).stringify()
}
