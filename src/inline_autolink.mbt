// Links written bare: `http://example.com`, `www.example.com` and
// `someone@example.com`. The first two are recognised while scanning, the last
// one by a pass over the text nodes once emphasis has been settled, because an
// address is not introduced by any character of its own.

///|
/// Whether a character may appear in a host name.
fn is_valid_hostchar(c : Char) -> Bool {
  !is_unicode_space(c) && !is_unicode_punctuation_only(c)
}

///|
/// How much of the text from `start` is a host name, counting the segments and
/// refusing a host whose last two segments hold an underscore.
fn check_domain(
  text : StringView,
  start : Int32,
  size : Int32,
  allow_short : Bool,
) -> Int32 {
  let mut i = 1
  let mut segments = 0
  let mut underscore_before = 0
  let mut underscore_last = 0
  while i + 1 < size {
    if cu(text, start + i) == 0x5C && i + 2 < size {
      i = i + 1
    }
    let c = cu(text, start + i)
    if c == 0x5F {
      underscore_last = underscore_last + 1
    } else if c == 0x2E {
      underscore_before = underscore_last
      underscore_last = 0
      segments = segments + 1
    } else if !is_valid_hostchar(char_at(text, start + i)) && c != 0x2D {
      break
    }
    i = i + 1
  }
  if (underscore_before > 0 || underscore_last > 0) && segments <= 10 {
    return 0
  }
  if allow_short {
    i
  } else if segments > 0 {
    i
  } else {
    0
  }
}

///|
/// Cut the trailing punctuation a sentence leaves on a bare link, keeping the
/// parentheses balanced.
fn autolink_delim(text : StringView, start : Int32, limit : Int32) -> Int32 {
  let mut link_end = limit
  let mut opening = 0
  let mut closing = 0
  let mut i = 0
  while i < link_end {
    let c = cu(text, start + i)
    if c == 0x3C {
      link_end = i
      break
    } else if c == 0x28 {
      opening = opening + 1
    } else if c == 0x29 {
      closing = closing + 1
    }
    i = i + 1
  }
  while link_end > 0 {
    let c = cu(text, start + link_end - 1)
    if c == 0x29 {
      if closing <= opening {
        return link_end
      }
      closing = closing - 1
      link_end = link_end - 1
    } else if c == 0x3F ||
      c == 0x21 ||
      c == 0x2E ||
      c == 0x2C ||
      c == 0x3A ||
      c == 0x2A ||
      c == 0x5F ||
      c == 0x7E ||
      c == 0x27 ||
      c == 0x22 {
      link_end = link_end - 1
    } else if c == 0x3B {
      let mut candidate = link_end - 2
      while candidate > 0 && is_alpha(cu(text, start + candidate)) {
        candidate = candidate - 1
      }
      if candidate < link_end - 2 && cu(text, start + candidate) == 0x26 {
        link_end = candidate
      } else {
        link_end = link_end - 1
      }
    } else {
      return link_end
    }
  }
  link_end
}

///|
/// `http://`, `https://` or `ftp://` right before the `:` being looked at.
fn is_safe_scheme(text : StringView, from : Int32, to : Int32) -> Bool {
  let length = to - from
  for scheme in ["http://", "https://", "ftp://"] {
    let scheme_view : StringView = scheme[:]
    if length == scheme_view.length() &&
      text.clamped_view(start=from, end=to).equal_ignore_ascii_case(scheme_view) {
      return is_valid_hostchar(char_at(text, to))
    }
  }
  false
}

///|
/// Recognise `scheme://host` starting at the `:` under the cursor.
fn Subject::try_url_autolink(self : Subject) -> Bool {
  let n = self.input.length()
  if self.pos + 3 > n ||
    self.peek(self.pos + 1) != 0x2F ||
    self.peek(self.pos + 2) != 0x2F {
    return false
  }
  let text = self.input[:]
  let mut rewind = 0
  while rewind < self.pos && is_alpha(self.peek(self.pos - rewind - 1)) {
    rewind = rewind + 1
  }
  let start = self.pos - rewind
  if !is_safe_scheme(text, start, self.pos + 3) {
    return false
  }
  let domain = check_domain(text, self.pos + 3, n - (self.pos + 3), true)
  if domain == 0 {
    return false
  }
  let mut link_end = 3 + domain
  while self.pos + link_end < n &&
        !is_unicode_space(char_at(text, self.pos + link_end)) &&
        cu(text, self.pos + link_end) != 0x3C {
    link_end = link_end + 1
  }
  link_end = autolink_delim(text, self.pos, link_end)
  if link_end == 0 {
    return false
  }
  let destination = text
    .clamped_view(start~, end=self.pos + link_end)
    .to_owned()
  self.unput(rewind)
  let link = self.tree.make(LinkNode, destination, destination.length(), "")
  self.tree.append_child(self.root, link)
  let label = self.tree.make(TextNode, destination, destination.length(), "")
  self.tree.append_child(link, label)
  self.pos = self.pos + link_end
  true
}

