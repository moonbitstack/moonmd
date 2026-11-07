// The scanners. Each one looks at a line (or a paragraph's text) from a given
// offset and answers how many code units the construct it recognises spans, or
// zero when it does not recognise one there. A code unit past the end reads as
// zero, the way a NUL terminator would.

///|
/// The code unit at `i`, or zero when `i` is past the end.
fn cu(text : StringView, i : Int32) -> Int32 {
  if i >= 0 && i < text.length() {
    text.at(i).to_int()
  } else {
    0
  }
}

///|
fn is_ascii_punct(c : Int32) -> Bool {
  (c >= 0x21 && c <= 0x2F) ||
  (c >= 0x3A && c <= 0x40) ||
  (c >= 0x5B && c <= 0x60) ||
  (c >= 0x7B && c <= 0x7E)
}

///|
/// Any ASCII whitespace, the set the reference implementation accepts after a
/// list marker.
fn is_ascii_space(c : Int32) -> Bool {
  c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0B || c == 0x0C || c == 0x0D
}

///|
/// What trimming removes from the end of a line.
fn is_blank_char(c : Int32) -> Bool {
  c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0B || c == 0x0C
}

///|
fn is_space_or_tab(c : Int32) -> Bool {
  c == 0x20 || c == 0x09
}

///|
fn is_line_end(c : Int32) -> Bool {
  c == 0x0A || c == 0x0D
}

///|
fn is_digit(c : Int32) -> Bool {
  c >= 0x30 && c <= 0x39
}

///|
fn is_alpha(c : Int32) -> Bool {
  (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)
}

///|
fn is_alnum(c : Int32) -> Bool {
  is_alpha(c) || is_digit(c)
}

///|
/// `[ \t\v\f\r\n]+`.
fn scan_spacechars(text : StringView, start : Int32) -> Int32 {
  let mut i = start
  while true {
    let c = cu(text, i)
    if c == 0x20 ||
      c == 0x09 ||
      c == 0x0B ||
      c == 0x0C ||
      c == 0x0D ||
      c == 0x0A {
      i = i + 1
    } else {
      break
    }
  }
  i - start
}

///|
/// `[#]{1,6} ([ \t]+|[\r\n])`, returning the whole match including the space
/// after the last `#`.
fn scan_atx_heading_start(text : StringView, start : Int32) -> Int32 {
  let mut i = start
  while cu(text, i) == 0x23 && i - start < 7 {
    i = i + 1
  }
  let hashes = i - start
  if hashes < 1 || hashes > 6 {
    return 0
  }
  let c = cu(text, i)
  if is_space_or_tab(c) {
    while is_space_or_tab(cu(text, i)) {
      i = i + 1
    }
    return i - start
  }
  if is_line_end(c) {
    return i - start
  }
  0
}

///|
/// `[=]+ [ \t]* [\r\n]` for level one, `[-]+ [ \t]* [\r\n]` for level two.
fn scan_setext_heading_line(text : StringView, start : Int32) -> Int32 {
  let c = cu(text, start)
  if c != 0x3D && c != 0x2D {
    return 0
  }
  let mut i = start
  while cu(text, i) == c {
    i = i + 1
  }
  while is_space_or_tab(cu(text, i)) {
    i = i + 1
  }
  if is_line_end(cu(text, i)) {
    if c == 0x3D {
      1
    } else {
      2
    }
  } else {
    0
  }
}

///|
/// An opening code fence: three or more backticks not followed by another
/// backtick on the line, or three or more tildes. Returns the number of fence
/// characters.
fn scan_open_code_fence(text : StringView, start : Int32) -> Int32 {
  let c = cu(text, start)
  if c != 0x60 && c != 0x7E {
    return 0
  }
  let mut i = start
  while cu(text, i) == c {
    i = i + 1
  }
  let fence = i - start
  if fence < 3 {
    return 0
  }
  while true {
    let d = cu(text, i)
    if d == 0 {
      return 0
    } else if is_line_end(d) {
      return fence
    } else if c == 0x60 && d == 0x60 {
      return 0
    }
    i = i + 1
  }
  fence
}

