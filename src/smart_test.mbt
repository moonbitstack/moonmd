// Typographic punctuation: the pass a flavor turns on, and what it leaves
// alone. Every case here was checked against the reference implementation's
// `--smart`: the same document, the same characters out.

///|
let typed : @moonmd.Flavor = {
  tables: true,
  strikethrough: true,
  autolinks: true,
  task_lists: true,
  tag_filter: true,
  footnotes: true,
  smart: true,
  breaks: false,
}

///|
fn read(source : String) -> String {
  @moonmd.parse(source[:], flavor=typed).html(safe=false)
}

///|
test "a double quote curls towards the text it wraps" {
  assert_eq(read("\"quoted\"\n"), "<p>\u{201C}quoted\u{201D}</p>\n")
}

///|
test "a single quote does the same" {
  assert_eq(read("'single'\n"), "<p>\u{2018}single\u{2019}</p>\n")
}

///|
test "an apostrophe closes" {
  assert_eq(read("don't\n"), "<p>don\u{2019}t</p>\n")
  assert_eq(read("5'11\" tall\n"), "<p>5\u{2019}11\u{201D} tall</p>\n")
}

///|
test "a lone single quote is an apostrophe, not an opening quote" {
  assert_eq(read("'tis\n"), "<p>\u{2019}tis</p>\n")
}

///|
test "a single quote opens when another one closes it" {
  assert_eq(read("rock 'n' roll\n"), "<p>rock \u{2018}n\u{2019} roll</p>\n")
}

///|
test "quotes nest" {
  assert_eq(
    read("He said \"she said 'hi'\"\n"),
    "<p>He said \u{201C}she said \u{2018}hi\u{2019}\u{201D}</p>\n",
  )
}

///|
test "a quote pair may wrap other markup" {
  assert_eq(
    read("'*a*' and \"a\" \"b\"\n"),
    "<p>\u{2018}<em>a</em>\u{2019} and \u{201C}a\u{201D} \u{201C}b\u{201D}</p>\n",
  )
}

///|
test "hyphens become dashes, two at a time and three at a time" {
  assert_eq(read("a -- b\n"), "<p>a \u{2013} b</p>\n")
  assert_eq(read("a --- b\n"), "<p>a \u{2014} b</p>\n")
  assert_eq(read("a ---- b\n"), "<p>a \u{2013}\u{2013} b</p>\n")
  assert_eq(read("a ----- b\n"), "<p>a \u{2014}\u{2013} b</p>\n")
  assert_eq(read("a ------ b\n"), "<p>a \u{2014}\u{2014} b</p>\n")
}

///|
test "a single hyphen stays a hyphen" {
  assert_eq(read("a - b\n"), "<p>a - b</p>\n")
}

///|
test "three dots are an ellipsis" {
  assert_eq(read("wait...\n"), "<p>wait\u{2026}</p>\n")
  assert_eq(read("wait....\n"), "<p>wait\u{2026}.</p>\n")
}

///|
test "a code span keeps what it was written with" {
  assert_eq(read("`\"--\"`\n"), "<p><code>&quot;--&quot;</code></p>\n")
}

///|
test "a destination keeps what it was written with" {
  assert_eq(read("[x](/a--b)\n"), "<p><a href=\"/a--b\">x</a></p>\n")
}

///|
test "the text inside emphasis is rewritten" {
  assert_eq(read("*\"x\"*\n"), "<p><em>\u{201C}x\u{201D}</em></p>\n")
}

///|
test "a flavor without it leaves the characters alone" {
  assert_eq(
    @moonmd.parse("\"quoted\" -- ...\n"[:]).html(safe=false),
    "<p>&quot;quoted&quot; -- ...</p>\n",
  )
}
