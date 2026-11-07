// Writing the tree back as Markdown. The output favours being read back
// identically over being short: every construct is written in the form the
// specification parses unambiguously, and text is escaped wherever it could
// otherwise start something.

///|
/// Render the document as Markdown.
pub fn Document::markdown(self : Document) -> String {
  let out = StringBuilder()
  let context : MarkdownContext = { at_line_start: true, digits_only: false, }
  write_blocks(out, self.blocks, context, true)
  let text = out.to_string()
  // One trailing newline, not two: a document is a sequence of blocks.
  let trimmed = text.trim_end(chars="\n"[:])
  trimmed.to_owned() + "\n"
}

///|
/// What the writer has to remember between the pieces it writes.
priv struct MarkdownContext {
  mut at_line_start : Bool
  /// Whether the line so far holds nothing but digits, which decides whether a
  /// following `.` or `)` would open an ordered list.
  mut digits_only : Bool
}

///|
fn MarkdownContext::new() -> MarkdownContext {
  { at_line_start: true, digits_only: false, }
}

///|
fn write_blocks(
  out : StringBuilder,
  blocks : Array[Block],
  context : MarkdownContext,
  separate : Bool,
) -> Unit {
  for i = 0; i < blocks.length(); i = i + 1 {
    write_block(out, blocks[i], context)
    // Blocks are separated by a blank line, which also keeps a list from
    // swallowing the paragraph after it. A tight list item keeps them together.
    if separate && i + 1 < blocks.length() {
      out.write_char('\n')
      context.at_line_start = true
    }
  }
}

///|
fn write_block(
  out : StringBuilder,
  block : Block,
  context : MarkdownContext,
) -> Unit {
  match block {
    Heading(heading) => {
      // A heading that spans lines can only be written as a setext heading, and
      // only levels one and two have that form.
      if heading.level <= 2 && has_soft_break(heading.content) {
        context.at_line_start = true
        write_inlines(out, heading.content, context, false)
        out.write_char('\n')
        let underline = if heading.level == 1 { "===" } else { "---" }
        out.write_string(underline)
        out.write_char('\n')
        context.at_line_start = true
        return
      }
      for _ in 0..<heading.level {
        out.write_char('#')
      }
      out.write_char(' ')
      context.at_line_start = false
      write_inlines(out, heading.content, context, false)
      out.write_char('\n')
      context.at_line_start = true
    }
    Paragraph(content) => {
      context.at_line_start = true
      write_inlines(out, content, context, false)
      out.write_char('\n')
      context.at_line_start = true
    }
    Code(code) => {
      let fence = block_fence(code.text, code.info)
      out.write_string(fence)
      out.write_string(code.info)
      out.write_char('\n')
      out.write_string(code.text)
      if code.text.length() > 0 &&
        cu(code.text[:], code.text.length() - 1) != 0x0A {
        out.write_char('\n')
      }
      out.write_string(fence)
      out.write_char('\n')
      context.at_line_start = true
    }
    Quote(children) => {
      let inner = StringBuilder()
      write_blocks(inner, children, MarkdownContext::new(), true)
      let text = inner.to_string().trim_end(chars="\n"[:])
      let lines = split_written_lines(text.to_owned())
      if lines.length() == 0 {
        out.write_string(">\n")
        context.at_line_start = true
        return
      }
      for line in lines {
        if line.is_empty() {
          out.write_char('>')
        } else {
          out.write_string("> ")
          out.write_string(line)
        }
        out.write_char('\n')
      }
      context.at_line_start = true
    }
    List(list) => write_list(out, list, context)
    Table(table) => write_table(out, table, context)
    Html(html) => {
      out.write_string(html)
      if html.length() == 0 || cu(html[:], html.length() - 1) != 0x0A {
        out.write_char('\n')
      }
      context.at_line_start = true
    }
    Break => {
      out.write_string("***\n")
      context.at_line_start = true
    }
    Footnote(footnote) => write_footnote(out, footnote, context)
  }
}

