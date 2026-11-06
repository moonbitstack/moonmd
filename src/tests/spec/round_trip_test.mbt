// Writing the tree back as Markdown has to give a document that reads the same
// way: the HTML of the round trip is the HTML of the original.

///|
fn show_visible(text : String) -> String {
  let out = StringBuilder()
  for c in text {
    if c == '\n' {
      out.write_string("\\n")
    } else if c == '\t' {
      out.write_string("\\t")
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
fn check_round_trip(
  name : String,
  cases : Array[@spec.Case],
  flavor : @moonmd.Flavor,
) -> Int32 {
  let failures : Array[String] = []
  for case in cases {
    let document = @moonmd.parse(case.markdown[:], flavor~)
    let written = document.markdown()
    let again = @moonmd.parse(written[:], flavor~).html(safe=false)
    let first = document.html(safe=false)
    if again != first {
      failures.push(
        "example \{case.example}: \{show_visible(case.markdown)} -> \{show_visible(written)}",
      )
    }
  }
  println(
    "\{name} round trip: \{cases.length() - failures.length()}/\{cases.length()} passed",
  )
  let shown = if failures.length() > 5 { 5 } else { failures.length() }
  for i in 0..<shown {
    println(failures[i])
  }
  failures.length()
}

///|
test "CommonMark round trip" {
  let failed = check_round_trip(
    "commonmark",
    @spec.commonmark_cases(),
    @moonmd.commonmark,
  )
  assert_eq(
    failed,
    0,
    msg="examples whose Markdown does not read back the same",
  )
}

///|
test "GitHub Flavored Markdown round trip" {
  let cases : Array[@spec.Case] = []
  for case in @spec.gfm_cases() {
    if case.html.trim() != "<IGNORE>" {
      cases.push(case)
    }
  }
  let failed = check_round_trip("gfm", cases, @moonmd.gfm)
  assert_eq(
    failed,
    0,
    msg="extension examples whose Markdown does not read back",
  )
}
