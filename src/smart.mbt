// Typographic punctuation, the pass `Flavor::smart` turns on. It runs while the
// text is still the source, which is what makes it agree with the reference:
// an escaped quote is not a quote, an entity is not a quote, and the characters
// on either side of a run decide which way a quote curls.

///|
/// Whether a character at `i` could open and could close, by the flanking rules
/// the specification gives delimiters.
fn flanking_of(input : StringView, i : Int32) -> (Bool, Bool) {
  let before = char_before(input, i)
  let after = if i + 1 >= input.length() { '\n' } else { char_at(input, i + 1) }
  let space_before = is_unicode_space(before)
  let space_after = is_unicode_space(after)
  let punct_before = is_unicode_punct(before)
  let punct_after = is_unicode_punct(after)
  let left = !space_after && (!punct_after || space_before || punct_before)
  let right = !space_before && (!punct_before || space_after || punct_after)
  (left, right)
}

///|
/// Whether a single quote that could close sits anywhere later in the block.
/// A quote with none is the apostrophe of `'tis`, which stays a closing quote.
fn has_closing_quote(input : StringView, from : Int32) -> Bool {
  let n = input.length()
  let mut i = from
  while i < n {
    let c = input.get_char(i).unwrap()
    if c == '\'' {
      let (_, right) = flanking_of(input, i)
      if right {
        return true
      }
    }
    i = i + c.utf16_len()
  }
  false
}

///|
/// How a run of hyphens is written: the reference reads three as an em dash,
/// two as an en dash, and splits a longer run the way a proof would.
fn dash_counts(run : Int32) -> (Int32, Int32) {
  if run % 3 == 0 {
    (run / 3, 0)
  } else if run % 2 == 0 {
    (0, run / 2)
  } else if run % 3 == 2 {
    ((run - 2) / 3, 1)
  } else {
    ((run - 4) / 3, 2)
  }
}

///|
/// How many times `ch` occurs from `start` on, up to `end`.
fn run_length(
  input : StringView,
  start : Int32,
  end : Int32,
  ch : Char,
) -> Int32 {
  let mut i = start
  let mut count = 0
  while i < end && input.get_char(i) == Some(ch) {
    count = count + 1
    i = i + ch.utf16_len()
  }
  count
}

///|
/// Rewrite the characters of one run of plain text. `input` is the whole block,
/// so the characters on either side of the run still decide a quote's direction,
/// and a closing quote further on is still seen.
fn smarten_run(input : StringView, start : Int32, end : Int32) -> String {
  let out = StringBuilder()
  let mut i = start
  while i < end {
    let c = input.get_char(i).unwrap()
    let step = c.utf16_len()
    if c == '"' {
      let (_, right) = flanking_of(input, i)
      out.write_char(if right { '\u{201D}' } else { '\u{201C}' })
    } else if c == '\'' {
      let (left, _) = flanking_of(input, i)
      let opens = left && has_closing_quote(input, i + step)
      out.write_char(if opens { '\u{2018}' } else { '\u{2019}' })
    } else if c == '-' {
      let run = run_length(input, i, end, '-')
      if run == 1 {
        out.write_char('-')
      } else {
        let (em, en) = dash_counts(run)
        for _ in 0..<em {
          out.write_char('\u{2014}')
        }
        for _ in 0..<en {
          out.write_char('\u{2013}')
        }
      }
      i = i + run - step
    } else if c == '.' {
      let run = run_length(input, i, end, '.')
      let mut left = run
      while left >= 3 {
        out.write_char('\u{2026}')
        left = left - 3
      }
      for _ in 0..<left {
        out.write_char('.')
      }
      i = i + run - step
    } else {
      out.write_char(c)
    }
    i = i + step
  }
  out.to_string()
}