///|
/// A closing code fence: three or more of the fence character followed only by
/// spaces. Returns the number of fence characters.
fn scan_close_code_fence(text : StringView, start : Int32) -> Int32 {
  let c = cu(text, start)
  if c != 0x60 && c != 0x7E {
    return 0
  }
  let mut i = start
  while cu(text, i) == c {
    i = i + 1
  }
  let fence = i - start
  if fence < 3 {
    return 0
  }
  while is_space_or_tab(cu(text, i)) {
    i = i + 1
  }
  if is_line_end(cu(text, i)) {
    fence
  } else {
    0
  }
}

///|
/// Three or more `-`, `*` or `_` on a line of their own, spaces allowed between
/// them. Returns the match length, or zero.
fn scan_thematic_break(text : StringView, start : Int32) -> Int32 {
  let c = cu(text, start)
  if c != 0x2A && c != 0x5F && c != 0x2D {
    return 0
  }
  let mut i = start
  let mut count = 0
  while true {
    let d = cu(text, i)
    if d == c {
      count = count + 1
      i = i + 1
    } else if d == 0x20 || d == 0x09 {
      i = i + 1
    } else {
      break
    }
  }
  if count >= 3 && is_line_end(cu(text, i)) {
    i - start
  } else {
    0
  }
}

///|
/// The opening of a footnote definition, `[^label]:`: a caret, a label that
/// holds nothing but a `]`, a space, a tab or a line ending, a colon, and the
/// run of spaces or tabs the reference tolerates after it. Returns the number of
/// code units the opening spans, or zero.
fn scan_footnote_definition(text : StringView, start : Int32) -> Int32 {
  if cu(text, start) != 0x5B {
    return 0
  }
  if cu(text, start + 1) != 0x5E {
    return 0
  }
  let n = text.length()
  let mut i = start + 2
  let mut saw = false
  while i < n {
    let c = cu(text, i)
    if c == 0x5D {
      if saw && cu(text, i + 1) == 0x3A {
        // The spaces and tabs after the colon belong to the marker, so the
        // body begins at the first character that is not one of them.
        i = i + 2
        while cu(text, i) == 0x20 || cu(text, i) == 0x09 {
          i = i + 1
        }
        return i - start
      }
      return 0
    }
    if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D {
      return 0
    }
    saw = true
    i = i + 1
  }
  0
}

///|
/// The names the CommonMark specification lists as block level HTML tags.
let html_block_tags : Array[String] = [
  "address", "article", "aside", "base", "basefont", "blockquote", "body", "caption",
  "center", "col", "colgroup", "dd", "details", "dialog", "dir", "div", "dl", "dt",
  "fieldset", "figcaption", "figure", "footer", "form", "frame", "frameset", "h1",
  "h2", "h3", "h4", "h5", "h6", "head", "header", "hr", "html", "iframe", "legend",
  "li", "link", "main", "menu", "menuitem", "nav", "noframes", "ol", "optgroup",
  "option", "p", "param", "section", "source", "summary", "table", "tbody", "td",
  "tfoot", "th", "thead", "title", "tr", "track", "ul",
]

///|
/// Whether `text` at `i` begins with `word`, ignoring ASCII case.
fn starts_with_word(
  text : StringView,
  i : Int32,
  word : StringView,
  limit : Int32,
) -> Bool {
  if i + word.length() > limit {
    return false
  }
  for k = 0; k < word.length(); k = k + 1 {
    let c = cu(text, i + k)
    let d = word.at(k).to_int()
    let left = if c >= 0x41 && c <= 0x5A { c + 0x20 } else { c }
    let right = if d >= 0x41 && d <= 0x5A { d + 0x20 } else { d }
    if left != right {
      return false
    }
  }
  true
}

