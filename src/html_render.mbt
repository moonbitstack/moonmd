// Writing the tree back as HTML. The output is the one the CommonMark
// specification's examples were produced with, so that a document rendered here
// and a document run through the reference implementation agree byte for byte.

///|
/// The tags the filter keeps out of a page, because a browser would treat them
/// as a new context.
let filtered_tags : Array[String] = [
  "title", "textarea", "style", "xmp", "iframe", "noembed", "noframes", "script",
  "plaintext",
]

///|
/// Render the document as HTML. With `safe` set, which is the default, raw HTML
/// is escaped and links to dangerous destinations lose their anchor; pass
/// `safe=false` to write a document that may embed HTML of its own.
pub fn Document::html(self : Document, safe~ : Bool = true) -> String {
  let out = HtmlOut::new()
  let permit_html = !safe
  let blocks = self.blocks
  // The footnotes, if there are any, were gathered to the end of the document
  // and are the last blocks; they are written inside the notes section.
  let footnotes_start = find_footnotes_start(blocks)
  render_blocks(
    out,
    blocks.clamped_view(start=0, end=footnotes_start),
    self.flavor,
    permit_html,
    false,
  )
  if footnotes_start < blocks.length() {
    out.put_string("<section class=\"footnotes\" data-footnotes>\n<ol>\n")
    render_blocks(
      out,
      blocks.clamped_view(start=footnotes_start, end=blocks.length()),
      self.flavor,
      permit_html,
      false,
    )
    out.put_string("</ol>\n</section>\n")
  }
  out.buf.to_string()
}

///|
/// The first of the trailing footnote blocks, or the end of the array when
/// there are none.
fn find_footnotes_start(blocks : Array[Block]) -> Int32 {
  let mut i = blocks.length() - 1
  while i >= 0 {
    match blocks[i] {
      Footnote(_) => i = i - 1
      _ => break
    }
  }
  i + 1
}

///|
/// A buffer that knows whether it is at the start of a line, which is what the
/// blank line rules of the output are written in terms of.
priv struct HtmlOut {
  buf : StringBuilder
  mut at_line_start : Bool
}

///|
fn HtmlOut::new() -> HtmlOut {
  { buf: StringBuilder(), at_line_start: true, }
}

///|
fn HtmlOut::put(self : HtmlOut, text : StringView) -> Unit {
  self.buf.write_view(text)
  if text.length() > 0 {
    self.at_line_start = cu(text, text.length() - 1) == 0x0A
  }
}

///|
fn HtmlOut::put_string(self : HtmlOut, text : String) -> Unit {
  self.put(text[:])
}

///|
fn HtmlOut::put_char(self : HtmlOut, c : Char) -> Unit {
  self.buf.write_char(c)
  self.at_line_start = c == '\n'
}

///|
/// Start a new line unless the output is already at one.
fn HtmlOut::cr(self : HtmlOut) -> Unit {
  if !self.at_line_start {
    self.buf.write_char('\n')
    self.at_line_start = true
  }
}

///|
fn HtmlOut::escaped(self : HtmlOut, text : StringView) -> Unit {
  write_html_escaped(self.buf, text)
  if text.length() > 0 {
    self.at_line_start = cu(text, text.length() - 1) == 0x0A
  }
}

///|
/// Whether the raw HTML at `start` opens one of the filtered tags.
fn is_filtered_tag(text : StringView, start : Int32) -> Bool {
  for tag in filtered_tags {
    let tag_view : StringView = tag[:]
    let mut i = start + 1
    if cu(text, i) == 0x2F {
      i = i + 1
    }
    let name_start = i
    let length = tag_view.length()
    if i + length > text.length() {
      continue
    }
    if text
      .clamped_view(start=name_start, end=name_start + length)
      .equal_ignore_ascii_case(tag_view) {
      let after = cu(text, name_start + length)
      if after == 0x20 ||
        after == 0x09 ||
        after == 0x0A ||
        after == 0x0C ||
        after == 0x0D ||
        after == 0x3E {
        return true
      }
      if after == 0x2F && cu(text, name_start + length + 1) == 0x3E {
        return true
      }
    }
  }
  false
}