///|
/// Recognise `www.host` starting at the `w` under the cursor.
fn Subject::try_www_autolink(self : Subject) -> Bool {
  let n = self.input.length()
  if self.pos > 0 {
    let before = char_before(self.input[:], self.pos)
    if !"*_~("[:].contains_char(before) && !is_unicode_space(before) {
      return false
    }
  }
  if n - self.pos < 4 {
    return false
  }
  let text = self.input[:]
  if !text
    .clamped_view(start=self.pos, end=self.pos + 4)
    .equal_ignore_ascii_case("www."[:]) {
    return false
  }
  let domain = check_domain(text, self.pos, n - self.pos, false)
  if domain == 0 {
    return false
  }
  let mut link_end = domain
  while self.pos + link_end < n &&
        !is_unicode_space(char_at(text, self.pos + link_end)) &&
        cu(text, self.pos + link_end) != 0x3C {
    link_end = link_end + 1
  }
  link_end = autolink_delim(text, self.pos, link_end)
  if link_end == 0 {
    return false
  }
  let written = text
    .clamped_view(start=self.pos, end=self.pos + link_end)
    .to_owned()
  let destination = "http://" + written
  let link = self.tree.make(LinkNode, destination, destination.length(), "")
  self.tree.append_child(self.root, link)
  let label = self.tree.make(TextNode, written, written.length(), "")
  self.tree.append_child(link, label)
  self.pos = self.pos + link_end
  true
}

///|
/// Take `count` characters back out of the text already written, which is what
/// a scheme recognised late needs.
fn Subject::unput(self : Subject, count : Int32) -> Unit {
  let mut remaining = count
  while remaining > 0 {
    let last = self.tree.nodes[self.root].last_child
    if last < 0 || self.tree.nodes[last].kind != TextNode {
      return
    }
    let length = self.tree.nodes[last].text_len
    if length <= remaining {
      remaining = remaining - length
      self.tree.detach(last)
    } else {
      self.tree.nodes[last].text_len = length - remaining
      remaining = 0
    }
  }
}

///|
/// Merge the runs of text that ended up next to each other, so that the email
/// pass and the reader both see whole words.
fn consolidate_text(tree : InlineTree, parent : Int32) -> Unit {
  let mut node = tree.nodes[parent].first_child
  while node >= 0 {
    let next = tree.nodes[node].next
    if tree.nodes[node].kind == TextNode {
      if tree.nodes[node].text_len == 0 {
        tree.detach(node)
      } else {
        let mut sibling = tree.nodes[node].next
        while sibling >= 0 && tree.nodes[sibling].kind == TextNode {
          let following = tree.nodes[sibling].next
          let merged = tree.literal(node).to_owned() +
            tree.literal(sibling).to_owned()
          tree.nodes[node].text = merged
          tree.nodes[node].text_len = merged.length()
          tree.detach(sibling)
          sibling = following
        }
      }
    } else {
      consolidate_text(tree, node)
    }
    node = next
  }
}

///|
/// Where an address starts: alphanumerics and the few punctuation marks an
/// address may hold, or the `mailto:` and `xmpp:` protocols in front of them.
fn email_local_char(c : Int32) -> Bool {
  is_alnum(c) || c == 0x2E || c == 0x2B || c == 0x2D || c == 0x5F
}

