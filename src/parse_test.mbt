// Reading a document whole.

///|
test "an empty document has no blocks" {
  assert_eq(@moonmd.parse(""[:]).blocks().length(), 0)
  assert_eq(@moonmd.parse("\n\n\n"[:]).blocks().length(), 0)
}

///|
test "a paragraph keeps its soft line breaks" {
  let document = @moonmd.parse("one\ntwo\n"[:])
  assert_eq(document.html(safe=false), "<p>one\ntwo</p>\n")
}

///|
test "the last line needs no newline" {
  assert_eq(@moonmd.parse("# title"[:]).html(safe=false), "<h1>title</h1>\n")
  assert_eq(
    @moonmd.parse("- item"[:]).html(safe=false),
    "<ul>\n<li>item</li>\n</ul>\n",
  )
}

///|
test "carriage returns are read as line endings" {
  assert_eq(
    @moonmd.parse("one\r\ntwo\r"[:]).html(safe=false),
    "<p>one\ntwo</p>\n",
  )
}

///|
test "a byte order mark at the start is dropped" {
  assert_eq(
    @moonmd.parse("\u{FEFF}# title\n"[:]).html(safe=false),
    "<h1>title</h1>\n",
  )
}

///|
test "a NUL becomes the replacement character" {
  assert_eq(
    @moonmd.parse("a\u{0}b\n"[:]).html(safe=false),
    "<p>a\u{FFFD}b</p>\n",
  )
}

///|
test "headings of every level" {
  for level in 1..<=6 {
    let marks = "#".repeat(level)
    let document = @moonmd.parse("\{marks} heading\n"[:])
    assert_eq(document.blocks().length(), 1)
    match document.blocks()[0] {
      @moonmd.Heading(heading) => assert_eq(heading.level, level)
      _ => fail("not a heading")
    }
  }
}

///|
test "the document keeps the flavor it was read with" {
  let document = @moonmd.parse("x"[:], flavor=@moonmd.commonmark)
  assert_eq(document.flavor().tables, false)
}