///|
/// Which kind of HTML block a line opens, as numbered by the specification, or
/// zero. Type seven is `scan_html_block_start_7`, because it depends on the
/// paragraph it would interrupt.
fn scan_html_block_start(text : StringView, start : Int32) -> Int32 {
  if cu(text, start) != 0x3C {
    return 0
  }
  let i = start + 1
  let c = cu(text, i)
  if c == 0x21 {
    // `<!--`, `<![CDATA[`, or a declaration.
    if cu(text, i + 1) == 0x2D && cu(text, i + 2) == 0x2D {
      return 2
    }
    if cu(text, i + 1) == 0x5B &&
      starts_with_word(text, i + 2, "CDATA[", text.length()) {
      return 5
    }
    if cu(text, i + 1) >= 0x41 && cu(text, i + 1) <= 0x5A {
      return 4
    }
    return 0
  }
  if c == 0x3F {
    return 3
  }
  let mut j = i
  if cu(text, j) == 0x2F {
    j = j + 1
  }
  for tag in ["script", "pre", "textarea", "style"] {
    if starts_with_word(text, j, tag, text.length()) {
      let d = cu(text, j + tag.length())
      if d == 0x20 ||
        d == 0x09 ||
        d == 0x0B ||
        d == 0x0C ||
        d == 0x0D ||
        d == 0x0A ||
        d == 0x3E {
        // Only an opening tag of these four names starts type one.
        return if j == i { 1 } else { 0 }
      }
    }
  }
  for tag in html_block_tags {
    if starts_with_word(text, j, tag, text.length()) {
      let d = cu(text, j + tag.length())
      if d == 0x20 ||
        d == 0x09 ||
        d == 0x0B ||
        d == 0x0C ||
        d == 0x0D ||
        d == 0x0A {
        return 6
      }
      if d == 0x3E {
        return 6
      }
      if d == 0x2F && cu(text, j + tag.length() + 1) == 0x3E {
        return 6
      }
    }
  }
  0
}

///|
/// Type seven: a complete open or close tag alone on the line.
fn scan_html_block_start_7(text : StringView, start : Int32) -> Bool {
  if cu(text, start) != 0x3C {
    return false
  }
  let matched = scan_html_tag(text, start + 1)
  if matched == 0 {
    return false
  }
  let mut i = start + 1 + matched
  while true {
    let c = cu(text, i)
    if c == 0x09 || c == 0x0C || c == 0x20 {
      i = i + 1
    } else {
      break
    }
  }
  is_line_end(cu(text, i))
}

///|
/// Whether the line at `start` closes an HTML block of `kind`.
fn scan_html_block_end(text : StringView, start : Int32, kind : Int32) -> Bool {
  let n = text.length()
  match kind {
    1 => {
      // A closing `</script>`, `</pre>`, `</textarea>` or `</style>` anywhere.
      let mut found = false
      for tag in ["</script>", "</pre>", "</textarea>", "</style>"] {
        if contains_word(text, start, tag[:], n) {
          found = true
        }
      }
      found
    }
    2 => contains_word(text, start, "-->"[:], n)
    3 => contains_word(text, start, "?>"[:], n)
    4 => contains_word(text, start, ">"[:], n)
    5 => contains_word(text, start, "]]>"[:], n)
    _ => false
  }
}

///|
/// Whether `needle` appears in `text` at or after `start`, compared ignoring
/// ASCII case.
fn contains_word(
  text : StringView,
  start : Int32,
  needle : StringView,
  limit : Int32,
) -> Bool {
  let mut i = start
  while i < limit {
    if starts_with_word(text, i, needle, limit) {
      return true
    }
    i = i + 1
  }
  false
}

///|
/// `[A-Za-z][A-Za-z0-9-]*`, returning its length.
fn scan_tag_name(text : StringView, start : Int32) -> Int32 {
  if !is_alpha(cu(text, start)) {
    return 0
  }
  let mut i = start + 1
  while true {
    let c = cu(text, i)
    if is_alnum(c) || c == 0x2D {
      i = i + 1
    } else {
      break
    }
  }
  i - start
}