///|
/// Find the addresses in a text node and turn them into links.
fn Subject::postprocess_emails(self : Subject, parent : Int32) -> Unit {
  let mut node = self.tree.nodes[parent].first_child
  while node >= 0 {
    let next = self.tree.nodes[node].next
    let kind = self.tree.nodes[node].kind
    if kind == LinkNode {
      ()
    } else if kind == TextNode {
      self.split_emails(node)
    } else if kind == ImageNode ||
      kind == CodeNode ||
      kind == HtmlNode ||
      kind == SoftBreakNode ||
      kind == HardBreakNode {
      ()
    } else {
      self.postprocess_emails(node)
    }
    node = next
  }
}

///|
/// One address found in a text node.
priv struct EmailMatch {
  start : Int32
  end : Int32
  auto_mailto : Bool
}

///|
/// Scan the text for addresses and replace them with links, keeping the text
/// around them.
fn Subject::split_emails(self : Subject, node : Int32) -> Unit {
  let text = self.tree.literal(node).to_owned()
  let n = text.length()
  let matches : Array[EmailMatch] = []
  let mut offset = 0
  while offset < n {
    // The next `@`.
    let mut at = offset
    while at < n && cu(text[:], at) != 0x40 {
      at = at + 1
    }
    if at >= n {
      break
    }
    // The local part, and any protocol in front of it.
    let mut start = at
    while start > 0 && email_local_char(cu(text[:], start - 1)) {
      start = start - 1
    }
    let mut auto_mailto = true
    let mut is_xmpp = false
    let rest = text.clamped_view(start=0, end=start)
    if rest.has_suffix("mailto:"[:]) && protocol_boundary(rest, 7) {
      auto_mailto = false
      start = start - 7
    } else if rest.has_suffix("xmpp:"[:]) && protocol_boundary(rest, 5) {
      auto_mailto = false
      is_xmpp = true
      start = start - 5
    }
    if start == at {
      offset = at + 1
      continue
    }
    // The domain.
    let mut link_end = 1
    let mut segments = 0
    let mut retry = false
    while at + link_end < n {
      let c = cu(text[:], at + link_end)
      if is_alnum(c) {
        link_end = link_end + 1
      } else if c == 0x40 {
        offset = at + 1
        at = at + 1
        retry = true
        break
      } else if c == 0x2E &&
        at + link_end + 1 < n &&
        is_alnum(cu(text[:], at + link_end + 1)) {
        segments = segments + 1
        link_end = link_end + 1
      } else if c == 0x2F && is_xmpp {
        link_end = link_end + 1
      } else if c == 0x2D || c == 0x5F {
        link_end = link_end + 1
      } else {
        break
      }
    }
    if retry {
      continue
    }
    let last = cu(text[:], at + link_end - 1)
    if link_end < 2 || segments == 0 || !(is_alpha(last) || last == 0x2E) {
      offset = at + link_end
      continue
    }
    let end = autolink_delim(text[:], at, link_end)
    if end == 0 {
      offset = at + 1
      continue
    }
    matches.push({ start, end: at + end, auto_mailto, })
    offset = at + end
  }
  if matches.length() == 0 {
    return
  }
  let parent = self.tree.nodes[node].parent
  let _ = parent
  let mut cursor = 0
  let mut anchor = node
  for match_ in matches {
    if match_.start > cursor {
      let piece_text = text
        .clamped_view(start=cursor, end=match_.start)
        .to_owned()
      let piece = self.tree.make(TextNode, piece_text, piece_text.length(), "")
      self.tree.insert_after(anchor, piece)
      anchor = piece
    }
    let written = text
      .clamped_view(start=match_.start, end=match_.end)
      .to_owned()
    let destination = if match_.auto_mailto {
      "mailto:" + written
    } else {
      written
    }
    let link = self.tree.make(LinkNode, destination, destination.length(), "")
    self.tree.insert_after(anchor, link)
    let label = self.tree.make(TextNode, written, written.length(), "")
    self.tree.append_child(link, label)
    anchor = link
    cursor = match_.end
  }
  if cursor < n {
    let piece = self.tree.make(
      TextNode,
      text.clamped_view(start=cursor, end=n).to_owned(),
      n - cursor,
      "",
    )
    self.tree.insert_after(anchor, piece)
  }
  self.tree.detach(node)
}

///|
/// Whether a protocol is a word of its own, not the tail of a longer one.
fn protocol_boundary(text : StringView, length : Int32) -> Bool {
  let before = text.length() - length
  before == 0 || !is_alnum(cu(text, before - 1))
}
