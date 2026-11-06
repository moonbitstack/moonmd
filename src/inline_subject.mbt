// The inline phase. One subject (the text of a leaf block) is scanned from left
// to right; the nodes produced are kept in a flat array linked both ways, so
// that emphasis and links can splice the list the way the specification's
// delimiter stack requires.

///|
#derive(Eq)
priv enum InlineKind {
  TextNode
  CodeNode
  HtmlNode
  EmphNode
  StrongNode
  StrikeNode
  LinkNode
  ImageNode
  SoftBreakNode
  HardBreakNode
}

///|
priv struct InlineNode {
  mut kind : InlineKind
  mut parent : Int32
  mut first_child : Int32
  mut last_child : Int32
  mut next : Int32
  mut prev : Int32
  mut text : String
  /// How much of `text` is still in use: a delimiter run shrinks as it pairs up.
  mut text_len : Int32
  title : String
}

///|
priv struct InlineTree {
  nodes : Array[InlineNode]
}

///|
fn InlineTree::new() -> InlineTree {
  let tree : InlineTree = { nodes: [], }
  tree.nodes.push(InlineNode::{
    kind: TextNode,
    parent: -1,
    first_child: -1,
    last_child: -1,
    next: -1,
    prev: -1,
    text: "",
    text_len: 0,
    title: "",
  })
  tree
}

///|
fn InlineTree::make(
  self : InlineTree,
  kind : InlineKind,
  text : String,
  text_len : Int32,
  title : String,
) -> Int32 {
  self.nodes.push(InlineNode::{
    kind,
    parent: -1,
    first_child: -1,
    last_child: -1,
    next: -1,
    prev: -1,
    text,
    text_len,
    title,
  })
  self.nodes.length() - 1
}

///|
fn InlineTree::append_child(
  self : InlineTree,
  parent : Int32,
  child : Int32,
) -> Unit {
  let last = self.nodes[parent].last_child
  self.nodes[child].parent = parent
  self.nodes[child].prev = last
  self.nodes[child].next = -1
  if last >= 0 {
    self.nodes[last].next = child
  } else {
    self.nodes[parent].first_child = child
  }
  self.nodes[parent].last_child = child
}

///|
fn InlineTree::insert_after(
  self : InlineTree,
  index : Int32,
  node : Int32,
) -> Unit {
  let parent = self.nodes[index].parent
  let next = self.nodes[index].next
  self.nodes[node].parent = parent
  self.nodes[node].prev = index
  self.nodes[node].next = next
  self.nodes[index].next = node
  if next >= 0 {
    self.nodes[next].prev = node
  } else {
    self.nodes[parent].last_child = node
  }
}

///|
/// The text a node still shows, without the part a delimiter run has used up.
fn InlineTree::literal(self : InlineTree, index : Int32) -> StringView {
  let node = self.nodes[index]
  if node.text_len >= node.text.length() {
    node.text[:]
  } else {
    node.text[:].clamped_view(start=0, end=node.text_len)
  }
}

///|
/// Remove a node, giving its children to the parent of `keep_children_of` when
/// asked, or simply dropping it.
fn InlineTree::detach(self : InlineTree, index : Int32) -> Unit {
  let parent = self.nodes[index].parent
  if parent < 0 {
    return
  }
  let prev = self.nodes[index].prev
  let next = self.nodes[index].next
  if prev >= 0 {
    self.nodes[prev].next = next
  } else {
    self.nodes[parent].first_child = next
  }
  if next >= 0 {
    self.nodes[next].prev = prev
  } else {
    self.nodes[parent].last_child = prev
  }
  self.nodes[index].parent = -1
  self.nodes[index].prev = -1
  self.nodes[index].next = -1
}

///|
priv struct Delimiter {
  ch : Int32
  can_open : Bool
  can_close : Bool
  inl : Int32
  pos : Int32
  len : Int32
  mut prev : Int32
  mut next : Int32
}

///|
priv struct Bracket {
  image : Bool
  inl : Int32
  prev : Int32
  pos : Int32
  mut bracket_after : Bool
}

///|
/// One leaf block being parsed into inlines.
priv struct Subject {
  input : String
  tree : InlineTree
  refs : Map[String, Reference]
  flavor : Flavor
  mut pos : Int32
  root : Int32
  mut last_delim : Int32
  mut last_bracket : Int32
  mut no_link_openers : Bool
  delims : Array[Delimiter]
  brackets : Array[Bracket]
  backticks : Array[Int32]
  mut scanned_for_backticks : Bool
}

///|
fn Subject::new(
  input : String,
  refs : Map[String, Reference],
  flavor : Flavor,
) -> Subject {
  let tree = InlineTree::new()
  {
    input,
    tree,
    refs,
    flavor,
    pos: 0,
    root: 0,
    last_delim: -1,
    last_bracket: -1,
    no_link_openers: false,
    delims: [],
    brackets: [],
    backticks: array_of(81, 0),
    scanned_for_backticks: false,
  }
}

///|
fn Subject::peek(self : Subject, i : Int32) -> Int32 {
  cu(self.input[:], i)
}

///|
fn Subject::eof(self : Subject) -> Bool {
  self.pos >= self.input.length()
}

///|
fn Subject::skip_spaces(self : Subject) -> Unit {
  while true {
    let c = self.peek(self.pos)
    if c == 0x20 || c == 0x09 {
      self.pos = self.pos + 1
    } else {
      break
    }
  }
}

