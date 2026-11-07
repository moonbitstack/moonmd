// The inline phase's main loop and the handlers for the constructs that are
// not emphasis: line breaks, code spans, backslashes, entities, raw HTML,
// autolinks, brackets and links.

///|
/// Parse the text of a leaf block into inlines.
fn parse_inlines(
  text : String,
  refs : Map[String, Reference],
  flavor : Flavor,
) -> Array[Inline] {
  let input = rtrim_string(text)
  let subject = Subject::new(input, refs, flavor)
  while !subject.eof() {
    subject.parse_inline()
  }
  subject.process_emphasis(0)
  while subject.last_delim >= 0 {
    subject.remove_delimiter(subject.last_delim)
  }
  subject.last_bracket = -1
  consolidate_text(subject.tree, subject.root)
  if flavor.autolinks {
    subject.postprocess_emails(subject.root)
  }
  materialize_inlines(subject.tree, subject.root)
}

///|
/// Drop the whitespace at the end, which belongs to no inline.
fn rtrim_string(text : String) -> String {
  let mut n = text.length()
  while n > 0 {
    let c = cu(text[:], n - 1)
    if c == 0x20 ||
      c == 0x09 ||
      c == 0x0A ||
      c == 0x0D ||
      c == 0x0B ||
      c == 0x0C {
      n = n - 1
    } else {
      break
    }
  }
  text.clamped_view(start=0, end=n).to_owned()
}

///|
/// Drop the spaces and tabs at the end of a run of text.
fn rtrim_view(text : StringView) -> StringView {
  let mut n = text.length()
  while n > 0 {
    let c = cu(text, n - 1)
    if c == 0x20 || c == 0x09 {
      n = n - 1
    } else {
      break
    }
  }
  text.clamped_view(start=0, end=n)
}

///|
/// One step of the loop: look at the character at the cursor and handle it.
fn Subject::parse_inline(self : Subject) -> Unit {
  let c = self.peek(self.pos)
  match c {
    0x0A | 0x0D => self.handle_newline()
    0x60 => self.handle_backticks()
    0x5C => self.handle_backslash()
    0x26 => self.handle_entity()
    0x3C => self.handle_pointy_brace()
    0x2A | 0x5F => self.handle_delim(c)
    0x5B => {
      self.pos = self.pos + 1
      let node = self.add_text("[")
      self.push_bracket(false, node)
    }
    0x5D => self.handle_close_bracket()
    0x21 => {
      self.pos = self.pos + 1
      // A `!` followed by `[^` opens a footnote reference, not an image: the
      // exclamation mark is then ordinary text.
      if self.peek(self.pos) == 0x5B &&
        !(self.flavor.footnotes && self.peek(self.pos + 1) == 0x5E) {
        self.pos = self.pos + 1
        let node = self.add_text("![")
        self.push_bracket(true, node)
      } else {
        let _ = self.add_text("!")
      }
    }
    0x7E =>
      if self.flavor.strikethrough {
        self.handle_strike()
      } else {
        self.handle_plain()
      }
    0x3A =>
      if self.flavor.autolinks &&
        self.last_bracket < 0 &&
        self.try_url_autolink() {
        ()
      } else {
        self.handle_plain()
      }
    0x77 =>
      if self.flavor.autolinks &&
        self.last_bracket < 0 &&
        self.try_www_autolink() {
        ()
      } else {
        self.handle_plain()
      }
    _ => self.handle_plain()
  }
}

///|
/// A run of text up to the next character that could start something.
fn Subject::handle_plain(self : Subject) -> Unit {
  let start = self.pos
  let mut end = start + 1
  while end < self.input.length() && !self.is_special(self.peek(end)) {
    end = end + 1
  }
  self.pos = end
  let mut text = self.input.clamped_view(start~, end~)
  if is_line_end(self.peek(self.pos)) {
    text = rtrim_view(text)
  }
  let _ = self.add_text(text)
}

///|
/// A soft or hard line break.
fn Subject::handle_newline(self : Subject) -> Unit {
  let nlpos = self.pos
  if self.peek(self.pos) == 0x0D {
    self.pos = self.pos + 1
  }
  if self.peek(self.pos) == 0x0A {
    self.pos = self.pos + 1
  }
  self.skip_spaces()
  if nlpos > 1 && self.peek(nlpos - 1) == 0x20 && self.peek(nlpos - 2) == 0x20 {
    let _ = self.add_break(HardBreakNode)
  } else {
    let _ = self.add_break(SoftBreakNode)
  }
}

///|
/// A code span, or the backticks themselves when no run closes it.
fn Subject::handle_backticks(self : Subject) -> Unit {
  let start = self.pos
  while self.peek(self.pos) == 0x60 {
    self.pos = self.pos + 1
  }
  let run = self.pos - start
  let content_start = self.pos
  let end = self.scan_to_closing_backticks(run)
  if end == 0 {
    self.pos = content_start
    let _ = self.add_text(self.input.clamped_view(start~, end=content_start))
    return
  }
  let raw = self.input.clamped_view(start=content_start, end=end - run)
  let code = normalize_code(raw)
  let node = self.tree.make(CodeNode, code, code.length(), "")
  self.tree.append_child(self.root, node)
  self.pos = end
}

