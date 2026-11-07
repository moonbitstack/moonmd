// The entry point: normalise the input, cut it into lines, run the block phase
// and build the document.

///|
/// Parse a Markdown document.
///
/// ```mbt check
/// test {
///   let document = @moonmd.parse("# Title")
///   assert_eq(document.html(safe=false), "<h1>Title</h1>\n")
/// }
/// ```
pub fn parse(text : StringView, flavor~ : Flavor = flavor) -> Document {
  let normalized = normalize_input(text)
  let parser = BlockParser::new(flavor, (Map([]) : Map[String, Reference]))
  for line in split_lines(normalized) {
    parser.process_line(line)
  }
  parser.close_all()
  let blocks = build_blocks(parser.tree, parser.refs, flavor, parser.root, -1)
  Document::of_blocks(blocks, flavor~)
}

///|
/// Undo the line endings the platform may have left in, drop a byte order mark,
/// and replace the NUL characters that would otherwise cut a string short.
fn normalize_input(text : StringView) -> String {
  let buf = StringBuilder()
  let mut started = false
  let mut skip_newline = false
  for c in text {
    if skip_newline {
      skip_newline = false
      if c == '\n' {
        continue
      }
    }
    if !started {
      started = true
      if c == '\u{FEFF}' {
        continue
      }
    }
    if c == '\r' {
      buf.write_char('\n')
      skip_newline = true
    } else if c == '\u{0}' {
      buf.write_char('\u{FFFD}')
    } else {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// Cut the text into lines, each ending with a newline: the block phase relies
/// on every line it sees being terminated, which is what the last line of a
/// document without a trailing newline needs too.
fn split_lines(text : String) -> Array[String] {
  let out : Array[String] = []
  let n = text.length()
  let mut start = 0
  let mut i = 0
  while i < n {
    if cu(text[:], i) == 0x0A {
      out.push(text.clamped_view(start~, end=i + 1).to_owned())
      start = i + 1
    }
    i = i + 1
  }
  if start < n {
    out.push(text.clamped_view(start~, end=n).to_owned() + "\n")
  }
  out
}
