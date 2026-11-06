// Rendering HTML, in the two modes the caller chooses between.

///|
test "raw html is escaped by default" {
  let document = @moonmd.parse("<div>\nx\n</div>\n"[:])
  assert_eq(document.html(), "&lt;div&gt;\nx\n&lt;/div&gt;\n")
  assert_eq(document.html(safe=false), "<div>\nx\n</div>\n")
}

///|
test "inline html is escaped by default" {
  let document = @moonmd.parse("a <b>c</b>\n"[:])
  assert_eq(document.html(), "<p>a &lt;b&gt;c&lt;/b&gt;</p>\n")
}

///|
test "a dangerous destination keeps its text and loses its link" {
  let document = @moonmd.parse("[click](javascript:alert(1))\n"[:])
  assert_eq(document.html(), "<p>click</p>\n")
  assert_eq(
    document.html(safe=false),
    "<p><a href=\"javascript:alert(1)\">click</a></p>\n",
  )
}

///|
test "an image with a dangerous source shows its alternative text" {
  let document = @moonmd.parse("![alt](file:///etc/passwd)\n"[:])
  assert_eq(document.html(), "<p>alt</p>\n")
}

///|
test "a data url is safe for an image but not for a link" {
  let image = @moonmd.parse("![a](data:image/png;base64,AAAA)\n"[:])
  assert_eq(
    image.html(),
    "<p><img src=\"data:image/png;base64,AAAA\" alt=\"a\" /></p>\n",
  )
  let link = @moonmd.parse("[a](data:text/html,x)\n"[:])
  assert_eq(link.html(), "<p>a</p>\n")
}

///|
test "the tag filter escapes the tags that change the page" {
  let document = @moonmd.parse(
    "<script>alert(1)</script>\n\n<xmp>\n"[:],
    flavor=@moonmd.gfm,
  )
  assert_eq(
    document.html(safe=false),
    "&lt;script>alert(1)&lt;/script>\n&lt;xmp>\n",
  )
}

///|
test "a flavor without the tag filter passes those tags through" {
  let document = @moonmd.parse(
    "<script>a</script>\n"[:],
    flavor=@moonmd.commonmark,
  )
  assert_eq(document.html(safe=false), "<script>a</script>\n")
}

///|
test "text is escaped once" {
  let document = @moonmd.parse("a &amp; b < c\n"[:])
  assert_eq(document.html(), "<p>a &amp; b &lt; c</p>\n")
}

///|
test "an image alt text is flattened to text" {
  let document = @moonmd.parse("![a *b* `c`](i)\n"[:])
  assert_eq(
    document.html(safe=false),
    "<p><img src=\"i\" alt=\"a b c\" /></p>\n",
  )
}