///|
/// The position after a closing backtick run of the same width, or zero.
fn Subject::scan_to_closing_backticks(self : Subject, run : Int32) -> Int32 {
  if run > 80 {
    return 0
  }
  if self.scanned_for_backticks && self.backticks[run] <= self.pos {
    return 0
  }
  while true {
    while !self.eof() && self.peek(self.pos) != 0x60 {
      self.pos = self.pos + 1
    }
    if self.eof() {
      break
    }
    let mut count = 0
    while self.peek(self.pos) == 0x60 {
      self.pos = self.pos + 1
      count = count + 1
    }
    if count <= 80 {
      self.backticks[count] = self.pos - count
    }
    if count == run {
      return self.pos
    }
  }
  self.scanned_for_backticks = true
  0
}

///|
/// A backslash escape, a hard break, or a lone backslash.
fn Subject::handle_backslash(self : Subject) -> Unit {
  self.pos = self.pos + 1
  if is_ascii_punct(self.peek(self.pos)) {
    let start = self.pos - 1
    self.pos = self.pos + 1
    let _ = self.add_text(
      self.input.clamped_view(start=start + 1, end=self.pos),
    )
  } else if !self.eof() && self.skip_line_end() {
    let _ = self.add_break(HardBreakNode)
  } else {
    let _ = self.add_text("\\")
  }
}

///|
/// A character reference, or a lone ampersand.
fn Subject::handle_entity(self : Subject) -> Unit {
  let (value, len) = entity_at(self.input[:], self.pos)
  if len == 0 {
    self.pos = self.pos + 1
    let _ = self.add_text("&")
  } else {
    self.pos = self.pos + len
    let _ = self.add_text(value[:])
  }
}

///|
/// An autolink or a raw HTML tag, or a lone `<`.
fn Subject::handle_pointy_brace(self : Subject) -> Unit {
  let n = self.input.length()
  self.pos = self.pos + 1
  let text = self.input[:]
  let after = self.pos
  let uri = scan_autolink_uri(text, after)
  if uri > 0 {
    let raw = text.clamped_view(start=after, end=after + uri - 1)
    self.pos = self.pos + uri
    self.make_autolink(raw, false)
    return
  }
  let email = scan_autolink_email(text, after)
  if email > 0 {
    let raw = text.clamped_view(start=after, end=after + email - 1)
    self.pos = self.pos + email
    self.make_autolink(raw, true)
    return
  }
  let mut raw_len = 0
  let c = cu(text, after)
  if c == 0x21 {
    if cu(text, after + 1) == 0x2D && cu(text, after + 2) == 0x2D {
      if cu(text, after + 3) == 0x3E {
        raw_len = 5
      } else if cu(text, after + 3) == 0x2D && cu(text, after + 4) == 0x3E {
        raw_len = 6
      } else {
        let len = scan_html_comment(text, after + 1)
        if len > 0 {
          raw_len = len + 2
        }
      }
    } else if cu(text, after + 1) == 0x5B {
      let len = scan_html_cdata(text, after + 2)
      if len > 0 {
        // The construct is `<![` plus what the scanner covers from `CDATA[`.
        raw_len = len + 3
      }
    } else {
      let len = scan_html_declaration(text, after + 1)
      if len > 0 {
        raw_len = len + 2
      }
    }
  } else if c == 0x3F {
    let len = scan_html_pi(text, after + 1)
    if len > 0 {
      raw_len = len + 2
    }
  } else {
    let len = scan_html_tag(text, after)
    if len > 0 {
      raw_len = len + 1
    }
  }
  if raw_len > 0 && after - 1 + raw_len <= n {
    let raw = text.clamped_view(start=after - 1, end=after - 1 + raw_len)
    let node = self.tree.make(HtmlNode, raw.to_owned(), raw.length(), "")
    self.tree.append_child(self.root, node)
    self.pos = after - 1 + raw_len
    return
  }
  let _ = self.add_text("<")
}

///|
/// A link made from an autolink, whose text is the destination as written.
fn Subject::make_autolink(
  self : Subject,
  raw : StringView,
  is_email : Bool,
) -> Unit {
  let destination = if is_email {
    "mailto:" + html_unescape(trim_view(raw))
  } else {
    html_unescape(trim_view(raw))
  }
  let link = self.tree.make(LinkNode, destination, destination.length(), "")
  self.tree.append_child(self.root, link)
  let text = self.tree.make(TextNode, raw.to_owned(), raw.length(), "")
  self.tree.append_child(link, text)
}

///|
/// A run of `*` or `_`, which may open or close emphasis.
fn Subject::handle_delim(self : Subject, c : Int32) -> Unit {
  let start = self.pos
  let (count, can_open, can_close) = self.scan_delims(c)
  let text = self.input.clamped_view(start~, end=self.pos)
  let node = self.add_text(text)
  if (can_open || can_close) && count > 0 {
    self.push_delimiter(c, can_open, can_close, node)
  }
}

