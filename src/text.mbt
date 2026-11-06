// Text handling that is not specific to blocks or inlines: entity references,
// the backslash unescaping of link destinations, the normalisation of labels,
// and the two escapers the HTML renderer writes through.

///|
/// Whether the text holds nothing but spaces, tabs and newlines.
fn is_blank(text : StringView) -> Bool {
  for c in text {
    if c != ' ' && c != '\t' && c != '\n' && c != '\r' {
      return false
    }
  }
  true
}

///|
/// Drop the spaces, tabs and line endings at both ends.
fn trim_view(text : StringView) -> StringView {
  text.trim(chars=" \t\r\n\u{0B}\u{0C}"[:])
}

///|
/// The Unicode character at `i`, taking a surrogate pair as one.
fn char_at(text : StringView, i : Int32) -> Char {
  match text.get_char(i) {
    Some(c) => c
    None => '\u{0}'
  }
}

///|
/// The Unicode character just before `i`, taking a surrogate pair as one.
fn char_before(text : StringView, i : Int32) -> Char {
  if i <= 0 {
    return '\n'
  }
  let last = char_at(text, i - 1)
  if i >= 2 && last.to_int() >= 0xDC00 && last.to_int() <= 0xDFFF {
    let high = char_at(text, i - 2)
    if high.to_int() >= 0xD800 && high.to_int() <= 0xDBFF {
      return combine_surrogates(char_at(text, i - 2), last)
    }
  }
  last
}

///|
fn combine_surrogates(high : Char, low : Char) -> Char {
  let cp = 0x10000 + ((high.to_int() - 0xD800) << 10) + (low.to_int() - 0xDC00)
  Int32::unsafe_to_char(cp)
}

///|
/// The Unicode White_Space property.
fn is_unicode_space(c : Char) -> Bool {
  let cp = c.to_int()
  let mut low = 0
  let mut high = whitespace_code_points.length() - 1
  while low <= high {
    let mid = (low + high) / 2
    let value = whitespace_code_points[mid]
    if value == cp {
      return true
    } else if value < cp {
      low = mid + 1
    } else {
      high = mid - 1
    }
  }
  false
}

///|
/// The P general category alone, which is what a host name stops at: a symbol
/// may be part of one, an emoji included.
fn is_unicode_punctuation_only(c : Char) -> Bool {
  let cp = c.to_int()
  let mut low = 0
  let mut high = punctuation_only_ranges.length() / 2 - 1
  while low <= high {
    let mid = (low + high) / 2
    let start = punctuation_only_ranges[mid * 2]
    let end = punctuation_only_ranges[mid * 2 + 1]
    if cp < start {
      high = mid - 1
    } else if cp > end {
      low = mid + 1
    } else {
      return true
    }
  }
  false
}

///|
/// The P or S general category.
fn is_unicode_punct(c : Char) -> Bool {
  let cp = c.to_int()
  let mut low = 0
  let mut high = punctuation_ranges.length() / 2 - 1
  while low <= high {
    let mid = (low + high) / 2
    let start = punctuation_ranges[mid * 2]
    let end = punctuation_ranges[mid * 2 + 1]
    if cp < start {
      high = mid - 1
    } else if cp > end {
      low = mid + 1
    } else {
      return true
    }
  }
  false
}

///|
/// Look up a named character reference by its name, without the `&` and `;`.
fn entity_by_name(name : StringView) -> String? {
  let mut low = 0
  let mut high = entity_names.length() - 1
  while low <= high {
    let mid = (low + high) / 2
    let order = entity_names[mid][:].lexical_compare(name)
    if order == 0 {
      return Some(entity_values[mid])
    } else if order < 0 {
      low = mid + 1
    } else {
      high = mid - 1
    }
  }
  None
}

///|
/// The upper case hexadecimal digit for a value below sixteen.
fn hex_digit(value : Int32) -> Char {
  Int32::unsafe_to_char(
    if value < 10 {
      0x30 + value
    } else {
      0x41 + value - 10
    },
  )
}

