// Walking the tree.

///|
test "walk visits every block and inline, containers first" {
  let document = @moonmd.parse("# t\n\np *e* `c`\n\n- i\n"[:])
  let seen : Array[String] = []
  @moonmd.walk(document, fn(node) {
    match node {
      @moonmd.Block(@moonmd.Heading(_)) => seen.push("heading")
      @moonmd.Block(@moonmd.Paragraph(_)) => seen.push("paragraph")
      @moonmd.Block(@moonmd.List(_)) => seen.push("list")
      @moonmd.Inline(@moonmd.Text(_)) => seen.push("text")
      @moonmd.Inline(@moonmd.Emphasis(_)) => seen.push("emphasis")
      @moonmd.Inline(@moonmd.Code(_)) => seen.push("code")
      _ => ()
    }
  })
  assert_eq(
    seen.join(","),
    "heading,text,paragraph,text,emphasis,text,text,code,list,paragraph,text",
  )
}

///|
test "a heading keeps its level and content" {
  let document = @moonmd.parse("### three\n"[:])
  match document.blocks()[0] {
    @moonmd.Heading(heading) => {
      assert_eq(heading.level, 3)
      assert_eq(heading.content.length(), 1)
    }
    _ => fail("not a heading")
  }
}

///|
test "a list item reports its task marker" {
  let document = @moonmd.parse("- [x] done\n- [ ] todo\n- plain\n"[:])
  match document.blocks()[0] {
    @moonmd.List(list) => {
      assert_eq(list.items.length(), 3)
      match list.items[0].task {
        @moonmd.Checked => ()
        _ => fail("first item is not checked")
      }
      match list.items[1].task {
        @moonmd.Unchecked => ()
        _ => fail("second item is not unchecked")
      }
      match list.items[2].task {
        @moonmd.Plain => ()
        _ => fail("third item is not plain")
      }
    }
    _ => fail("not a list")
  }
}

///|
test "a table reports its columns and rows" {
  let document = @moonmd.parse("| a | b |\n|:--|--:|\n| 1 | 2 |\n"[:])
  match document.blocks()[0] {
    @moonmd.Table(table) => {
      assert_eq(table.align.length(), 2)
      assert_eq(table.head.length(), 2)
      assert_eq(table.body.length(), 1)
    }
    _ => fail("not a table")
  }
}