///|
/// A run of tildes, which may open or close a strikethrough. Only runs of one
/// or two count.
fn Subject::handle_strike(self : Subject) -> Unit {
  let before = if self.pos == 0 {
    '\n'
  } else {
    flanking_before(self.input[:], self.pos, false)
  }
  let start = self.pos
  let mut count = 0
  while self.peek(self.pos) == 0x7E && count < 100 {
    count = count + 1
    self.pos = self.pos + 1
  }
  let after = if self.eof() {
    '\n'
  } else {
    flanking_after(self.input[:], self.pos, false)
  }
  let space_before = is_unicode_space(before)
  let space_after = is_unicode_space(after)
  let punct_before = is_unicode_punct(before)
  let punct_after = is_unicode_punct(after)
  let left = count > 0 &&
    !space_after &&
    !(punct_after && !space_before && !punct_before)
  let right = count > 0 &&
    !space_before &&
    !(punct_before && !space_after && !punct_after)
  let text = self.input.clamped_view(start~, end=self.pos)
  let node = self.add_text(text)
  if (left || right) && (count == 1 || count == 2) {
    self.push_delimiter(0x7E, left, right, node)
  }
}

///|
/// A link, an image, or a `]` that closes nothing.
fn Subject::handle_close_bracket(self : Subject) -> Unit {
  self.pos = self.pos + 1
  let initial_pos = self.pos
  let opener = self.last_bracket
  if opener < 0 {
    let _ = self.add_text("]")
    return
  }
  let is_image = self.brackets[opener].image
  if !is_image && self.no_link_openers {
    self.pop_bracket()
    let _ = self.add_text("]")
    return
  }
  let after_link_text = self.pos
  let mut matched = false
  let mut url = ""
  let mut title = ""
  let text = self.input[:]
  if self.peek(self.pos) == 0x28 {
    let spaces = scan_spacechars(text, self.pos + 1)
    let (raw_url, url_len) = scan_link_url(text, self.pos + 1 + spaces)
    if url_len >= 0 {
      let end_url = self.pos + 1 + spaces + url_len
      let start_title = end_url + scan_spacechars(text, end_url)
      let end_title = if start_title == end_url {
        start_title
      } else {
        start_title + scan_link_title(text, start_title)
      }
      let end_all = end_title + scan_spacechars(text, end_title)
      if self.peek(end_all) == 0x29 {
        self.pos = end_all + 1
        url = clean_url(raw_url[:])
        title = clean_title(text.clamped_view(start=start_title, end=end_title))
        matched = true
      } else {
        self.pos = after_link_text
      }
    } else {
      self.pos = after_link_text
    }
  }
  if !matched {
    let mut found_label = false
    let mut raw_label = ""
    let (label, label_len) = scan_link_label(text, self.pos)
    if label_len > 0 {
      raw_label = label
      found_label = true
      self.pos = self.pos + label_len
    }
    if !found_label {
      self.pos = initial_pos
    }
    if (!found_label || raw_label.is_empty()) &&
      !self.brackets[opener].bracket_after {
      raw_label = self.input
        .clamped_view(start=self.brackets[opener].pos, end=initial_pos - 1)
        .to_owned()
      found_label = true
    }
    if found_label {
      match self.refs.get(normalize_label(raw_label[:])) {
        Some(reference) => {
          url = reference.url
          title = reference.title
          matched = true
        }
        None => ()
      }
    }
  }
  if !matched &&
    self.flavor.footnotes &&
    !is_image &&
    self.peek(self.brackets[opener].body_start) == 0x5E {
    // `[^label]` is a footnote reference: it points at a definition by its
    // label, which is resolved to a number when the document is rendered. The
    // label is taken from the source between the caret and the close.
    self.pos = initial_pos
    let body_start = self.brackets[opener].body_start
    let label = self.input
      .clamped_view(start=body_start + 1, end=initial_pos - 1)
      .to_owned()
    if label.length() > 0 {
      let opener_inl = self.brackets[opener].inl
      let fnref = self.tree.make(FootnoteRefNode, label, label.length(), "")
      self.tree.insert_after(opener_inl, fnref)
      let mut node = self.tree.nodes[fnref].next
      while node >= 0 {
        let next = self.tree.nodes[node].next
        self.tree.detach(node)
        self.tree.append_child(fnref, node)
        node = next
      }
      self.tree.detach(opener_inl)
      self.process_emphasis(self.brackets[opener].pos)
      self.pop_bracket()
      return
    }
  }
  if !matched {
    self.pop_bracket()
    self.pos = initial_pos
    let _ = self.add_text("]")
    return
  }
  let opener_inl = self.brackets[opener].inl
  let link = self.tree.make(
    if is_image {
      ImageNode
    } else {
      LinkNode
    },
    url,
    url.length(),
    title,
  )
  self.tree.insert_after(opener_inl, link)
  let mut node = self.tree.nodes[link].next
  while node >= 0 {
    let next = self.tree.nodes[node].next
    self.tree.detach(node)
    self.tree.append_child(link, node)
    node = next
  }
  self.tree.detach(opener_inl)
  self.process_emphasis(self.brackets[opener].pos)
  self.pop_bracket()
  if !is_image {
    self.no_link_openers = true
  }
}
