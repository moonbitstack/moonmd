// The two scanners the link syntax shares between the block phase (reference
// definitions are stripped from paragraphs) and the inline phase (inline links,
// images, reference links).

///|
/// A link reference definition, kept by the label it can be looked up with.
priv struct Reference {
  url : String
  title : String
}

///|
/// Scan a link destination at `offset`: either `<...>`, or a run that stops at
/// whitespace, balancing parentheses. Returns the destination as written and
/// the number of code units consumed, or `-1` as the length when there is none.
fn scan_link_url(text : StringView, offset : Int32) -> (String, Int32) {
  let n = text.length()
  let mut i = offset
  if cu(text, i) == 0x3C {
    i = i + 1
    while i < n {
      let c = cu(text, i)
      if c == 0x3E {
        i = i + 1
        break
      } else if c == 0x5C {
        i = i + 2
      } else if c == 0x0A || c == 0x3C {
        return ("", -1)
      } else {
        i = i + 1
      }
    }
    if i >= n {
      return ("", -1)
    }
    return (
      text.clamped_view(start=offset + 1, end=i - 1).to_owned(),
      i - offset,
    )
  }
  let mut depth = 0
  while i < n {
    let c = cu(text, i)
    if c == 0x5C && is_ascii_punct(cu(text, i + 1)) && i + 1 < n {
      i = i + 2
    } else if c == 0x28 {
      depth = depth + 1
      i = i + 1
      if depth > 32 {
        return ("", -1)
      }
    } else if c == 0x29 {
      if depth == 0 {
        break
      }
      depth = depth - 1
      i = i + 1
    } else if c == 0x20 ||
      c == 0x09 ||
      c == 0x0A ||
      c == 0x0D ||
      c == 0x0B ||
      c == 0x0C {
      if i == offset {
        return ("", -1)
      }
      break
    } else {
      i = i + 1
    }
  }
  if i >= n {
    return ("", -1)
  }
  (text.clamped_view(start=offset, end=i).to_owned(), i - offset)
}

///|
/// Scan a link label at `pos`, which must be `[`. Returns the label between the
/// brackets and the length consumed, or `-1` when it is not closed in time.
fn scan_link_label(text : StringView, pos : Int32) -> (String, Int32) {
  if cu(text, pos) != 0x5B {
    return ("", -1)
  }
  let n = text.length()
  let mut i = pos + 1
  let mut length = 0
  while i < n {
    let c = cu(text, i)
    if c == 0x5B || c == 0x5D {
      break
    }
    if c == 0x5C {
      i = i + 1
      length = length + 1
      if is_ascii_punct(cu(text, i)) {
        i = i + 1
        length = length + 1
      }
    } else {
      i = i + 1
      length = length + 1
    }
    if length > 999 {
      return ("", -1)
    }
  }
  if cu(text, i) == 0x5D {
    return (
      trim_view(text.clamped_view(start=pos + 1, end=i)).to_owned(),
      i + 1 - pos,
    )
  }
  ("", -1)
}

///|
/// Parse one link reference definition at `pos` and add it to `refs`. Returns
/// the position after it, or `None` when there is no definition there.
fn parse_reference(
  text : StringView,
  pos : Int32,
  refs : Map[String, Reference],
) -> Int32? {
  let n = text.length()
  let (label, label_len) = scan_link_label(text, pos)
  if label_len < 0 || label.is_empty() {
    return None
  }
  let mut i = pos + label_len
  if cu(text, i) != 0x3A {
    return None
  }
  i = i + 1
  // `spnl`: spaces, at most one newline, then spaces again.
  while is_space_or_tab(cu(text, i)) {
    i = i + 1
  }
  if cu(text, i) == 0x0A {
    i = i + 1
    while is_space_or_tab(cu(text, i)) {
      i = i + 1
    }
  }
  let (url, url_len) = scan_link_url(text, i)
  if url_len < 0 {
    return None
  }
  i = i + url_len
  // An optional title, which only counts if a space introduced it.
  let before_title = i
  let mut j = i
  while is_space_or_tab(cu(text, j)) {
    j = j + 1
  }
  if cu(text, j) == 0x0A {
    j = j + 1
    while is_space_or_tab(cu(text, j)) {
      j = j + 1
    }
  }
  let title_len = if j == before_title { 0 } else { scan_link_title(text, j) }
  let mut title = ""
  let mut end = before_title
  if title_len > 0 {
    title = text.clamped_view(start=j, end=j + title_len).to_owned()
    end = j + title_len
  }
  // Nothing but spaces may follow, then the line has to end.
  let mut k = end
  while is_space_or_tab(cu(text, k)) {
    k = k + 1
  }
  let mut stop = k
  if !(cu(text, k) == 0x0A || cu(text, k) == 0x0D || k >= n) {
    if title_len > 0 {
      // The title may have run past the line; retry without it.
      let mut m = before_title
      while is_space_or_tab(cu(text, m)) {
        m = m + 1
      }
      if !(cu(text, m) == 0x0A || cu(text, m) == 0x0D || m >= n) {
        return None
      }
      title = ""
      stop = m
    } else {
      return None
    }
  }
  let key = normalize_label(label[:])
  if !key.is_empty() && !refs.contains(key) {
    refs[key] = { url: clean_url(url[:]), title: clean_title(title[:]), }
  }
  match cu(text, stop) {
    0x0A => Some(stop + 1)
    0x0D =>
      if cu(text, stop + 1) == 0x0A {
        Some(stop + 2)
      } else {
        Some(stop + 1)
      }
    _ => Some(stop)
  }
}