///|
/// `[a-zA-Z_:][a-zA-Z0-9:._-]*`, returning its length.
fn scan_attribute_name(text : StringView, start : Int32) -> Int32 {
  let c = cu(text, start)
  if !(is_alpha(c) || c == 0x5F || c == 0x3A) {
    return 0
  }
  let mut i = start + 1
  while true {
    let d = cu(text, i)
    if is_alnum(d) || d == 0x3A || d == 0x2E || d == 0x5F || d == 0x2D {
      i = i + 1
    } else {
      break
    }
  }
  i - start
}

///|
/// One attribute value, quoted or not, returning its length.
fn scan_attribute_value(text : StringView, start : Int32) -> Int32 {
  let c = cu(text, start)
  if c == 0x27 || c == 0x22 {
    let mut i = start + 1
    while true {
      let d = cu(text, i)
      if d == 0 {
        return 0
      }
      if d == c {
        return i + 1 - start
      }
      i = i + 1
    }
  }
  let mut i = start
  while true {
    let d = cu(text, i)
    if d == 0 ||
      d == 0x20 ||
      d == 0x09 ||
      d == 0x0A ||
      d == 0x0B ||
      d == 0x0C ||
      d == 0x0D ||
      d == 0x22 ||
      d == 0x27 ||
      d == 0x3D ||
      d == 0x3C ||
      d == 0x3E ||
      d == 0x60 {
      break
    }
    i = i + 1
  }
  i - start
}

///|
/// An open or close tag, starting at the character after `<`, returning the
/// length of the tag up to and including its `>`.
fn scan_html_tag(text : StringView, start : Int32) -> Int32 {
  let mut i = start
  if cu(text, i) == 0x2F {
    // A close tag.
    i = i + 1
    let name = scan_tag_name(text, i)
    if name == 0 {
      return 0
    }
    i = i + name
    while is_space_or_tab(cu(text, i)) ||
          cu(text, i) == 0x0A ||
          cu(text, i) == 0x0C ||
          cu(text, i) == 0x0D {
      i = i + 1
    }
    if cu(text, i) == 0x3E {
      return i + 1 - start
    }
    return 0
  }
  let name = scan_tag_name(text, i)
  if name == 0 {
    return 0
  }
  i = i + name
  while true {
    let before = i
    while is_space_or_tab(cu(text, i)) ||
          cu(text, i) == 0x0A ||
          cu(text, i) == 0x0C ||
          cu(text, i) == 0x0D {
      i = i + 1
    }
    let c = cu(text, i)
    if c == 0x3E {
      return i + 1 - start
    }
    if c == 0x2F && cu(text, i + 1) == 0x3E {
      return i + 2 - start
    }
    if i == before {
      // An attribute has to be separated from the tag name or the one before.
      return 0
    }
    let attribute = scan_attribute_name(text, i)
    if attribute == 0 {
      return 0
    }
    i = i + attribute
    let after_name = i
    while is_space_or_tab(cu(text, i)) ||
          cu(text, i) == 0x0A ||
          cu(text, i) == 0x0C ||
          cu(text, i) == 0x0D {
      i = i + 1
    }
    if cu(text, i) == 0x3D {
      i = i + 1
      while is_space_or_tab(cu(text, i)) ||
            cu(text, i) == 0x0A ||
            cu(text, i) == 0x0C ||
            cu(text, i) == 0x0D {
        i = i + 1
      }
      let value = scan_attribute_value(text, i)
      if value == 0 {
        return 0
      }
      i = i + value
    } else {
      i = after_name
    }
  }
  abort("unreachable")
}

///|
/// An HTML comment, starting at the character after `<`, including its `-->`.
fn scan_html_comment(text : StringView, start : Int32) -> Int32 {
  // The caller has already seen `<!`; the body begins with `--`.
  let mut i = start
  if cu(text, i) != 0x2D || cu(text, i + 1) != 0x2D {
    return 0
  }
  i = i + 2
  while true {
    let c = cu(text, i)
    if c == 0 {
      return 0
    }
    if c == 0x2D {
      if cu(text, i + 1) == 0x2D && cu(text, i + 2) == 0x3E {
        return i + 3 - start
      }
    }
    i = i + 1
  }
  abort("unreachable")
}