///|
/// Encode a code point as the UTF-8 percent escapes an href may hold.
fn write_percent_encoded(buf : StringBuilder, cp : Int32) -> Unit {
  let bytes : Array[Int32] = []
  if cp < 0x80 {
    bytes.push(cp)
  } else if cp < 0x800 {
    bytes.push(0xC0 | (cp >> 6))
    bytes.push(0x80 | (cp & 0x3F))
  } else if cp < 0x10000 {
    bytes.push(0xE0 | (cp >> 12))
    bytes.push(0x80 | ((cp >> 6) & 0x3F))
    bytes.push(0x80 | (cp & 0x3F))
  } else {
    bytes.push(0xF0 | (cp >> 18))
    bytes.push(0x80 | ((cp >> 12) & 0x3F))
    bytes.push(0x80 | ((cp >> 6) & 0x3F))
    bytes.push(0x80 | (cp & 0x3F))
  }
  for byte in bytes {
    buf.write_char('%')
    buf.write_char(hex_digit(byte >> 4))
    buf.write_char(hex_digit(byte & 0xF))
  }
}

///|
/// The replacement text of the entity reference at `pos` and how many code
/// units it spans, or `("", 0)` when there is none there. `pos` points at `&`.
fn entity_at(text : StringView, pos : Int32) -> (String, Int32) {
  let n = text.length()
  let mut i = pos + 1
  if cu(text, i) != 0x23 {
    // A named reference.
    let mut name_len = 0
    while name_len < 32 && is_alnum(cu(text, i + name_len)) {
      name_len = name_len + 1
    }
    if name_len < 2 || cu(text, i + name_len) != 0x3B {
      return ("", 0)
    }
    match entity_by_name(text.clamped_view(start=i, end=i + name_len)) {
      Some(value) => (value, name_len + 2)
      None => ("", 0)
    }
  } else {
    // `&#123;` or `&#x7B;`, at most seven decimal or six hexadecimal digits.
    i = i + 1
    let mut value = 0
    let mut digits = 0
    if cu(text, i) == 0x78 || cu(text, i) == 0x58 {
      i = i + 1
      while digits < 6 {
        let c = cu(text, i)
        let digit = if c >= 0x30 && c <= 0x39 {
          c - 0x30
        } else if c >= 0x61 && c <= 0x66 {
          c - 0x57
        } else if c >= 0x41 && c <= 0x46 {
          c - 0x37
        } else {
          break
        }
        value = value * 16 + digit
        digits = digits + 1
        i = i + 1
      }
    } else {
      while digits < 7 && is_digit(cu(text, i)) {
        value = value * 10 + (cu(text, i) - 0x30)
        digits = digits + 1
        i = i + 1
      }
    }
    if digits == 0 || cu(text, i) != 0x3B || i >= n + 1 {
      return ("", 0)
    }
    if value == 0 || value > 0x10FFFF || (value >= 0xD800 && value <= 0xDFFF) {
      value = 0xFFFD
    }
    let buf = StringBuilder()
    buf.write_char(Int32::unsafe_to_char(value))
    (buf.to_string(), i + 1 - pos)
  }
}

///|
/// Replace every entity reference in `text` by what it stands for.
fn html_unescape(text : StringView) -> String {
  if !text.contains_char('&') {
    return text.to_owned()
  }
  let buf = StringBuilder()
  let n = text.length()
  let mut i = 0
  while i < n {
    if cu(text, i) == 0x26 {
      let (value, len) = entity_at(text, i)
      if len > 0 {
        buf.write_string(value)
        i = i + len
        continue
      }
    }
    let c = char_at(text, i)
    buf.write_char(c)
    i = i + c.utf16_len()
  }
  buf.to_string()
}

///|
/// Remove the backslashes in front of ASCII punctuation. Entities in the
/// entities region are left alone: callers run this after `html_unescape`.
fn unescape_backslashes(text : StringView) -> String {
  if !text.contains_char('\\') {
    return text.to_owned()
  }
  let buf = StringBuilder()
  let n = text.length()
  let mut i = 0
  while i < n {
    if cu(text, i) == 0x5C && is_ascii_punct(cu(text, i + 1)) {
      i = i + 1
    }
    buf.write_char(char_at(text, i))
    i = i + char_at(text, i).utf16_len()
  }
  buf.to_string()
}

///|
/// Turn the code span's newlines into spaces and drop one space at each end
/// when the span is not made of spaces only.
fn normalize_code(text : StringView) -> String {
  let buf = StringBuilder()
  let mut has_content = false
  for c in text {
    if c == '\r' {
      continue
    }
    if c == '\n' {
      buf.write_char(' ')
    } else {
      buf.write_char(c)
      if c != ' ' {
        has_content = true
      }
    }
  }
  let result = buf.to_string()
  if has_content &&
    result.length() >= 2 &&
    result.at(0).to_int() == 0x20 &&
    result.at(result.length() - 1).to_int() == 0x20 {
    return result.clamped_view(start=1, end=result.length() - 1).to_owned()
  }
  result
}