///|
/// Skip a `\r\n`, `\r` or `\n`; true when one was there or the input ended.
fn Subject::skip_line_end(self : Subject) -> Bool {
  let mut seen = false
  if self.peek(self.pos) == 0x0D {
    self.pos = self.pos + 1
    seen = true
  }
  if self.peek(self.pos) == 0x0A {
    self.pos = self.pos + 1
    seen = true
  }
  seen || self.eof()
}

///|
fn Subject::add_text(self : Subject, text : StringView) -> Int32 {
  let node = self.tree.make(TextNode, text.to_owned(), text.length(), "")
  self.tree.append_child(self.root, node)
  node
}

///|
fn Subject::add_break(self : Subject, kind : InlineKind) -> Int32 {
  let node = self.tree.make(kind, "", 0, "")
  self.tree.append_child(self.root, node)
  node
}

///|
/// Whether a character would start an inline construct, so that a run of plain
/// text can stop before it.
fn Subject::is_special(self : Subject, c : Int32) -> Bool {
  if c == 0x0A ||
    c == 0x0D ||
    c == 0x5C ||
    c == 0x60 ||
    c == 0x26 ||
    c == 0x5F ||
    c == 0x2A ||
    c == 0x5B ||
    c == 0x5D ||
    c == 0x3C ||
    c == 0x21 {
    return true
  }
  if self.flavor.autolinks && (c == 0x3A || c == 0x77) {
    return true
  }
  if self.flavor.strikethrough && c == 0x7E {
    return true
  }
  false
}

///|
/// Push a delimiter run onto the stack.
fn Subject::push_delimiter(
  self : Subject,
  ch : Int32,
  can_open : Bool,
  can_close : Bool,
  inl : Int32,
) -> Unit {
  let index = self.delims.length()
  self.delims.push(Delimiter::{
    ch,
    can_open,
    can_close,
    inl,
    pos: self.pos,
    len: self.tree.nodes[inl].text_len,
    prev: self.last_delim,
    next: -1,
  })
  if self.last_delim >= 0 {
    self.delims[self.last_delim].next = index
  }
  self.last_delim = index
}

///|
fn Subject::remove_delimiter(self : Subject, index : Int32) -> Unit {
  if index < 0 {
    return
  }
  let prev = self.delims[index].prev
  let next = self.delims[index].next
  if next >= 0 {
    self.delims[next].prev = prev
  } else {
    self.last_delim = prev
  }
  if prev >= 0 {
    self.delims[prev].next = next
  }
  self.delims[index].prev = -1
  self.delims[index].next = -1
}

///|
fn Subject::push_bracket(self : Subject, image : Bool, inl : Int32) -> Unit {
  if self.last_bracket >= 0 {
    self.brackets[self.last_bracket].bracket_after = true
  }
  self.brackets.push(Bracket::{
    image,
    inl,
    prev: self.last_bracket,
    pos: self.pos,
    bracket_after: false,
  })
  self.last_bracket = self.brackets.length() - 1
  if !image {
    self.no_link_openers = false
  }
}

///|
fn Subject::pop_bracket(self : Subject) -> Unit {
  if self.last_bracket < 0 {
    return
  }
  self.last_bracket = self.brackets[self.last_bracket].prev
}

///|
/// Whether the delimiter character is one this position may open or close,
/// computed from the characters on either side of the run.
fn Subject::scan_delims(self : Subject, c : Int32) -> (Int32, Bool, Bool) {
  let before = if self.pos == 0 {
    '\n'
  } else {
    flanking_before(self.input[:], self.pos, self.flavor.strikethrough)
  }
  let mut count = 0
  while self.peek(self.pos) == c {
    count = count + 1
    self.pos = self.pos + 1
  }
  let after = if self.eof() {
    '\n'
  } else {
    flanking_after(self.input[:], self.pos, self.flavor.strikethrough)
  }
  let space_before = is_unicode_space(before)
  let space_after = is_unicode_space(after)
  let punct_before = is_unicode_punct(before)
  let punct_after = is_unicode_punct(after)
  let left = count > 0 &&
    !space_after &&
    (!punct_after || space_before || punct_before)
  let right = count > 0 &&
    !space_before &&
    (!punct_before || space_after || punct_after)
  let can_open = if c == 0x5F { left && (!right || punct_before) } else { left }
  let can_close = if c == 0x5F {
    right && (!left || punct_after)
  } else {
    right
  }
  (count, can_open, can_close)
}

///|
/// The character before `pos`, skipping the runs of special characters that do
/// not count when flanking is decided.
fn flanking_before(text : StringView, pos : Int32, skip_tilde : Bool) -> Char {
  let mut i = pos
  if skip_tilde {
    while i > 0 && cu(text, i - 1) == 0x7E {
      i = i - 1
    }
  }
  char_before(text, i)
}

///|
/// The character at `pos`, skipping the same runs.
fn flanking_after(text : StringView, pos : Int32, skip_tilde : Bool) -> Char {
  let mut i = pos
  if skip_tilde {
    while cu(text, i) == 0x7E {
      i = i + 1
    }
  }
  char_at(text, i)
}

///|
/// `array_of` without pulling in a package for it.
fn array_of(size : Int32, value : Int32) -> Array[Int32] {
  let out : Array[Int32] = []
  for _ in 0..<size {
    out.push(value)
  }
  out
}