///|
/// Write raw HTML, escaping the `<` of the tags the filter keeps out.
fn filtered_html(out : HtmlOut, text : StringView, flavor : Flavor) -> Unit {
  if !flavor.tag_filter {
    out.put(text)
    return
  }
  let pieces = StringBuilder()
  let n = text.length()
  let mut i = 0
  while i < n {
    let c = char_at(text, i)
    if c == '<' && is_filtered_tag(text, i) {
      out.put(pieces.to_string()[:])
      pieces.reset()
      out.put_string("&lt;")
    } else {
      pieces.write_char(c)
    }
    i = i + c.utf16_len()
  }
  out.put(pieces.to_string()[:])
}

///|
fn render_blocks(
  out : HtmlOut,
  blocks : ArrayView[Block],
  flavor : Flavor,
  permit_html : Bool,
  tight : Bool,
) -> Unit {
  for block in blocks {
    render_block(out, block, flavor, permit_html, tight)
  }
}

///|
fn render_block(
  out : HtmlOut,
  block : Block,
  flavor : Flavor,
  permit_html : Bool,
  tight : Bool,
) -> Unit {
  match block {
    Heading(heading) => {
      out.cr()
      out.put_string("<h")
      out.put_char(Int32::unsafe_to_char(0x30 + heading.level))
      out.put_char('>')
      render_inlines(out, heading.content, flavor, permit_html, false, false)
      out.put_string("</h")
      out.put_char(Int32::unsafe_to_char(0x30 + heading.level))
      out.put_string(">\n")
    }
    Paragraph(content) => {
      if !tight {
        out.cr()
        out.put_string("<p>")
      }
      render_inlines(out, content, flavor, permit_html, false, false)
      if !tight {
        out.put_string("</p>\n")
      }
    }
    Code(code) => {
      out.cr()
      if code.info.is_empty() {
        out.put_string("<pre><code>")
      } else {
        let info = code.info[:]
        let mut first_word = 0
        while first_word < info.length() &&
              !(cu(info, first_word) == 0x20 ||
              cu(info, first_word) == 0x09 ||
              cu(info, first_word) == 0x0A ||
              cu(info, first_word) == 0x0B ||
              cu(info, first_word) == 0x0C ||
              cu(info, first_word) == 0x0D) {
          first_word = first_word + 1
        }
        out.put_string("<pre><code class=\"language-")
        out.escaped(info.clamped_view(start=0, end=first_word))
        out.put_string("\">")
      }
      out.escaped(code.text[:])
      out.put_string("</code></pre>\n")
    }
    Quote(children) => {
      out.cr()
      out.put_string("<blockquote>\n")
      render_blocks(out, children, flavor, permit_html, false)
      out.cr()
      out.put_string("</blockquote>\n")
    }
    List(list) => render_list(out, list, flavor, permit_html)
    Table(table) => render_table(out, table, flavor, permit_html)
    Html(text) => {
      out.cr()
      if permit_html {
        filtered_html(out, text[:], flavor)
      } else {
        out.escaped(text[:])
      }
      out.cr()
    }
    Break => {
      out.cr()
      out.put_string("<hr />\n")
    }
    Footnote(footnote) => render_footnote(out, footnote, flavor, permit_html)
  }
}

///|
/// One footnote: a list item whose last line carries the link back to the
/// reference it is reached from, and one more for every further reference to
/// the same footnote.
fn render_footnote(
  out : HtmlOut,
  footnote : Footnote,
  flavor : Flavor,
  permit_html : Bool,
) -> Unit {
  out.put_string("<li id=\"fn-")
  write_href_escaped(out.buf, footnote.label[:])
  out.put_string("\">\n")
  let blocks = footnote.blocks
  let mut backref_written = false
  let mut i = 0
  for block in blocks {
    let is_last = i == blocks.length() - 1
    if is_last {
      match block {
        // The backref goes inside the last paragraph, the way a paragraph at
        // the end of a footnote reads.
        Paragraph(content) => {
          out.cr()
          out.put_string("<p>")
          render_inlines(out, content, flavor, permit_html, false, false)
          out.put_char(' ')
          write_footnote_backref(out, footnote)
          out.put_string("</p>\n")
          backref_written = true
        }
        _ => render_block(out, block, flavor, permit_html, false)
      }
    } else {
      render_block(out, block, flavor, permit_html, false)
    }
    i = i + 1
  }
  if !backref_written {
    // The body does not end in a paragraph, so the backref stands alone.
    write_footnote_backref(out, footnote)
    out.put_char('\n')
  }
  out.put_string("</li>\n")
}

