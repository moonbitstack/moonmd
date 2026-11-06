// Feeding a document in pieces has to give the same blocks as reading it at
// once, whatever the pieces are. Every example is fed one character at a time,
// which covers every place a chunk could end.

///|
/// Where each character of the text starts, and the end of the text: a chunk
/// boundary has to fall between characters, never inside one.
fn character_offsets(text : String) -> Array[Int32] {
  let offsets : Array[Int32] = []
  let n = text.length()
  let mut i = 0
  while i < n {
    offsets.push(i)
    i = i + text[:].get_char(i).unwrap().utf16_len()
  }
  offsets.push(n)
  offsets
}

///|
fn stream_html(
  markdown : String,
  flavor : @moonmd.Flavor,
  chunk : Int32,
) -> String {
  let offsets = character_offsets(markdown)
  let stream = @moonmd.Stream::new(flavor~)
  let blocks : Array[@moonmd.Block] = []
  let mut k = 0
  while k + 1 < offsets.length() {
    let next = if k + chunk < offsets.length() - 1 {
      k + chunk
    } else {
      offsets.length() - 1
    }
    blocks.append(
      stream.feed(markdown.clamped_view(start=offsets[k], end=offsets[next]))[:],
    )
    k = next
  }
  blocks.append(stream.finish()[:])
  @moonmd.Document::of_blocks(blocks, flavor~).html(safe=false)
}

///|
fn check_stream(
  name : String,
  cases : Array[@spec.Case],
  flavor : @moonmd.Flavor,
) -> Int32 {
  let failures : Array[String] = []
  for case in cases {
    let once = @moonmd.parse(case.markdown[:], flavor~).html(safe=false)
    for chunk in [1, 2, 3, 5, 8] {
      if stream_html(case.markdown, flavor, chunk) != once {
        failures.push("example \{case.example} in chunks of \{chunk}")
        break
      }
    }
  }
  println(
    "\{name} stream: \{cases.length() - failures.length()}/\{cases.length()} passed",
  )
  let shown = if failures.length() > 8 { 8 } else { failures.length() }
  for i in 0..<shown {
    println(failures[i])
  }
  failures.length()
}

///|
test "CommonMark streaming" {
  let failed = check_stream(
    "commonmark",
    @spec.commonmark_cases(),
    @moonmd.commonmark,
  )
  assert_eq(failed, 0, msg="examples whose streamed blocks differ")
}

///|
test "GitHub Flavored Markdown streaming" {
  let cases : Array[@spec.Case] = []
  for case in @spec.gfm_cases() {
    if case.html.trim() != "<IGNORE>" {
      cases.push(case)
    }
  }
  let failed = check_stream("gfm", cases, @moonmd.gfm)
  assert_eq(failed, 0, msg="extension examples whose streamed blocks differ")
}