///|
/// A processing instruction, starting at the character after `<`, including
/// its `?>`.
fn scan_html_pi(text : StringView, start : Int32) -> Int32 {
  let mut i = start
  while true {
    let c = cu(text, i)
    if c == 0 {
      if i + 2 <= text.length() && cu(text, i) == 0 && i >= text.length() {
        return 0
      }
      return 0
    }
    if c == 0x3F && cu(text, i + 1) == 0x3E {
      return i + 2 - start
    }
    i = i + 1
  }
  abort("unreachable")
}

///|
/// A markup declaration, starting at the character after `<!`, including the
/// `>`.
fn scan_html_declaration(text : StringView, start : Int32) -> Int32 {
  let mut i = start
  if !(cu(text, i) >= 0x41 && cu(text, i) <= 0x5A) {
    return 0
  }
  while cu(text, i) >= 0x41 && cu(text, i) <= 0x5A {
    i = i + 1
  }
  let spaces = scan_spacechars(text, i)
  if spaces == 0 {
    return 0
  }
  i = i + spaces
  while true {
    let c = cu(text, i)
    if c == 0 {
      return 0
    }
    if c == 0x3E {
      return i + 1 - start
    }
    i = i + 1
  }
  abort("unreachable")
}

///|
/// A CDATA section, starting at the character after `<!`, including its `]]>`.
fn scan_html_cdata(text : StringView, start : Int32) -> Int32 {
  let mut i = start
  if !starts_with_word(text, i, "CDATA[", text.length()) {
    return 0
  }
  i = i + 6
  while true {
    let c = cu(text, i)
    if c == 0 {
      return 0
    }
    if c == 0x5D && cu(text, i + 1) == 0x5D && cu(text, i + 2) == 0x3E {
      return i + 3 - start
    }
    i = i + 1
  }
  abort("unreachable")
}

///|
/// A link title in quotes or parentheses, including them. One level of escaped
/// quote nesting is allowed.
fn scan_link_title(text : StringView, start : Int32) -> Int32 {
  let open = cu(text, start)
  let close = match open {
    0x22 => 0x22
    0x27 => 0x27
    0x28 => 0x29
    _ => return 0
  }
  let mut i = start + 1
  while true {
    let c = cu(text, i)
    if c == 0 {
      return 0
    }
    if c == 0x5C && is_ascii_punct(cu(text, i + 1)) {
      i = i + 2
      continue
    }
    if c == close {
      return i + 1 - start
    }
    if c == open && open == 0x28 {
      return 0
    }
    i = i + 1
  }
  abort("unreachable")
}

///|
/// A URI autolink after the `<`, including its `>`.
fn scan_autolink_uri(text : StringView, start : Int32) -> Int32 {
  let mut i = start
  if !is_alpha(cu(text, i)) {
    return 0
  }
  i = i + 1
  let mut scheme = 1
  while true {
    let c = cu(text, i)
    if is_alnum(c) || c == 0x2E || c == 0x2B || c == 0x2D {
      i = i + 1
      scheme = scheme + 1
    } else {
      break
    }
  }
  if scheme < 2 || scheme > 32 || cu(text, i) != 0x3A {
    return 0
  }
  i = i + 1
  while true {
    let c = cu(text, i)
    if c == 0 {
      return 0
    }
    if c == 0x3E {
      return i + 1 - start
    }
    if c <= 0x20 || c == 0x3C {
      return 0
    }
    i = i + 1
  }
  abort("unreachable")
}

