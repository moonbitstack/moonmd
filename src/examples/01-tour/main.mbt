///|
/// A document read whole: look at its tree, its HTML, and the Markdown it is
/// written back as.
///
///     moon run src/examples/01-tour
#coverage.skip
fn main {
  let source =
    #|# Reading Markdown
    #|
    #|A *small* document with a [link](https://example.com), some `code`,
    #|and a list:
    #|
    #|- one
    #|- two, with **weight**
    #|
  let document = @moonmd.parse(source[:])
  println("HTML:")
  println(document.html(safe=false))
  println("")
  println("Markdown again:")
  println(document.markdown())
  println("")
  let counts = [0, 0]
  @moonmd.walk(document, fn(node) {
    match node {
      @moonmd.Block(@moonmd.Heading(_)) => counts[0] = counts[0] + 1
      @moonmd.Inline(@moonmd.Link(_)) => counts[1] = counts[1] + 1
      _ => ()
    }
  })
  println("headings: \{counts[0]}, links: \{counts[1]}")
}
