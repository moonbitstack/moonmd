///|
/// A document that arrives in pieces, the way a model writes one: each block
/// is printed as soon as no later text can change it.
///
///     moon run src/examples/02-stream
#coverage.skip
fn main {
  let chunks = [
    "# Notes\n", "\n", "The first paragraph ", "is written in two chunks.\n", "\n",
    "- a list item\n", "- another\n", "\n", "```moonbit\n", "let answer = 42\n",
    "```\n",
  ]
  let stream = @moonmd.Stream::new()
  for chunk in chunks {
    let blocks = stream.feed(chunk[:])
    for block in blocks {
      println("settled: \{describe(block)}")
    }
  }
  for block in stream.finish() {
    println("at the end: \{describe(block)}")
  }
}

///|
fn describe(block : @moonmd.Block) -> String {
  match block {
    @moonmd.Heading(_) => "a heading"
    @moonmd.Paragraph(_) => "a paragraph"
    @moonmd.Code(_) => "a code block"
    @moonmd.List(_) => "a list"
    @moonmd.Quote(_) => "a quote"
    @moonmd.Table(_) => "a table"
    @moonmd.Html(_) => "raw HTML"
    @moonmd.Break => "a thematic break"
  }
}