///|
/// An email autolink after the `<`, including its `>`.
fn scan_autolink_email(text : StringView, start : Int32) -> Int32 {
  let mut i = start
  while true {
    let c = cu(text, i)
    if is_alnum(c) ||
      c == 0x2E ||
      c == 0x21 ||
      c == 0x23 ||
      c == 0x24 ||
      c == 0x25 ||
      c == 0x26 ||
      c == 0x27 ||
      c == 0x2A ||
      c == 0x2B ||
      c == 0x2F ||
      c == 0x3D ||
      c == 0x3F ||
      c == 0x5E ||
      c == 0x5F ||
      c == 0x60 ||
      c == 0x7B ||
      c == 0x7C ||
      c == 0x7D ||
      c == 0x7E ||
      c == 0x2D {
      i = i + 1
    } else {
      break
    }
  }
  if cu(text, i) != 0x40 {
    return 0
  }
  i = i + 1
  // One domain label: alphanumeric, up to 63 characters, no trailing hyphen.
  while true {
    if !is_alnum(cu(text, i)) {
      break
    }
    let mut j = i + 1
    while j - i <= 62 && (is_alnum(cu(text, j)) || cu(text, j) == 0x2D) {
      j = j + 1
    }
    if cu(text, j - 1) == 0x2D {
      // Back off the trailing hyphens; the label has to end alphanumeric.
      while j - 1 > i && cu(text, j - 1) == 0x2D {
        j = j - 1
      }
    }
    i = j
    if cu(text, i) == 0x2E {
      i = i + 1
      if is_alnum(cu(text, i)) {
        continue
      }
    }
    break
  }
  if cu(text, i) == 0x3E {
    return i + 1 - start
  }
  0
}

///|
/// A table's delimiter row: optional leading pipe, then one cell per column of
/// the form `:?-+:?`, separated by pipes, with an optional trailing pipe.
fn scan_table_start(text : StringView, start : Int32) -> Int32 {
  let n = text.length()
  let mut i = start
  if cu(text, i) == 0x7C {
    i = i + 1
  }
  while true {
    // One marker.
    let column_start = i
    while is_space_or_tab(cu(text, i)) {
      i = i + 1
    }
    if cu(text, i) == 0x3A {
      i = i + 1
    }
    let mut hyphens = 0
    while cu(text, i) == 0x2D {
      hyphens = hyphens + 1
      i = i + 1
    }
    if hyphens == 0 {
      return 0
    }
    if cu(text, i) == 0x3A {
      i = i + 1
    }
    while is_space_or_tab(cu(text, i)) {
      i = i + 1
    }
    if i == column_start {
      return 0
    }
    if cu(text, i) == 0x7C {
      i = i + 1
      // A trailing pipe may end the row, otherwise another column follows.
      let mut j = i
      while is_space_or_tab(cu(text, j)) {
        j = j + 1
      }
      if is_line_end(cu(text, j)) {
        return j - start
      }
      continue
    }
    break
  }
  if is_line_end(cu(text, i)) {
    i - start
  } else if i == n {
    0
  } else {
    0
  }
}

///|
/// One table cell: everything up to the next unescaped pipe or the end of the
/// line, escapes honoured.
fn scan_table_cell(text : StringView, start : Int32) -> Int32 {
  let mut i = start
  while true {
    let c = cu(text, i)
    if c == 0 || c == 0x0A || c == 0x0D || c == 0x7C {
      return i - start
    }
    if c == 0x5C && is_ascii_punct(cu(text, i + 1)) {
      i = i + 2
      continue
    }
    i = i + 1
  }
  abort("unreachable")
}

///|
/// A pipe and the spaces after it.
fn scan_table_cell_end(text : StringView, start : Int32) -> Int32 {
  if cu(text, start) != 0x7C {
    return 0
  }
  let mut i = start + 1
  while is_space_or_tab(cu(text, i)) ||
        cu(text, i) == 0x0B ||
        cu(text, i) == 0x0C {
    i = i + 1
  }
  i - start
}

///|
/// The spaces and newline that end a table row.
fn scan_table_row_end(text : StringView, start : Int32) -> Int32 {
  let mut i = start
  while is_space_or_tab(cu(text, i)) ||
        cu(text, i) == 0x0B ||
        cu(text, i) == 0x0C {
    i = i + 1
  }
  if is_line_end(cu(text, i)) {
    i + 1 - start
  } else {
    0
  }
}