///|
/// A footnote definition: its label, then its body indented under it. The
/// indentation is what keeps the body's blocks nested inside the definition
/// when the document is read again.
fn write_footnote(
  out : StringBuilder,
  footnote : Footnote,
  context : MarkdownContext,
) -> Unit {
  out.write_string("[^")
  out.write_string(footnote.label)
  out.write_string("]:\n")
  let inner = StringBuilder()
  write_blocks(inner, footnote.blocks, MarkdownContext::new(), true)
  let body = inner.to_string().trim_end(chars="\n"[:])
  for line in split_written_lines(body.to_owned()) {
    out.write_string("    ")
    out.write_string(line)
    out.write_char('\n')
  }
  context.at_line_start = true
}

///|
/// A fence longer than any run of backticks in the code, so the code cannot end
/// the block early.
fn code_fence(text : String, minimum : Int32) -> String {
  let mut longest = 0
  let mut run = 0
  for c in text {
    if c == '`' {
      run = run + 1
      if run > longest {
        longest = run
      }
    } else {
      run = 0
    }
  }
  let width = if longest < minimum { minimum } else { longest + 1 }
  let out = StringBuilder()
  for _ in 0..<width {
    out.write_char('`')
  }
  out.to_string()
}

///|
/// A fence for a block of code. A backtick fence may not carry a backtick in its
/// info string, so an info string holding one asks for tildes.
fn block_fence(text : String, info : String) -> String {
  let fence_char = if info.contains_char('`') { '~' } else { '`' }
  let mut longest = 0
  let mut run = 0
  for c in text {
    if c == fence_char {
      run = run + 1
      if run > longest {
        longest = run
      }
    } else {
      run = 0
    }
  }
  let width = if longest < 3 { 3 } else { longest + 1 }
  let out = StringBuilder()
  for _ in 0..<width {
    out.write_char(fence_char)
  }
  out.to_string()
}

///|
fn split_written_lines(text : String) -> Array[String] {
  let lines : Array[String] = []
  let n = text.length()
  let mut start = 0
  let mut i = 0
  while i < n {
    if cu(text[:], i) == 0x0A {
      lines.push(text.clamped_view(start~, end=i).to_owned())
      start = i + 1
    }
    i = i + 1
  }
  if start < n {
    lines.push(text.clamped_view(start~, end=n).to_owned())
  }
  lines
}

///|
/// Write a list: the marker, then the item's blocks indented to the width of
/// the marker.
fn write_list(
  out : StringBuilder,
  list : ListBlock,
  context : MarkdownContext,
) -> Unit {
  let mut number = match list.kind {
    Ordered(start, _) => start
    Bullet(_) => 1
  }
  for index = 0; index < list.items.length(); index = index + 1 {
    let item = list.items[index]
    let marker = match list.kind {
      Bullet(marker) => marker.to_string() + " "
      Ordered(_, delimiter) => number.to_string() + delimiter.to_string() + " "
    }
    number = number + 1
    let inner = StringBuilder()
    let inner_context = MarkdownContext::new()
    match item.task {
      Checked => inner.write_string("[x] ")
      Unchecked => inner.write_string("[ ] ")
      Plain => ()
    }
    inner_context.at_line_start = false
    write_blocks(inner, item.blocks, inner_context, !list.tight)
    let text = inner.to_string().trim_end(chars="\n"[:])
    let lines = if text.is_empty() {
      [""]
    } else {
      split_written_lines(text.to_owned())
    }
    let indent = StringBuilder()
    for _ in 0..<marker.length() {
      indent.write_char(' ')
    }
    let indent_string = indent.to_string()
    for i = 0; i < lines.length(); i = i + 1 {
      if i == 0 {
        out.write_string(marker)
      } else {
        out.write_string(indent_string)
      }
      out.write_string(lines[i])
      out.write_char('\n')
    }
    if list.tight && index + 1 < list.items.length() {
      continue
    }
    if index + 1 < list.items.length() {
      out.write_char('\n')
    }
  }
  context.at_line_start = true
}

