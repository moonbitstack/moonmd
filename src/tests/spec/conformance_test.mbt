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
/// The extension corpus marks the examples that use footnotes, so a failure can
/// be reported by the kind of construct that broke, and the count of them is
/// checked on its own.
fn is_footnote_example(example : Int32) -> Bool {
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
  // Every example in the corpus, footnotes included, has to produce the HTML
  // the corpus expects.
  cases.append(footnotes[:])
  let failed = run_corpus("gfm", cases, @moonmd.gfm)
  assert_eq(failed, 0, msg="extension examples that differ")
  // Keep the footnote examples under their own name, so that if the corpus
  // gains more of them, or loses them, the count is the first thing to move.
  assert_eq(footnotes.length(), 3, msg="footnote examples in the corpus")
}
