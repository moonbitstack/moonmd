// The snippets on the documentation site, with the output each one prints.
// A guide that drifts from the library is worse than no guide.

///|
test "the guide reads a document" {
  let document = parse("# Notes\n\nA *small* page.\n"[:])
  assert_eq(
    document.html(safe=false),
    "<h1>Notes</h1>\n<p>A <em>small</em> page.</p>\n",
  )
}

///|
test "the guide walks a tree" {
  let document = parse("# Notes\n\n- one\n- two\n"[:])
  let seen : Array[String] = []
  walk(document, fn(node) {
    match node {
      Block(Heading(heading)) => seen.push("heading, level \{heading.level}")
      Block(List(list)) => seen.push("list of \{list.items.length()}")
      Inline(Text(text)) => seen.push("text: \{text}")
      _ => ()
    }
  })
  assert_eq(
    seen.join("\n"),
    "heading, level 1\ntext: Notes\nlist of 2\ntext: one\ntext: two",
  )
}

///|
test "the guide renders both ways" {
  let page = parse("<b>bold</b> [x](javascript:alert(1))\n"[:])
  assert_eq(page.html(), "<p>&lt;b&gt;bold&lt;/b&gt; x</p>\n")
  assert_eq(
    page.html(safe=false),
    "<p><b>bold</b> <a href=\"javascript:alert(1)\">x</a></p>\n",
  )
}

///|
test "the guide writes markdown back" {
  let document = parse("# Notes\n\nA *small* page.\n"[:])
  assert_eq(document.markdown(), "# Notes\n\nA *small* page.\n")
}

///|
test "the guide streams a document" {
  let stream = Stream::new()
  assert_eq(stream.feed("# Notes\n\nA *sm"[:]).length(), 1)
  assert_eq(stream.feed("all* page.\n\n"[:]).length(), 1)
  assert_eq(stream.finish().length(), 0)
}

///|
test "the guide turns an extension off" {
  let plain = parse("~~gone~~\n"[:], flavor=commonmark)
  assert_eq(plain.html(safe=false), "<p>~~gone~~</p>\n")
}
