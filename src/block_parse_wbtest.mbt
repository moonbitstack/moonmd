// The block structure: what a line opens, what it continues, and when a list
// counts as tight.

///|
fn html_of(source : String) -> String {
  parse(source[:], flavor=gfm).html(safe=false)
}

///|
test "a blank line between items makes the list loose" {
  assert_eq(html_of("- a\n- b\n"), "<ul>\n<li>a</li>\n<li>b</li>\n</ul>\n")
  assert_eq(
    html_of("- a\n\n- b\n"),
    "<ul>\n<li>\n<p>a</p>\n</li>\n<li>\n<p>b</p>\n</li>\n</ul>\n",
  )
}

///|
test "a blank line inside an item makes the list loose" {
  assert_eq(
    html_of("- a\n\n  b\n- c\n"),
    "<ul>\n<li>\n<p>a</p>\n<p>b</p>\n</li>\n<li>\n<p>c</p>\n</li>\n</ul>\n",
  )
}

///|
test "an ordered list keeps its first number" {
  assert_eq(html_of("1. a\n2. b\n"), "<ol>\n<li>a</li>\n<li>b</li>\n</ol>\n")
  assert_eq(
    html_of("3. a\n4. b\n"),
    "<ol start=\"3\">\n<li>a</li>\n<li>b</li>\n</ol>\n",
  )
}

///|
test "a marker that changes kind starts a new list" {
  assert_eq(
    html_of("- a\n\n1. b\n"),
    "<ul>\n<li>a</li>\n</ul>\n<ol>\n<li>b</li>\n</ol>\n",
    msg="different markers are different lists",
  )
}

///|
test "a fenced block keeps its info string and drops the fence spaces" {
  assert_eq(
    html_of("```moonbit\nlet a = 1\n```\n"),
    "<pre><code class=\"language-moonbit\">let a = 1\n</code></pre>\n",
  )
  assert_eq(html_of("~~~\nx\n~~~\n"), "<pre><code>x\n</code></pre>\n")
}

///|
test "an unclosed fence runs to the end" {
  assert_eq(html_of("```\nx\n"), "<pre><code>x\n</code></pre>\n")
}

///|
test "indented code keeps its blank lines and drops the trailing ones" {
  assert_eq(html_of("    a\n\n    b\n\n"), "<pre><code>a\n\nb\n</code></pre>\n")
}

///|
test "a tab counts for four columns" {
  assert_eq(html_of("\ta\n"), "<pre><code>a\n</code></pre>\n")
}

///|
test "a quote holds blocks of its own" {
  assert_eq(
    html_of("> # t\n>\n> p\n"),
    "<blockquote>\n<h1>t</h1>\n<p>p</p>\n</blockquote>\n",
  )
}

///|
test "an atx heading drops the closing hashes" {
  assert_eq(html_of("## name ##\n"), "<h2>name</h2>\n")
  assert_eq(html_of("## ###\n"), "<h2></h2>\n")
}

///|
test "a setext underline makes a heading of the line above" {
  assert_eq(html_of("name\n====\n"), "<h1>name</h1>\n")
  assert_eq(html_of("name\n----\n"), "<h2>name</h2>\n")
}

///|
test "three marks on their own are a thematic break" {
  assert_eq(html_of("***\n"), "<hr />\n")
  assert_eq(html_of("- - -\n"), "<hr />\n")
}

///|
test "an html block ends at its own closing mark" {
  assert_eq(
    html_of("<div>\nx\n</div>\n\nafter\n"),
    "<div>\nx\n</div>\n<p>after</p>\n",
  )
}

///|
test "a table keeps its alignment" {
  assert_eq(
    html_of("| l | c | r |\n|:--|:-:|--:|\n| 1 | 2 | 3 |\n"),
    "<table>\n<thead>\n<tr>\n<th align=\"left\">l</th>\n<th align=\"center\">c</th>\n<th align=\"right\">r</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td align=\"left\">1</td>\n<td align=\"center\">2</td>\n<td align=\"right\">3</td>\n</tr>\n</tbody>\n</table>\n",
  )
}

///|
test "a table row is cut to the width of the header" {
  assert_eq(
    html_of("| a |\n| - |\n| 1 | 2 |\n"),
    "<table>\n<thead>\n<tr>\n<th>a</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>1</td>\n</tr>\n</tbody>\n</table>\n",
  )
}

///|
test "a reference definition leaves nothing behind" {
  assert_eq(html_of("[a]: /url\n"), "")
  assert_eq(html_of("[a]: /url\n\ntext\n"), "<p>text</p>\n")
}

///|
test "a paragraph line can be a lazy continuation" {
  assert_eq(
    html_of("> quoted\ncontinued\n"),
    "<blockquote>\n<p>quoted\ncontinued</p>\n</blockquote>\n",
  )
}
