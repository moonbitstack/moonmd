// Footnotes: a reference in the text, its definition, and the notes section the
// two are written into.

///|
fn has_sub(haystack : String, needle : String) -> Bool {
  if needle.length() == 0 {
    return true
  }
  if needle.length() > haystack.length() {
    return false
  }
  let max = haystack.length() - needle.length()
  for i in 0..<=max {
    let slice = haystack.clamped_view(start=i, end=i + needle.length())
    if slice == needle[:] {
      return true
    }
  }
  false
}

///|
test "a reference becomes a numbered marker and a definition its body" {
  let document = @moonmd.parse(
    "Here is a note.[^1]\n\n[^1]: The first note.\n"[:],
  )
  assert_eq(
    document.html(safe=false),
    "<p>Here is a note.<sup class=\"footnote-ref\"><a href=\"#fn-1\" id=\"fnref-1\" data-footnote-ref>1</a></sup></p>\n" +
    "<section class=\"footnotes\" data-footnotes>\n<ol>\n<li id=\"fn-1\">\n" +
    "<p>The first note. <a href=\"#fnref-1\" class=\"footnote-backref\" data-footnote-backref data-footnote-backref-idx=\"1\" aria-label=\"Back to reference 1\">↩</a></p>\n" +
    "</li>\n</ol>\n</section>\n",
  )
}

///|
test "the reference keeps its label, number and order" {
  let document = @moonmd.parse("a[^x]\n\n[^x]: b\n"[:])
  match document.blocks()[0] {
    @moonmd.Paragraph(inlines) => {
      assert_eq(inlines.length(), 2)
      match inlines[1] {
        @moonmd.FootnoteRef(reference) => {
          assert_eq(reference.label, "x")
          assert_eq(reference.number, 1)
          assert_eq(reference.ref_ix, 1)
        }
        _ => fail("the second inline is not a footnote reference")
      }
    }
    _ => fail("the first block is not a paragraph")
  }
}

///|
test "the definition carries its label, number and backref count" {
  let document = @moonmd.parse("a[^x]\n\n[^x]: b\n"[:])
  match document.blocks()[1] {
    @moonmd.Footnote(footnote) => {
      assert_eq(footnote.label, "x")
      assert_eq(footnote.number, 1)
      assert_eq(footnote.backrefs, 1)
      assert_eq(footnote.blocks.length(), 1)
    }
    _ => fail("the last block is not a footnote")
  }
}

///|
test "an unresolved reference keeps the text it was written as" {
  let document = @moonmd.parse("no referent[^none]\n"[:])
  assert_eq(document.html(safe=false), "<p>no referent[^none]</p>\n")
  assert_eq(document.blocks().length(), 1)
}

///|
test "a reference used three times gets three backrefs" {
  let document = @moonmd.parse("one[^a] two[^a] three[^a]\n\n[^a]: back\n"[:])
  assert_eq(
    document.html(safe=false),
    "<p>one<sup class=\"footnote-ref\"><a href=\"#fn-a\" id=\"fnref-a\" data-footnote-ref>1</a></sup> two<sup class=\"footnote-ref\"><a href=\"#fn-a\" id=\"fnref-a-2\" data-footnote-ref>1</a></sup> three<sup class=\"footnote-ref\"><a href=\"#fn-a\" id=\"fnref-a-3\" data-footnote-ref>1</a></sup></p>\n" +
    "<section class=\"footnotes\" data-footnotes>\n<ol>\n<li id=\"fn-a\">\n" +
    "<p>back <a href=\"#fnref-a\" class=\"footnote-backref\" data-footnote-backref data-footnote-backref-idx=\"1\" aria-label=\"Back to reference 1\">↩</a> " +
    "<a href=\"#fnref-a-2\" class=\"footnote-backref\" data-footnote-backref data-footnote-backref-idx=\"1-2\" aria-label=\"Back to reference 1-2\">↩<sup class=\"footnote-ref\">2</sup></a> " +
    "<a href=\"#fnref-a-3\" class=\"footnote-backref\" data-footnote-backref data-footnote-backref-idx=\"1-3\" aria-label=\"Back to reference 1-3\">↩<sup class=\"footnote-ref\">3</sup></a></p>\n" +
    "</li>\n</ol>\n</section>\n",
  )
}

///|
test "a label that would break a link is escaped in the anchors" {
  let document = @moonmd.parse("Hello[^a\"b]\n\n[^a\"b]: pwned\n"[:])
  let html = document.html(safe=false)
  // The quote in the label is percent-escaped, so it cannot end the attribute.
  assert_eq(has_sub(html, "href=\"#fn-a%22b\""), true)
  assert_eq(has_sub(html, "href=\"#fn-a\"b\""), false)
}

///|
test "the number follows the first reference, not the definition" {
  let document = @moonmd.parse(
    "second[^b]\nfirst[^a]\n\n[^b]: body b\n\n[^a]: body a\n"[:],
  )
  let html = document.html(safe=false)
  // `b` is referenced first, so it is 1; `a` is 2.
  assert_eq(has_sub(html, "id=\"fnref-b\" data-footnote-ref>1<"), true)
  assert_eq(has_sub(html, "id=\"fnref-a\" data-footnote-ref>2<"), true)
  // The notes are ordered by first reference: `b` before `a`.
  assert_eq(
    html.has_prefix(
      "<p>second<sup class=\"footnote-ref\"><a href=\"#fn-b\" id=\"fnref-b\"",
    ),
    true,
  )
}

///|
test "a footnote body is read with its indentation" {
  let document = @moonmd.parse(
    "a[^n]\n\n[^n]:\n    > a quote\n\n        indented\n"[:],
  )
  assert_eq(
    document.html(safe=false),
    "<p>a<sup class=\"footnote-ref\"><a href=\"#fn-n\" id=\"fnref-n\" data-footnote-ref>1</a></sup></p>\n" +
    "<section class=\"footnotes\" data-footnotes>\n<ol>\n<li id=\"fn-n\">\n" +
    "<blockquote>\n<p>a quote</p>\n</blockquote>\n" +
    "<pre><code>indented\n</code></pre>\n" +
    "<a href=\"#fnref-n\" class=\"footnote-backref\" data-footnote-backref data-footnote-backref-idx=\"1\" aria-label=\"Back to reference 1\">↩</a>\n" +
    "</li>\n</ol>\n</section>\n",
  )
}

///|
test "footnotes are written back and read the same" {
  let document = @moonmd.parse("a note[^x]\n\n[^x]: the body.\n"[:])
  let written = document.markdown()
  assert_eq(
    @moonmd.parse(written[:]).html(safe=false),
    document.html(safe=false),
  )
}

///|
test "the commonmark flavor reads the caret as ordinary text" {
  let source = "a[^x]\n\n[^x]: b\n"
  // The reference is a footnote only under gfm; under commonmark there is no
  // footnote section at all.
  let gfm = @moonmd.parse(source[:]).html(safe=false)
  assert_eq(has_sub(gfm, "footnote-ref"), true)
  let plain = @moonmd.parse(source[:], flavor=@moonmd.commonmark).html(
    safe=false,
  )
  assert_eq(has_sub(plain, "footnote-ref"), false)
  assert_eq(has_sub(plain, "footnotes"), false)
}
