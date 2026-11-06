// Resolving the delimiter stack into emphasis, strong emphasis and, when the
// flavor allows it, strikethrough. This is the part of the specification with
// the most rules per line of code, so it follows the reference wording closely.

///|
/// Pair up the delimiters from `stack_bottom` up, turning each pair into an
/// emphasis or strikethrough node. A closer that finds no opener stops future
/// searches from looking below it.
fn Subject::process_emphasis(self : Subject, stack_bottom : Int32) -> Unit {
  let openers_bottom = array_of(3 * 128, 0)
  for i in 0..<3 {
    openers_bottom[i * 128 + 0x2A] = stack_bottom
    openers_bottom[i * 128 + 0x5F] = stack_bottom
    openers_bottom[i * 128 + 0x27] = stack_bottom
    openers_bottom[i * 128 + 0x22] = stack_bottom
  }
  // Start at the first delimiter that is above the bottom of this stack.
  let mut closer = -1
  let mut candidate = self.last_delim
  while candidate >= 0 && self.delims[candidate].pos >= stack_bottom {
    closer = candidate
    candidate = self.delims[candidate].prev
  }
  while closer >= 0 {
    if self.delims[closer].can_close {
      let ch = self.delims[closer].ch
      let len = self.delims[closer].len
      let bottom = openers_bottom[len % 3 * 128 + ch]
      let mut opener = self.delims[closer].prev
      let mut opener_found = false
      while opener >= 0 &&
            self.delims[opener].pos >= stack_bottom &&
            self.delims[opener].pos >= bottom {
        if self.delims[opener].can_open && self.delims[opener].ch == ch {
          // A run of three can only pair with a run that is not a multiple of
          // three in total, unless both ends could also be openers or closers.
          if !(self.delims[closer].can_open || self.delims[opener].can_close) ||
            len % 3 == 0 ||
            (self.delims[opener].len + len) % 3 != 0 {
            opener_found = true
            break
          }
        }
        opener = self.delims[opener].prev
      }
      let old_closer = closer
      if opener_found {
        if ch == 0x7E {
          closer = self.insert_strike(opener, old_closer)
        } else {
          closer = self.insert_emph(opener, old_closer)
        }
      } else {
        closer = self.delims[old_closer].next
        openers_bottom[len % 3 * 128 + ch] = self.delims[old_closer].pos
        if !self.delims[old_closer].can_open {
          self.remove_delimiter(old_closer)
        }
      }
    } else {
      closer = self.delims[closer].next
    }
  }
  while self.last_delim >= 0 && self.delims[self.last_delim].pos >= stack_bottom {
    self.remove_delimiter(self.last_delim)
  }
}

///|
/// Turn a pair of `*` or `_` runs into emphasis or strong emphasis. Returns the
/// closer to carry on from, which moves when the closer run is used up.
fn Subject::insert_emph(
  self : Subject,
  opener : Int32,
  closer : Int32,
) -> Int32 {
  let opener_inl = self.delims[opener].inl
  let closer_inl = self.delims[closer].inl
  let opener_chars = self.tree.nodes[opener_inl].text_len
  let closer_chars = self.tree.nodes[closer_inl].text_len
  let used = if closer_chars >= 2 && opener_chars >= 2 { 2 } else { 1 }
  self.tree.nodes[opener_inl].text_len = opener_chars - used
  self.tree.nodes[closer_inl].text_len = closer_chars - used
  let mut delim = self.delims[closer].prev
  while delim >= 0 && delim != opener {
    let prev = self.delims[delim].prev
    self.remove_delimiter(delim)
    delim = prev
  }
  let emph = self.tree.make(
    if used == 1 {
      EmphNode
    } else {
      StrongNode
    },
    "",
    0,
    "",
  )
  let mut node = self.tree.nodes[opener_inl].next
  while node >= 0 && node != closer_inl {
    let next = self.tree.nodes[node].next
    self.tree.detach(node)
    self.tree.append_child(emph, node)
    node = next
  }
  self.tree.insert_after(opener_inl, emph)
  let mut result = closer
  if opener_chars - used == 0 {
    self.tree.detach(opener_inl)
    self.remove_delimiter(opener)
  }
  if closer_chars - used == 0 {
    self.tree.detach(closer_inl)
    let next = self.delims[closer].next
    self.remove_delimiter(closer)
    result = next
  }
  result
}

///|
/// Turn a pair of tilde runs into a strikethrough. The two runs have to be the
/// same width; otherwise the tildes stay as text.
fn Subject::insert_strike(
  self : Subject,
  opener : Int32,
  closer : Int32,
) -> Int32 {
  let result = self.delims[closer].next
  let opener_inl = self.delims[opener].inl
  let closer_inl = self.delims[closer].inl
  if self.delims[opener].len == self.delims[closer].len {
    self.tree.nodes[opener_inl].kind = StrikeNode
    self.tree.nodes[opener_inl].text = ""
    self.tree.nodes[opener_inl].text_len = 0
    let mut node = self.tree.nodes[opener_inl].next
    while node >= 0 && node != closer_inl {
      let next = self.tree.nodes[node].next
      self.tree.detach(node)
      self.tree.append_child(opener_inl, node)
      node = next
    }
    self.tree.detach(closer_inl)
  }
  let mut delim = closer
  while delim >= 0 && delim != opener {
    let prev = self.delims[delim].prev
    self.remove_delimiter(delim)
    delim = prev
  }
  self.remove_delimiter(opener)
  result
}