///|
/// The links back to the references a footnote is reached from.
fn write_footnote_backref(out : HtmlOut, footnote : Footnote) -> Unit {
  out.put_string("<a href=\"#fnref-")
  write_href_escaped(out.buf, footnote.label[:])
  out.put_string(
    "\" class=\"footnote-backref\" data-footnote-backref data-footnote-backref-idx=\"",
  )
  out.put_string(footnote.number.to_string())
  out.put_string("\" aria-label=\"Back to reference ")
  out.put_string(footnote.number.to_string())
  out.put_string("\">↩</a>")
  for i = 2; i <= footnote.backrefs; i = i + 1 {
    out.put_string(" <a href=\"#fnref-")
    write_href_escaped(out.buf, footnote.label[:])
    out.put_string("-")
    out.put_string(i.to_string())
    out.put_string(
      "\" class=\"footnote-backref\" data-footnote-backref data-footnote-backref-idx=\"",
    )
    out.put_string(footnote.number.to_string())
    out.put_string("-")
    out.put_string(i.to_string())
    out.put_string("\" aria-label=\"Back to reference ")
    out.put_string(footnote.number.to_string())
    out.put_string("-")
    out.put_string(i.to_string())
    out.put_string("\">↩<sup class=\"footnote-ref\">")
    out.put_string(i.to_string())
    out.put_string("</sup></a>")
  }
}

///|
fn render_list(
  out : HtmlOut,
  list : ListBlock,
  flavor : Flavor,
  permit_html : Bool,
) -> Unit {
  match list.kind {
    Bullet(_) => {
      out.cr()
      out.put_string("<ul>\n")
    }
    Ordered(start, _) => {
      out.cr()
      if start == 1 {
        out.put_string("<ol>\n")
      } else {
        out.put_string("<ol start=\"")
        out.put_string(start.to_string())
        out.put_string("\">\n")
      }
    }
  }
  for item in list.items {
    out.cr()
    out.put_string("<li>")
    match item.task {
      Checked =>
        out.put_string(
          "<input type=\"checkbox\" checked=\"\" disabled=\"\" /> ",
        )
      Unchecked => out.put_string("<input type=\"checkbox\" disabled=\"\" /> ")
      Plain => ()
    }
    render_blocks(out, item.blocks, flavor, permit_html, list.tight)
    out.put_string("</li>\n")
  }
  match list.kind {
    Bullet(_) => out.put_string("</ul>\n")
    Ordered(_, _) => out.put_string("</ol>\n")
  }
}

///|
fn render_table(
  out : HtmlOut,
  table : Table,
  flavor : Flavor,
  permit_html : Bool,
) -> Unit {
  out.cr()
  out.put_string("<table>")
  out.cr()
  out.put_string("<thead>")
  out.cr()
  out.put_string("<tr>")
  let mut column = 0
  for cell in table.head {
    out.cr()
    out.put_string("<th")
    render_align(out, table.align, column)
    out.put_string(">")
    render_inlines(out, cell, flavor, permit_html, false, false)
    out.put_string("</th>")
    column = column + 1
  }
  out.cr()
  out.put_string("</tr>")
  out.cr()
  out.put_string("</thead>")
  if table.body.length() > 0 {
    out.cr()
    out.put_string("<tbody>")
    for row in table.body {
      out.cr()
      out.put_string("<tr>")
      let mut i = 0
      for cell in row {
        out.cr()
        out.put_string("<td")
        render_align(out, table.align, i)
        out.put_string(">")
        render_inlines(out, cell, flavor, permit_html, false, false)
        out.put_string("</td>")
        i = i + 1
      }
      out.cr()
      out.put_string("</tr>")
    }
    out.cr()
    out.put_string("</tbody>")
  }
  out.cr()
  out.put_string("</table>")
  out.cr()
}

///|
fn render_align(out : HtmlOut, align : Array[Align], column : Int32) -> Unit {
  if column >= align.length() {
    return
  }
  match align[column] {
    Left => out.put_string(" align=\"left\"")
    Center => out.put_string(" align=\"center\"")
    Right => out.put_string(" align=\"right\"")
    Default => ()
  }
}

