// The lines each block came from: what a caller needs to split a document, or
// to point a reader at the text behind a node.

///|
fn spans(document : @moonmd.Document) -> Array[(Int32, Int32)] {
  document.lines().map(fn(span) { (span.first, span.last) })
}

///|
test "each block reports the lines it was read from" {
  let document = @moonmd.parse("# One\n\ntwo\nthree\n")
  assert_eq(spans(document), [(1, 1), (3, 4)])
}

///|
test "blank lines between blocks belong to neither" {
  let document = @moonmd.parse("one\n\n\n\ntwo\n\n")
  assert_eq(spans(document), [(1, 1), (5, 5)])
}

///|
test "a setext heading covers its underline" {
  let document = @moonmd.parse("Title\n=====\n\nbody\n")
  assert_eq(spans(document), [(1, 2), (4, 4)])
}

///|
test "a container covers the lines of everything inside it" {
  let document = @moonmd.parse("- one\n- two\n\n  more\n\nafter\n")
  assert_eq(spans(document), [(1, 4), (6, 6)])
}

///|
test "a fenced block covers its blank lines" {
  let document = @moonmd.parse("```\na\n\nb\n```\n\nafter\n")
  assert_eq(spans(document), [(1, 5), (7, 7)])
}

///|
test "a table covers its header, delimiter and rows" {
  let document = @moonmd.parse("| a |\n| - |\n| b |\n")
  assert_eq(spans(document), [(1, 3)])
}

///|
test "the notes a footnote is written on stay with its block" {
  let document = @moonmd.parse("claim[^n]\n\n[^n]: body\n")
  assert_eq(spans(document), [(1, 1), (3, 3)])
  assert_eq(document.blocks().length(), 2)
}

///|
test "a document with no blocks has no lines" {
  let document = @moonmd.parse("\n\n")
  assert_eq(document.lines().length(), 0)
}

///|
test "a document assembled from blocks has no source to point at" {
  let blocks = @moonmd.parse("# One\n").blocks()
  let document = @moonmd.Document::of_blocks(blocks)
  assert_eq(document.lines().length(), 0)
  assert_eq(document.blocks().length(), 1)
}
