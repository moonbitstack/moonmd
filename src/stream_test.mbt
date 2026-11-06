// Feeding a document in pieces.

///|
fn blocks_html(blocks : Array[@moonmd.Block]) -> String {
  @moonmd.Document::of_blocks(blocks).html(safe=false)
}

///|
test "a block is handed out once it is closed" {
  let stream = @moonmd.Stream::new()
  assert_eq(
    stream.feed("# heading\n"[:]).length(),
    0,
    msg="the line is not even finished",
  )
  assert_eq(blocks_html(stream.feed("\n"[:])), "<h1>heading</h1>\n")
  assert_eq(blocks_html(stream.finish()), "")
}

///|
test "a paragraph waits for the blank line that ends it" {
  let stream = @moonmd.Stream::new()
  assert_eq(stream.feed("one "[:]).length(), 0)
  assert_eq(stream.feed("two"[:]).length(), 0)
  assert_eq(stream.feed("\n"[:]).length(), 0)
  assert_eq(blocks_html(stream.feed("\n"[:])), "<p>one two</p>\n")
}

///|
test "a code block settles when its fence closes" {
  let stream = @moonmd.Stream::new()
  assert_eq(stream.feed("```\n"[:]).length(), 0)
  assert_eq(stream.feed("code\n"[:]).length(), 0)
  assert_eq(
    blocks_html(stream.feed("```\n"[:])),
    "<pre><code>code\n</code></pre>\n",
  )
}

///|
test "a half-written line is held back" {
  let stream = @moonmd.Stream::new()
  assert_eq(stream.feed("# half"[:]).length(), 0)
  assert_eq(
    blocks_html(stream.feed(" a heading\n\n"[:])),
    "<h1>half a heading</h1>\n",
  )
}

///|
test "finish emits whatever is still open" {
  let stream = @moonmd.Stream::new()
  let _ = stream.feed("a paragraph"[:])
  assert_eq(blocks_html(stream.finish()), "<p>a paragraph</p>\n")
  assert_eq(stream.finish().length(), 0, msg="finish may only be called once")
}

///|
test "a definition written later still applies by default" {
  let stream = @moonmd.Stream::new()
  let blocks : Array[@moonmd.Block] = []
  blocks.append(stream.feed("[a]\n\n"[:])[:])
  blocks.append(stream.feed("[a]: /url\n\n"[:])[:])
  blocks.append(stream.finish()[:])
  assert_eq(blocks_html(blocks), "<p><a href=\"/url\">a</a></p>\n")
}

///|
test "with defer_links off a block is handed out sooner, and loses the forward reference" {
  let stream = @moonmd.Stream::new(defer_links=false)
  let early = stream.feed("[a]\n\n"[:])
  assert_eq(blocks_html(early), "<p>[a]</p>\n")
  let _ = stream.feed("[a]: /url\n\n"[:])
  assert_eq(stream.finish().length(), 0)
}
