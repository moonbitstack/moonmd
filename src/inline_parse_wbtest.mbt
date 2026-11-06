// The inline phase: emphasis pairing, code spans, links and escapes.

///|
fn inline_html(source : String) -> String {
  parse(source[:], flavor=gfm).html(safe=false)
}

///|
test "emphasis pairs one mark, strong two" {
  assert_eq(inline_html("*a*\n"), "<p><em>a</em></p>\n")
  assert_eq(inline_html("**a**\n"), "<p><strong>a</strong></p>\n")
  assert_eq(inline_html("***a***\n"), "<p><em><strong>a</strong></em></p>\n")
}

///|
test "an opener without a closer stays text" {
  assert_eq(inline_html("*a\n"), "<p>*a</p>\n")
  assert_eq(inline_html("a**b\n"), "<p>a**b</p>\n")
}

///|
test "an underscore does not pair inside a word" {
  assert_eq(inline_html("a_b_c\n"), "<p>a_b_c</p>\n")
  assert_eq(inline_html("a*b*c\n"), "<p>a<em>b</em>c</p>\n")
}

///|
test "the closer decides how much of the run is used" {
  assert_eq(inline_html("*a**\n"), "<p><em>a</em>*</p>\n")
  assert_eq(inline_html("**a*\n"), "<p>*<em>a</em></p>\n")
}

///|
test "emphasis does not cross a code span" {
  assert_eq(inline_html("*a `*` b*\n"), "<p><em>a <code>*</code> b</em></p>\n")
}

///|
test "a code span trims one space at each end" {
  assert_eq(inline_html("` a `\n"), "<p><code>a</code></p>\n")
  assert_eq(inline_html("`  `\n"), "<p><code>  </code></p>\n")
  assert_eq(inline_html("``a`b``\n"), "<p><code>a`b</code></p>\n")
}

///|
test "a line ending inside code becomes a space" {
  assert_eq(inline_html("`a\nb`\n"), "<p><code>a b</code></p>\n")
}

///|
test "a backslash escapes punctuation only" {
  assert_eq(inline_html("\\*a\\*\n"), "<p>*a*</p>\n")
  assert_eq(inline_html("\\a\n"), "<p>\\a</p>\n")
  assert_eq(inline_html("a\\\nb\n"), "<p>a<br />\nb</p>\n")
}

///|
test "two spaces at the end of a line make a hard break" {
  assert_eq(inline_html("a  \nb\n"), "<p>a<br />\nb</p>\n")
  assert_eq(inline_html("a \nb\n"), "<p>a\nb</p>\n")
}

///|
test "an inline link carries its destination and title" {
  assert_eq(
    inline_html("[a](/b \"t\")\n"),
    "<p><a href=\"/b\" title=\"t\">a</a></p>\n",
  )
  assert_eq(inline_html("[a](<b c>)\n"), "<p><a href=\"b%20c\">a</a></p>\n")
  assert_eq(
    inline_html("![alt](/i \"t\")\n"),
    "<p><img src=\"/i\" alt=\"alt\" title=\"t\" /></p>\n",
  )
}

///|
test "a destination escapes what an attribute cannot hold" {
  assert_eq(
    inline_html("[a](/x?y=1&z=2)\n"),
    "<p><a href=\"/x?y=1&amp;z=2\">a</a></p>\n",
  )
  assert_eq(inline_html("[a](/é)\n"), "<p><a href=\"/%C3%A9\">a</a></p>\n")
}

///|
test "a reference link uses the definition it names" {
  assert_eq(
    inline_html("[a][ref]\n\n[ref]: /url \"title\"\n"),
    "<p><a href=\"/url\" title=\"title\">a</a></p>\n",
  )
  assert_eq(inline_html("[a][]\n\n[a]: /u\n"), "<p><a href=\"/u\">a</a></p>\n")
  assert_eq(inline_html("[a]\n\n[a]: /u\n"), "<p><a href=\"/u\">a</a></p>\n")
  assert_eq(inline_html("[a][missing]\n"), "<p>[a][missing]</p>\n")
}

///|
test "a label is compared without case or extra space" {
  assert_eq(
    inline_html("[a][ REF ]\n\n[ref]: /u\n"),
    "<p><a href=\"/u\">a</a></p>\n",
  )
}

///|
test "a link does not hold another link" {
  assert_eq(
    inline_html("[a [b](c)](d)\n"),
    "<p>[a <a href=\"c\">b</a>](d)</p>\n",
  )
}

///|
test "an angle autolink keeps its text" {
  assert_eq(
    inline_html("<https://example.com>\n"),
    "<p><a href=\"https://example.com\">https://example.com</a></p>\n",
  )
  assert_eq(
    inline_html("<a@b.co>\n"),
    "<p><a href=\"mailto:a@b.co\">a@b.co</a></p>\n",
  )
}

///|
test "a bare link stops before the sentence's punctuation" {
  assert_eq(
    inline_html("see http://a.bb/c.\n"),
    "<p>see <a href=\"http://a.bb/c\">http://a.bb/c</a>.</p>\n",
  )
}

///|
test "an entity is decoded, an unknown one is text" {
  assert_eq(inline_html("&amp; &#65; &#x41;\n"), "<p>&amp; A A</p>\n")
  assert_eq(inline_html("&nope;\n"), "<p>&amp;nope;</p>\n")
}

///|
test "raw html is passed through when the renderer allows it" {
  assert_eq(inline_html("a <b>c</b>\n"), "<p>a <b>c</b></p>\n")
  assert_eq(inline_html("a <!-- c -->\n"), "<p>a <!-- c --></p>\n")
}

///|
test "strikethrough takes one or two tildes, never three" {
  assert_eq(inline_html("~a~\n"), "<p><del>a</del></p>\n")
  assert_eq(inline_html("x ~~~a~~~ y\n"), "<p>x ~~~a~~~ y</p>\n")
  assert_eq(inline_html("~a~~\n"), "<p>~a~~</p>\n")
}

///|
test "a soft break inside emphasis stays inside" {
  assert_eq(inline_html("*a\nb*\n"), "<p><em>a\nb</em></p>\n")
}
