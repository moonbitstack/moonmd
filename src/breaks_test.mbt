// A line ending inside a paragraph is a soft break in the specification. A
// flavor can read it as a hard one, which is what a message box does.

///|
let boxy : @moonmd.Flavor = {
  tables: true,
  strikethrough: true,
  autolinks: true,
  task_lists: true,
  tag_filter: true,
  footnotes: true,
  smart: false,
  breaks: true,
}

///|
fn read_boxed(source : String) -> @moonmd.Document {
  @moonmd.parse(source[:], flavor=boxy)
}

///|
test "a newline renders as a line break" {
  assert_eq(
    read_boxed("one\ntwo\n").html(safe=false),
    "<p>one<br />\ntwo</p>\n",
  )
}

///|
test "the tree says the break is hard" {
  let document = read_boxed("one\ntwo\n")
  let breaks : Array[@moonmd.Break] = []
  @moonmd.walk(document, fn(node) {
    match node {
      @moonmd.Inline(@moonmd.Break(kind)) => breaks.push(kind)
      _ => ()
    }
  })
  assert_eq(breaks.length(), 1)
  assert_eq(breaks[0] is @moonmd.Hard, true)
}

///|
test "markdown writes it back as a hard break" {
  assert_eq(read_boxed("one\ntwo\n").markdown(), "one\\\ntwo\n")
}

///|
test "a break written by hand is a break either way" {
  assert_eq(
    read_boxed("one  \ntwo\n").html(safe=false),
    "<p>one<br />\ntwo</p>\n",
  )
  assert_eq(
    @moonmd.parse("one  \ntwo\n"[:]).html(safe=false),
    "<p>one<br />\ntwo</p>\n",
  )
}

///|
test "a flavor without it keeps the soft break" {
  let document = @moonmd.parse("one\ntwo\n"[:])
  assert_eq(document.html(safe=false), "<p>one\ntwo</p>\n")
  assert_eq(document.markdown(), "one\ntwo\n")
}