///|
fn render_inlines(
  out : HtmlOut,
  inlines : Array[Inline],
  flavor : Flavor,
  permit_html : Bool,
  plain : Bool,
  inside_strong : Bool,
) -> Unit {
  for inline in inlines {
    render_inline(out, inline, flavor, permit_html, plain, inside_strong)
  }
}

///|
fn render_inline(
  out : HtmlOut,
  inline : Inline,
  flavor : Flavor,
  permit_html : Bool,
  plain : Bool,
  inside_strong : Bool,
) -> Unit {
  match inline {
    Text(text) => out.escaped(text[:])
    Code(code) =>
      if plain {
        out.escaped(code[:])
      } else {
        out.put_string("<code>")
        out.escaped(code[:])
        out.put_string("</code>")
      }
    Html(html) =>
      if plain {
        out.escaped(html[:])
      } else if permit_html {
        filtered_html(out, html[:], flavor)
      } else {
        out.escaped(html[:])
      }
    Emphasis(children) =>
      if plain {
        render_inlines(out, children, flavor, permit_html, true, inside_strong)
      } else {
        out.put_string("<em>")
        render_inlines(out, children, flavor, permit_html, false, inside_strong)
        out.put_string("</em>")
      }
    Strong(children) =>
      if plain {
        render_inlines(out, children, flavor, permit_html, true, inside_strong)
      } else {
        out.put_string("<strong>")
        render_inlines(out, children, flavor, permit_html, false, true)
        out.put_string("</strong>")
      }
    Strike(children) =>
      if plain {
        render_inlines(out, children, flavor, permit_html, true, inside_strong)
      } else {
        out.put_string("<del>")
        render_inlines(out, children, flavor, permit_html, false, inside_strong)
        out.put_string("</del>")
      }
    Break(Soft) => if plain { out.put_char(' ') } else { out.put_char('\n') }
    Break(Hard) =>
      if plain {
        out.put_char(' ')
      } else {
        out.put_string("<br />\n")
      }
    Link(link) => {
      let dangerous = is_dangerous_url(link.dest[:])
      if plain {
        render_inlines(
          out,
          link.content,
          flavor,
          permit_html,
          true,
          inside_strong,
        )
      } else if dangerous && !permit_html {
        // A destination that would run script keeps its text and loses its link.
        render_inlines(
          out,
          link.content,
          flavor,
          permit_html,
          false,
          inside_strong,
        )
      } else {
        out.put_string("<a href=\"")
        write_href_escaped(out.buf, link.dest[:])
        if !link.title.is_empty() {
          out.put_string("\" title=\"")
          out.escaped(link.title[:])
        }
        out.put_string("\">")
        render_inlines(
          out,
          link.content,
          flavor,
          permit_html,
          false,
          inside_strong,
        )
        out.put_string("</a>")
      }
    }
    Image(image) => {
      let dangerous = is_dangerous_url(image.dest[:])
      if plain {
        render_inlines(
          out,
          image.content,
          flavor,
          permit_html,
          true,
          inside_strong,
        )
      } else if dangerous && !permit_html {
        // Without a source there is nothing to show but the alternative text.
        render_inlines(
          out,
          image.content,
          flavor,
          permit_html,
          true,
          inside_strong,
        )
      } else {
        out.put_string("<img src=\"")
        write_href_escaped(out.buf, image.dest[:])
        out.put_string("\" alt=\"")
        render_inlines(
          out,
          image.content,
          flavor,
          permit_html,
          true,
          inside_strong,
        )
        if !image.title.is_empty() {
          out.put_string("\" title=\"")
          out.escaped(image.title[:])
        }
        out.put_string("\" />")
      }
    }
    FootnoteRef(fnref) =>
      if plain {
        out.escaped(fnref.label[:])
      } else {
        out.put_string("<sup class=\"footnote-ref\"><a href=\"#fn-")
        write_href_escaped(out.buf, fnref.label[:])
        out.put_string("\" id=\"fnref-")
        write_href_escaped(out.buf, fnref.label[:])
        if fnref.ref_ix > 1 {
          out.put_char('-')
          out.put_string(fnref.ref_ix.to_string())
        }
        out.put_string("\" data-footnote-ref>")
        out.put_string(fnref.number.to_string())
        out.put_string("</a></sup>")
      }
  }
}