///|
/// How a link label compares: case folded, trimmed, inner whitespace collapsed.
fn normalize_label(text : StringView) -> String {
  let folded = StringBuilder()
  for c in text {
    match fold_lookup(c.to_int()) {
      Some(value) => folded.write_string(value)
      None => folded.write_char(c)
    }
  }
  let buf = StringBuilder()
  let mut pending_space = false
  let mut written = 0
  for c in folded.to_string() {
    if c == ' ' ||
      c == '\t' ||
      c == '\n' ||
      c == '\r' ||
      c == '\u{0B}' ||
      c == '\u{0C}' {
      pending_space = true
    } else {
      if pending_space && written > 0 {
        buf.write_char(' ')
        written = written + 1
      }
      pending_space = false
      buf.write_char(c)
      written = written + 1
    }
  }
  buf.to_string()
}

///|
/// The full case folding of a code point, if it differs from the character.
fn fold_lookup(cp : Int32) -> String? {
  let mut low = 0
  let mut high = fold_from.length() - 1
  while low <= high {
    let mid = (low + high) / 2
    let value = fold_from[mid]
    if value == cp {
      return Some(fold_to[mid])
    } else if value < cp {
      low = mid + 1
    } else {
      high = mid - 1
    }
  }
  None
}

///|
/// A link destination as the tree keeps it: trimmed, entities and backslash
/// escapes resolved.
fn clean_url(text : StringView) -> String {
  let trimmed = trim_view(text)
  if trimmed.is_empty() {
    return ""
  }
  unescape_backslashes(html_unescape(trimmed))
}

///|
/// A link title as the tree keeps it: surrounding quotes removed, entities and
/// backslash escapes resolved.
fn clean_title(text : StringView) -> String {
  if text.is_empty() {
    return ""
  }
  let first = text.at(0).to_int()
  let last = text.at(text.length() - 1).to_int()
  let inner = if (first == 0x27 && last == 0x27) ||
    (first == 0x28 && last == 0x29) ||
    (first == 0x22 && last == 0x22) {
    text.clamped_view(start=1, end=text.length() - 1)
  } else {
    text
  }
  unescape_backslashes(html_unescape(inner))
}

///|
/// Write `text` with the four characters that matter inside HTML escaped.
fn write_html_escaped(buf : StringBuilder, text : StringView) -> Unit {
  for c in text {
    match c {
      '&' => buf.write_string("&amp;")
      '<' => buf.write_string("&lt;")
      '>' => buf.write_string("&gt;")
      '"' => buf.write_string("&quot;")
      _ => buf.write_char(c)
    }
  }
}

///|
/// Whether a code point may appear in an href as it is. Everything else is
/// percent-encoded, which is what keeps international URLs working.
fn is_href_safe(c : Int32) -> Bool {
  if (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x61 && c <= 0x7A) {
    return true
  }
  match c {
    0x21
    | 0x23
    | 0x24
    | 0x25
    | 0x28
    | 0x29
    | 0x2A
    | 0x2B
    | 0x2C
    | 0x2D
    | 0x2E
    | 0x2F
    | 0x3A
    | 0x3B
    | 0x3D
    | 0x3F
    | 0x40
    | 0x5F
    | 0x7E => true
    _ => false
  }
}

///|
/// Write a link destination the way an `href` attribute needs it.
fn write_href_escaped(buf : StringBuilder, text : StringView) -> Unit {
  for c in text {
    let cp = c.to_int()
    if c == '&' {
      buf.write_string("&amp;")
    } else if c == '\'' {
      buf.write_string("&#x27;")
    } else if cp < 0x80 && is_href_safe(cp) {
      buf.write_char(c)
    } else {
      write_percent_encoded(buf, cp)
    }
  }
}

///|
/// Whether a destination would run script or reach the local file system, and
/// so must not be linked to when the document is rendered safely.
fn is_dangerous_url(url : StringView) -> Bool {
  let lower = url.to_lower().to_owned()
  if lower.has_prefix("javascript:"[:]) ||
    lower.has_prefix("vbscript:"[:]) ||
    lower.has_prefix("file:"[:]) {
    return true
  }
  if lower.has_prefix("data:"[:]) {
    return !(lower.has_prefix("data:image/png"[:]) ||
      lower.has_prefix("data:image/gif"[:]) ||
      lower.has_prefix("data:image/jpeg"[:]) ||
      lower.has_prefix("data:image/webp"[:]))
  }
  false
}