///|
fn write_table(
  out : StringBuilder,
  table : Table,
  context : MarkdownContext,
) -> Unit {
  let columns = table.align.length()
  write_table_row(out, table.head, context)
  let delimiter = StringBuilder()
  delimiter.write_char('|')
  for i = 0; i < columns; i = i + 1 {
    delimiter.write_char(' ')
    match table.align[i] {
      Left => delimiter.write_string(":---")
      Center => delimiter.write_string(":---:")
      Right => delimiter.write_string("---:")
      Default => delimiter.write_string("---")
    }
    delimiter.write_string(" |")
  }
  out.write_string(delimiter.to_string())
  out.write_char('\n')
  for row in table.body {
    write_table_row(out, row, context)
  }
  context.at_line_start = true
}

///|
fn write_table_row(
  out : StringBuilder,
  cells : Array[Array[Inline]],
  context : MarkdownContext,
) -> Unit {
  out.write_char('|')
  for cell in cells {
    out.write_char(' ')
    let cell_text = StringBuilder()
    let cell_context = MarkdownContext::new()
    write_inlines(cell_text, cell, cell_context, true)
    out.write_string(cell_text.to_string())
    out.write_string(" |")
  }
  out.write_char('\n')
  context.at_line_start = true
}

///|
/// Characters that would start something else wherever they appear.
fn needs_escape(c : Char) -> Bool {
  match c {
    '\\'
    | '`'
    | '*'
    | '_'
    | '['
    | ']'
    | '<'
    | '>'
    | '&'
    | '#'
    | '~'
    | '|'
    | '!' => true
    _ => false
  }
}

///|
/// Characters that only matter at the start of a line, where they could open a
/// block.
fn needs_escape_at_line_start(c : Char) -> Bool {
  match c {
    '-' | '+' | '=' | '>' | '#' | '*' | '_' => true
    _ => false
  }
}

///|
fn has_soft_break(inlines : Array[Inline]) -> Bool {
  for inline in inlines {
    match inline {
      Break(Soft) => return true
      Emphasis(children) | Strong(children) | Strike(children) =>
        if has_soft_break(children) {
          return true
        }
      Link(link) | Image(link) =>
        if has_soft_break(link.content) {
          return true
        }
      _ => ()
    }
  }
  false
}

///|
fn write_inlines(
  out : StringBuilder,
  inlines : Array[Inline],
  context : MarkdownContext,
  in_table : Bool,
) -> Unit {
  for inline in inlines {
    write_inline(out, inline, context, in_table, '*', 0)
  }
}

///|
fn write_inline_children(
  out : StringBuilder,
  inlines : Array[Inline],
  context : MarkdownContext,
  in_table : Bool,
  enclosing : Char,
  level : Int32,
) -> Unit {
  for inline in inlines {
    write_inline(out, inline, context, in_table, enclosing, level)
  }
}

