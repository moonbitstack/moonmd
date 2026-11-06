// The text helpers: entities, labels, and the escapers.

///|
test "a named reference is looked up by its name" {
  let (value, len) = entity_at("&amp;"[:], 0)
  assert_eq(value, "&")
  assert_eq(len, 5)
  let (value, len) = entity_at("&ngE;"[:], 0)
  assert_eq(value, "\u{2267}\u{338}")
  assert_eq(len, 5)
}

///|
test "a numeric reference may be decimal or hexadecimal" {
  let (value, len) = entity_at("&#65;"[:], 0)
  assert_eq(value, "A")
  assert_eq(len, 5)
  let (value, len) = entity_at("&#x41;"[:], 0)
  assert_eq(value, "A")
  assert_eq(len, 6)
}

///|
test "a reference that is not closed or not known is nothing" {
  let (_, len) = entity_at("&amp"[:], 0)
  assert_eq(len, 0)
  let (_, len) = entity_at("&#;"[:], 0)
  assert_eq(len, 0)
  let (_, len) = entity_at("&nope;"[:], 0)
  assert_eq(len, 0)
}

///|
test "a numeric reference out of range becomes the replacement character" {
  let (value, _) = entity_at("&#x110000;"[:], 0)
  assert_eq(value, "\u{FFFD}")
}

///|
test "a label is folded, trimmed and squeezed" {
  assert_eq(normalize_label("  Foo   Bar  "[:]), "foo bar")
  assert_eq(normalize_label("ẞ"[:]), "ss")
}

///|
test "an href escapes what an attribute cannot hold" {
  let buf = StringBuilder()
  write_href_escaped(buf, "/a b?c=1&d=2"[:])
  assert_eq(buf.to_string(), "/a%20b?c=1&amp;d=2")
}

///|
test "an href percent-encodes non-ascii as utf-8" {
  let buf = StringBuilder()
  write_href_escaped(buf, "é"[:])
  assert_eq(buf.to_string(), "%C3%A9")
  let buf = StringBuilder()
  write_href_escaped(buf, "🍄"[:])
  assert_eq(buf.to_string(), "%F0%9F%8D%84")
}

///|
test "an href writes a single quote as a reference" {
  let buf = StringBuilder()
  write_href_escaped(buf, "it's"[:])
  assert_eq(buf.to_string(), "it&#x27;s")
}

///|
test "html escaping covers the four characters that matter" {
  let buf = StringBuilder()
  write_html_escaped(buf, "<a href=\"x\">&</a>"[:])
  assert_eq(buf.to_string(), "&lt;a href=&quot;x&quot;&gt;&amp;&lt;/a&gt;")
}

///|
test "a dangerous destination is recognised whatever its case" {
  assert_eq(is_dangerous_url("JavaScript:alert(1)"[:]), true)
  assert_eq(is_dangerous_url("vbscript:x"[:]), true)
  assert_eq(is_dangerous_url("file:///etc"[:]), true)
  assert_eq(is_dangerous_url("data:text/html,x"[:]), true)
  assert_eq(is_dangerous_url("data:image/png;base64,x"[:]), false)
  assert_eq(is_dangerous_url("https://example.com"[:]), false)
}

///|
test "a code span drops the line endings it holds" {
  assert_eq(normalize_code(" a\nb "[:]), "a b")
  assert_eq(normalize_code("  "[:]), "  ")
}

///|
test "whitespace follows the unicode property" {
  assert_eq(is_unicode_space('\u{3000}'), true)
  assert_eq(is_unicode_space('a'), false)
}

///|
test "punctuation includes symbols for emphasis, but not for host names" {
  assert_eq(is_unicode_punct('€'), true)
  assert_eq(is_unicode_punctuation_only('€'), false)
  assert_eq(is_unicode_punctuation_only(','), true)
}
