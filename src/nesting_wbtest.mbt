// What a document may nest. Every container is walked again when the tree is
// built and when it is written out, so the parser stops opening them at a
// depth it can carry, and leaves the marker in the text instead. These cases
// are the ones that used to end the process rather than the document.

///|
fn count_of(haystack : String, needle : String) -> Int32 {
  let mut count = 0
  let mut i = 0
  while i + needle.length() <= haystack.length() {
    if haystack.clamped_view(start=i, end=i + needle.length()) == needle[:] {
      count = count + 1
      i = i + needle.length()
    } else {
      i = i + 1
    }
  }
  count
}

///|
test "deeply nested quotes stop at the limit instead of the stack" {
  let source = StringBuilder()
  for _ in 0..<2000 {
    source.write_string("> ")
  }
  source.write_string("bottom\n")
  let html = parse(source.to_string()[:]).html(safe=false)
  assert_eq(count_of(html, "<blockquote>"), MAX_NESTING)
  assert_true(html.contains("bottom"))
}

///|
test "deeply nested lists stop at the limit instead of the stack" {
  let source = StringBuilder()
  for i in 0..<400 {
    for _ in 0..<i {
      source.write_string("  ")
    }
    source.write_string("- one\n")
  }
  let html = parse(source.to_string()[:]).html(safe=false)
  assert_true(count_of(html, "<ul>") <= MAX_NESTING)
  assert_true(html.contains("one"))
}

///|
test "deeply nested emphasis stops at the limit and keeps its text" {
  let source = StringBuilder()
  for _ in 0..<400 {
    source.write_string("*")
  }
  source.write_string("word")
  for _ in 0..<400 {
    source.write_string("*")
  }
  source.write_string("\n")
  let html = parse(source.to_string()[:]).html(safe=false)
  assert_true(count_of(html, "<em>") <= MAX_NESTING)
  assert_true(html.contains("word"))
}

///|
test "deeply nested images stop at the limit and keep their text" {
  let source = StringBuilder()
  for _ in 0..<400 {
    source.write_string("![")
  }
  source.write_string("alt")
  for _ in 0..<400 {
    source.write_string("](/a)")
  }
  source.write_string("\n")
  let html = parse(source.to_string()[:]).html(safe=false)
  assert_true(count_of(html, "<img") <= MAX_NESTING)
  assert_true(html.contains("alt"))
}

///|
test "a document under the limit keeps every level" {
  let source = StringBuilder()
  for _ in 0..<20 {
    source.write_string("> ")
  }
  source.write_string("deep\n")
  let html = parse(source.to_string()[:]).html(safe=false)
  assert_eq(count_of(html, "<blockquote>"), 20)
  assert_eq(count_of(html, "</blockquote>"), 20)
}
