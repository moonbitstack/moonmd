// Writing the tree back as Markdown, and reading it again.

///|
test "a document reads back the same" {
  let source =
    #|# Title
    #|
    #|A paragraph with *emphasis*, **strength**, `code`, a [link](/u) and an
    #|![image](/i).
    #|
    #|- one
    #|- two
    #|  - nested
    #|
    #|> quoted
    #|
    #|```moonbit
    #|let a = 1
    #|```
    #|
    #|| a | b |
    #||:--|--:|
    #|| 1 | 2 |
    #|
  let document = @moonmd.parse(source[:])
  let written = document.markdown()
  assert_eq(
    @moonmd.parse(written[:]).html(safe=false),
    document.html(safe=false),
  )
}

///|
test "text that would start a block is escaped" {
  let document = @moonmd.parse("\\# not a heading\n"[:])
  let written = document.markdown()
  assert_eq(written, "\\# not a heading\n")
  assert_eq(
    @moonmd.parse(written[:]).html(safe=false),
    "<p># not a heading</p>\n",
  )
}

///|
test "a numbered line at the start is escaped" {
  let document = @moonmd.parse("1\\. not a list\n"[:])
  assert_eq(document.markdown(), "1\\. not a list\n")
}

///|
test "the writer keeps the list markers of the document" {
  let document = @moonmd.parse("* a\n\n+ b\n"[:])
  assert_eq(document.markdown(), "* a\n\n+ b\n")
}

///|
test "a loose list keeps its blank lines" {
  let document = @moonmd.parse("- a\n\n- b\n"[:])
  assert_eq(document.markdown(), "- a\n\n- b\n")
}

///|
test "a code fence is longer than any run inside" {
  let document = @moonmd.parse("~~~\na ``` b\n~~~\n"[:])
  assert_eq(document.markdown(), "````\na ``` b\n````\n")
}

///|
test "the writer ends with one newline" {
  let document = @moonmd.parse("a\n"[:])
  assert_eq(document.markdown(), "a\n")
  assert_eq(@moonmd.parse(""[:]).markdown(), "\n")
}
