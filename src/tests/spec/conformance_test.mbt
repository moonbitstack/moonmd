// The two conformance corpora, replayed example by example.

///|
/// Show a string with its line endings visible, for a failure report.
fn visible(text : String) -> String {
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
/// Run one corpus, printing the examples whose HTML differs, and return how
/// many failed.
fn run_corpus(
  name : String,
  cases : Array[@spec.Case],
  flavor : @moonmd.Flavor,
) -> Int32 {
  let failures : Array[@spec.Case] = []
  let actual : Array[String] = []
  for case in cases {
    let got = @moonmd.parse(case.markdown[:], flavor~).html(safe=false)
    if got != case.html {
      failures.push(case)
      actual.push(got)
    }
  }
  let passed = cases.length() - failures.length()
  println("\{name}: \{passed}/\{cases.length()} passed")
  let shown = if failures.length() > 3 { 3 } else { failures.length() }
  for i in 0..<shown {
    println("--- example \{failures[i].example} (\{failures[i].section})")
    println("markdown: \{visible(failures[i].markdown)}")
    println("expected: \{visible(failures[i].html)}")
    println("actual:   \{visible(actual[i])}")
  }
  failures.length()
}

///|
test "CommonMark 0.31.2 specification" {
  let failed = run_corpus(
    "commonmark",
    @spec.commonmark_cases(),
    @moonmd.commonmark,
  )
  assert_eq(failed, 0, msg="CommonMark examples that differ")
}

///|
/// The extension corpus has three examples that use footnotes. Footnotes are
/// not part of the tree this library hands out, so they are not expected to
/// pass; README.md lists them in its conformance section.
fn is_footnote_example(example : Int) -> Bool {
  example == 23 || example == 24 || example == 25
}

///|
test "GitHub Flavored Markdown extensions" {
  let cases : Array[@spec.Case] = []
  let footnotes : Array[@spec.Case] = []
  for case in @spec.gfm_cases() {
    // The corpus marks the examples that only have to survive: no expected HTML.
    if case.html.trim() == "<IGNORE>" {
      continue
    }
    if is_footnote_example(case.example) {
      footnotes.push(case)
    } else {
      cases.push(case)
    }
  }
  let failed = run_corpus("gfm", cases, @moonmd.gfm)
  assert_eq(failed, 0, msg="extension examples that differ")
  // The three excluded examples have to differ, or the note in README.md is
  // wrong and this list is out of date.
  let mut differing = 0
  for case in footnotes {
    let got = @moonmd.parse(case.markdown[:], flavor=@moonmd.gfm).html(safe=false)
    if got != case.html {
      differing = differing + 1
    }
  }
  assert_eq(differing, footnotes.length(), msg="footnote examples that now pass")
  assert_eq(footnotes.length(), 3, msg="footnote examples in the corpus")
}