///|
fn write_inline(
  out : StringBuilder,
  inline : Inline,
  context : MarkdownContext,
  in_table : Bool,
  enclosing : Char,
  level : Int32,
) -> Unit {
  match inline {
    Text(text) => write_text(out, text, context, in_table)
    Code(code) => {
      let text = if in_table {
        code.replace_all(old="|"[:], new="\\|"[:])
      } else {
        code
      }
      let fence = code_fence(text, 1)
      let first = cu(text[:], 0)
      let last = cu(text[:], text.length() - 1)
      let padding = if text.length() == 0 {
        ""
      } else if first == 0x60 || last == 0x60 {
        " "
      } else if first == 0x20 && last == 0x20 && !is_blank(text[:]) {
        " "
      } else {
        ""
      }
      out.write_string(fence)
      out.write_string(padding)
      out.write_string(text)
      out.write_string(padding)
      out.write_string(fence)
      context.at_line_start = false
    }
    Html(html) => {
      out.write_string(html)
      context.at_line_start = false
    }
    Emphasis(children) => {
      // Emphasis nested in emphasis of the same width needs the other
      // delimiter, or the two runs would read back as one of double width.
      let delim = if level == 1 && enclosing == '*' { '_' } else { '*' }
      out.write_char(delim)
      context.at_line_start = false
      write_inline_children(out, children, context, in_table, delim, 1)
      out.write_char(delim)
      context.at_line_start = false
    }
    Strong(children) => {
      // Two strong runs written next to each other read back as one run of
      // four, which is strong in strong: no other delimiter is needed.
      let delim = '*'
      out.write_char(delim)
      out.write_char(delim)
      context.at_line_start = false
      write_inline_children(out, children, context, in_table, delim, 2)
      out.write_char(delim)
      out.write_char(delim)
      context.at_line_start = false
    }
    Strike(children) => {
      out.write_string("~~")
      context.at_line_start = false
      write_inline_children(out, children, context, in_table, enclosing, level)
      out.write_string("~~")
      context.at_line_start = false
    }
    Break(Soft) => {
      out.write_char('\n')
      context.at_line_start = true
    }
    Break(Hard) => {
      out.write_string("\\\n")
      context.at_line_start = true
    }
    Link(link) => {
      out.write_char('[')
      context.at_line_start = false
      write_inline_children(
        out,
        link.content,
        context,
        in_table,
        enclosing,
        level,
      )
      out.write_string("](")
      out.write_string(write_destination(link.dest))
      if !link.title.is_empty() {
        out.write_string(" \"")
        out.write_string(link.title.replace_all(old="\""[:], new="\\\""[:]))
        out.write_char('"')
      }
      out.write_char(')')
      context.at_line_start = false
    }
    Image(image) => {
      out.write_string("![")
      context.at_line_start = false
      write_inline_children(
        out,
        image.content,
        context,
        in_table,
        enclosing,
        level,
      )
      out.write_string("](")
      out.write_string(write_destination(image.dest))
      if !image.title.is_empty() {
        out.write_string(" \"")
        out.write_string(image.title.replace_all(old="\""[:], new="\\\""[:]))
        out.write_char('"')
      }
      out.write_char(')')
      context.at_line_start = false
    }
    FootnoteRef(fnref) => {
      out.write_string("[^")
      out.write_string(fnref.label)
      out.write_char(']')
      context.at_line_start = false
    }
  }
}

///|
/// A link destination, in angle brackets when it holds a space or would confuse
/// the parser as written.
fn write_destination(destination : String) -> String {
  let needs_angles = destination.is_empty() ||
    destination.contains_any(chars=" <>"[:]) ||
    has_unbalanced_parens(destination)
  let buf = StringBuilder()
  if needs_angles {
    buf.write_char('<')
  }
  let text = destination[:]
  let n = text.length()
  let mut i = 0
  while i < n {
    let c = char_at(text, i)
    if c == '\\' || (needs_angles && (c == '<' || c == '>')) {
      buf.write_char('\\')
    }
    buf.write_char(c)
    i = i + c.utf16_len()
  }
  if needs_angles {
    buf.write_char('>')
  }
  buf.to_string()
}

///|
fn has_unbalanced_parens(destination : String) -> Bool {
  let mut depth = 0
  for c in destination {
    if c == '(' {
      depth = depth + 1
    } else if c == ')' {
      depth = depth - 1
      if depth < 0 {
        return true
      }
    }
  }
  depth != 0
}

///|
/// Write text, escaping whatever could be read as markup. Escaping is always
/// safe: a backslash in front of ASCII punctuation renders the punctuation.
fn write_text(
  out : StringBuilder,
  text : String,
  context : MarkdownContext,
  in_table : Bool,
) -> Unit {
  let _ = in_table
  let n = text.length()
  let mut i = 0
  while i < n {
    let c = char_at(text, i)
    let at_start = context.at_line_start
    let escape_for_line = at_start && needs_escape_at_line_start(c)
    let escape_for_digits = context.digits_only && (c == '.' || c == ')')
    if c == '\n' {
      out.write_string("&#10;")
      context.at_line_start = true
      context.digits_only = false
      i = i + 1
      continue
    }
    if c == '\t' && at_start {
      out.write_string("&#9;")
      context.at_line_start = false
      context.digits_only = false
      i = i + 1
      continue
    }
    if needs_escape(c) || escape_for_line || escape_for_digits {
      out.write_char('\\')
      out.write_char(c)
    } else {
      out.write_char(c)
    }
    if c >= '0' && c <= '9' {
      if at_start {
        context.at_line_start = false
        context.digits_only = true
      }
    } else if c != ' ' && c != '\t' {
      context.at_line_start = false
      context.digits_only = false
    }
    i = i + c.utf16_len()
  }
}
