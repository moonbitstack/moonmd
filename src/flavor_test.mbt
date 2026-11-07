// The two presets, and what each extension adds.

///|
test "the default preset is GitHub Flavored Markdown" {
  assert_eq(@moonmd.flavor.tables, true)
  assert_eq(@moonmd.flavor.strikethrough, true)
  assert_eq(@moonmd.flavor.autolinks, true)
  assert_eq(@moonmd.flavor.task_lists, true)
  assert_eq(@moonmd.flavor.tag_filter, true)
}

///|
test "the commonmark preset has no extension" {
  let document = @moonmd.parse("| a |\n| - |\n"[:], flavor=@moonmd.commonmark)
  assert_eq(document.html(safe=false), "<p>| a |\n| - |</p>\n")
}

///|
test "a table only exists in a flavor with tables" {
  let source = "| a |\n| - |\n| b |\n"
  assert_eq(
    @moonmd.parse(source[:], flavor=@moonmd.gfm).html(safe=false),
    "<table>\n<thead>\n<tr>\n<th>a</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>b</td>\n</tr>\n</tbody>\n</table>\n",
  )
  assert_eq(
    @moonmd.parse(source[:], flavor=@moonmd.commonmark).html(safe=false),
    "<p>| a |\n| - |\n| b |</p>\n",
  )
}

///|
test "strikethrough is an extension" {
  assert_eq(
    @moonmd.parse("~~gone~~"[:], flavor=@moonmd.gfm).html(safe=false),
    "<p><del>gone</del></p>\n",
  )
  assert_eq(
    @moonmd.parse("~~gone~~"[:], flavor=@moonmd.commonmark).html(safe=false),
    "<p>~~gone~~</p>\n",
  )
}

///|
test "bare links are an extension" {
  assert_eq(
    @moonmd.parse("see www.example.com"[:], flavor=@moonmd.gfm).html(safe=false),
    "<p>see <a href=\"http://www.example.com\">www.example.com</a></p>\n",
  )
  assert_eq(
    @moonmd.parse("see www.example.com"[:], flavor=@moonmd.commonmark).html(
      safe=false,
    ),
    "<p>see www.example.com</p>\n",
  )
}

///|
test "task list items are an extension" {
  assert_eq(
    @moonmd.parse("- [x] done\n"[:], flavor=@moonmd.gfm).html(safe=false),
    "<ul>\n<li><input type=\"checkbox\" checked=\"\" disabled=\"\" /> done</li>\n</ul>\n",
  )
  assert_eq(
    @moonmd.parse("- [x] done\n"[:], flavor=@moonmd.commonmark).html(safe=false),
    "<ul>\n<li>[x] done</li>\n</ul>\n",
  )
}

///|
test "a flavor can be taken apart field by field" {
  let only_tables : @moonmd.Flavor = {
    tables: true,
    strikethrough: false,
    autolinks: false,
    task_lists: false,
    tag_filter: false,
    footnotes: false,
  }
  assert_eq(
    @moonmd.parse("~~gone~~"[:], flavor=only_tables).html(safe=false),
    "<p>~~gone~~</p>\n",
  )
}
