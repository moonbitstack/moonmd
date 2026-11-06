// The block phase: one line at a time, match the prefixes of the containers
// still open, open the containers this line starts, then hand what is left to
// the innermost one. The structure follows the two phase design the
// specification describes, with tabs measured in columns of four.

///|
/// The most list nesting the parser follows, so that a hostile document cannot
/// exhaust the stack.
const MAX_LIST_DEPTH : Int32 = 100

///|
/// The indentation that starts an indented code block.
const CODE_INDENT : Int32 = 4

///|
/// A marker found at the start of a line: what kind of list it belongs to, and
/// how wide the marker is.
priv struct Marker {
  shape : ListShape
  matched : Int32
}

///|
priv struct BlockParser {
  tree : Tree
  root : Int32
  mut current : Int32
  refs : Map[String, Reference]
  flavor : Flavor
  mut line : String
  mut line_end : Int32
  mut offset : Int32
  mut column : Int32
  mut first_nonspace : Int32
  mut first_nonspace_column : Int32
  mut indent : Int32
  mut blank : Bool
  mut partial_tab : Bool
  mut line_number : Int32
}

///|
fn BlockParser::new(
  flavor : Flavor,
  refs : Map[String, Reference],
) -> BlockParser {
  let tree = Tree::new()
  {
    tree,
    root: 0,
    current: 0,
    refs,
    flavor,
    line: "",
    line_end: 0,
    offset: 0,
    column: 0,
    first_nonspace: 0,
    first_nonspace_column: 0,
    indent: 0,
    blank: false,
    partial_tab: false,
    line_number: 0,
  }
}

///|
/// The code unit at `i` of the line being parsed, or zero past its end.
fn BlockParser::peek(self : BlockParser, i : Int32) -> Int32 {
  cu(self.line[:], i)
}

///|
/// Find the first character that is not a space or a tab from the current
/// offset, and with it the indentation of the line.
fn BlockParser::find_first_nonspace(self : BlockParser) -> Unit {
  let mut chars_to_tab = 4 - self.column % 4
  if self.first_nonspace <= self.offset {
    self.first_nonspace = self.offset
    self.first_nonspace_column = self.column
    while true {
      let c = self.peek(self.first_nonspace)
      if c == 0x20 {
        self.first_nonspace = self.first_nonspace + 1
        self.first_nonspace_column = self.first_nonspace_column + 1
        chars_to_tab = chars_to_tab - 1
        if chars_to_tab == 0 {
          chars_to_tab = 4
        }
      } else if c == 0x09 {
        self.first_nonspace = self.first_nonspace + 1
        self.first_nonspace_column = self.first_nonspace_column + chars_to_tab
        chars_to_tab = 4
      } else {
        break
      }
    }
  }
  self.indent = self.first_nonspace_column - self.column
  let c = self.peek(self.first_nonspace)
  self.blank = c == 0x0A || c == 0x0D || c == 0
}

///|
/// Move the offset forward by `count` code units, or by `count` columns when
/// `columns` is set, in which case a tab may be taken in part.
fn BlockParser::advance_offset(
  self : BlockParser,
  count : Int32,
  columns : Bool,
) -> Unit {
  let mut remaining = count
  while remaining > 0 {
    let c = self.peek(self.offset)
    if c == 0 {
      break
    }
    if c == 0x09 {
      let chars_to_tab = 4 - self.column % 4
      if columns {
        self.partial_tab = chars_to_tab > remaining
        let step = if remaining < chars_to_tab {
          remaining
        } else {
          chars_to_tab
        }
        self.column = self.column + step
        if !self.partial_tab {
          self.offset = self.offset + 1
        }
        remaining = remaining - step
      } else {
        self.partial_tab = false
        self.column = self.column + chars_to_tab
        self.offset = self.offset + 1
        remaining = remaining - 1
      }
    } else {
      self.partial_tab = false
      self.offset = self.offset + 1
      self.column = self.column + 1
      remaining = remaining - 1
    }
  }
}

///|
/// Append what is left of the line to a block's content.
fn BlockParser::add_line(self : BlockParser, index : Int32) -> Unit {
  if self.partial_tab {
    self.offset = self.offset + 1
    let chars_to_tab = 4 - self.column % 4
    for _ in 0..<chars_to_tab {
      self.tree.nodes[index].content.write_char(' ')
    }
  }
  let rest = self.line[:].clamped_view(start=self.offset, end=self.line_end)
  self.tree.nodes[index].content.write_view(rest)
}

///|
fn BlockParser::parse_block_quote_prefix(self : BlockParser) -> Bool {
  if self.indent <= 3 && self.peek(self.first_nonspace) == 0x3E {
    self.advance_offset(self.indent + 1, true)
    if is_space_or_tab(self.peek(self.offset)) {
      self.advance_offset(1, true)
    }
    return true
  }
  false
}

///|
fn BlockParser::parse_item_prefix(self : BlockParser, index : Int32) -> Bool {
  let node = self.tree.nodes[index]
  if self.indent >= node.marker_offset + node.padding {
    self.advance_offset(node.marker_offset + node.padding, true)
    return true
  }
  if self.blank && node.first_child >= 0 {
    self.advance_offset(self.first_nonspace - self.offset, false)
    return true
  }
  false
}

///|
/// Match the prefix of a code block. The second value says whether the line
/// should still be processed: a closing fence ends it.
fn BlockParser::parse_code_block_prefix(
  self : BlockParser,
  index : Int32,
) -> (Bool, Bool) {
  let node = self.tree.nodes[index]
  if !node.fenced {
    if self.indent >= CODE_INDENT {
      self.advance_offset(CODE_INDENT, true)
      return (true, true)
    }
    if self.blank {
      self.advance_offset(self.first_nonspace - self.offset, false)
      return (true, true)
    }
    return (false, true)
  }
  let mut matched = 0
  if self.indent <= 3 && self.peek(self.first_nonspace) == node.fence_char {
    matched = scan_close_code_fence(self.line[:], self.first_nonspace)
  }
  if matched >= node.fence_length {
    self.advance_offset(matched, false)
    self.current = self.finalize(index)
    return (false, false)
  }
  let mut i = node.fence_offset
  while i > 0 && is_space_or_tab(self.peek(self.offset)) {
    self.advance_offset(1, true)
    i = i - 1
  }
  (true, true)
}

///|
fn BlockParser::parse_html_block_prefix(
  self : BlockParser,
  index : Int32,
) -> Bool {
  match self.tree.nodes[index].html_type {
    1 | 2 | 3 | 4 | 5 => true
    _ => !self.blank
  }
}

///|
/// Walk down the containers still open and match this line against each. The
/// result is the deepest container the line belongs to, and whether every
/// prefix matched (a lazy continuation line is one that did not).
fn BlockParser::check_open_blocks(self : BlockParser) -> (Int32, Bool) {
  let mut container = self.root
  let mut all_matched = true
  let mut should_continue = true
  let mut stopped = false
  while !stopped && self.tree.last_child_is_open(container) {
    container = self.tree.nodes[container].last_child
    self.find_first_nonspace()
    match self.tree.nodes[container].kind {
      Quote => if !self.parse_block_quote_prefix() { stopped = true }
      Item => if !self.parse_item_prefix(container) { stopped = true }
      Code => {
        let (matched, cont) = self.parse_code_block_prefix(container)
        should_continue = cont
        if !matched {
          stopped = true
        }
      }
      Heading => stopped = true
      Html => if !self.parse_html_block_prefix(container) { stopped = true }
      Paragraph => if self.blank { stopped = true }
      Table => if self.blank { stopped = true }
      _ => ()
    }
  }
  if stopped {
    all_matched = false
    container = self.tree.nodes[container].parent
    if container < 0 {
      container = self.root
    }
  }
  if !should_continue {
    return (-1, all_matched)
  }
  (container, all_matched)
}

///|
/// A bullet, `+`, `-` or `*`, or an ordered marker, at `pos`. `interrupts` says
/// a paragraph is open, which forbids markers that would leave it empty.
fn parse_list_marker(
  text : StringView,
  pos : Int32,
  interrupts : Bool,
) -> Marker? {
  let c = cu(text, pos)
  if c == 0x2A || c == 0x2D || c == 0x2B {
    if !is_ascii_space(cu(text, pos + 1)) {
      return None
    }
    if interrupts {
      let mut i = pos + 1
      while is_space_or_tab(cu(text, i)) {
        i = i + 1
      }
      if is_line_end(cu(text, i)) {
        return None
      }
    }
    return Some(Marker::{ shape: Bullet(Int32::unsafe_to_char(c)), matched: 1, })
  }
  if !is_digit(c) {
    return None
  }
  let mut i = pos
  let mut start = 0
  let mut digits = 0
  while digits < 9 && is_digit(cu(text, i)) {
    start = start * 10 + (cu(text, i) - 0x30)
    i = i + 1
    digits = digits + 1
  }
  if interrupts && start != 1 {
    return None
  }
  let delimiter = cu(text, i)
  if delimiter != 0x2E && delimiter != 0x29 {
    return None
  }
  if !is_ascii_space(cu(text, i + 1)) {
    return None
  }
  if interrupts {
    let mut j = i + 1
    while is_space_or_tab(cu(text, j)) {
      j = j + 1
    }
    if is_line_end(cu(text, j)) {
      return None
    }
  }
  Some(Marker::{
    shape: Ordered(start, Int32::unsafe_to_char(delimiter)),
    matched: i + 1 - pos,
  })
}

///|
/// Whether an item would continue the list it is being added to.
fn lists_match(list : ListShape, item : ListShape) -> Bool {
  match (list, item) {
    (Bullet(a), Bullet(b)) => a == b
    (Ordered(_, d1), Ordered(_, d2)) => d1 == d2
    _ => false
  }
}

///|
/// Whether the text at the current offset opens a task list item, and if so
/// whether it is checked. Moves the offset past the brackets.
fn BlockParser::take_task_marker(self : BlockParser) -> Task {
  if !self.flavor.task_lists || scan_task_marker(self.line[:], 0) == 0 {
    return Plain
  }
  if self.peek(self.offset) != 0x5B {
    return Plain
  }
  let inner = self.peek(self.offset + 1)
  if !(inner == 0x20 || inner == 0x78 || inner == 0x58) ||
    self.peek(self.offset + 2) != 0x5D {
    return Plain
  }
  self.advance_offset(3, false)
  if inner == 0x78 || inner == 0x58 {
    Checked
  } else {
    Unchecked
  }
}

///|
/// `spacechar* marker spacechar+ ("[ ]" | "[x]") spacechar+` at the very start
/// of the line.
fn scan_task_marker(text : StringView, start : Int32) -> Int32 {
  let mut i = start
  while cu(text, i) == 0x20 ||
        cu(text, i) == 0x09 ||
        cu(text, i) == 0x0B ||
        cu(text, i) == 0x0C {
    i = i + 1
  }
  let c = cu(text, i)
  if c == 0x2A || c == 0x2D || c == 0x2B {
    i = i + 1
  } else {
    let mut digits = 0
    while is_digit(cu(text, i)) {
      digits = digits + 1
      i = i + 1
    }
    if digits == 0 || cu(text, i) != 0x2E {
      return 0
    }
    i = i + 1
  }
  let mut spaces = 0
  while cu(text, i) == 0x20 ||
        cu(text, i) == 0x09 ||
        cu(text, i) == 0x0B ||
        cu(text, i) == 0x0C {
    spaces = spaces + 1
    i = i + 1
  }
  if spaces == 0 || cu(text, i) != 0x5B {
    return 0
  }
  let inner = cu(text, i + 1)
  if !(inner == 0x20 || inner == 0x78 || inner == 0x58) ||
    cu(text, i + 2) != 0x5D {
    return 0
  }
  i = i + 3
  let mut trailing = 0
  while cu(text, i) == 0x20 ||
        cu(text, i) == 0x09 ||
        cu(text, i) == 0x0B ||
        cu(text, i) == 0x0C {
    trailing = trailing + 1
    i = i + 1
  }
  if trailing == 0 {
    return 0
  }
  i - start
}

///|
/// Open the containers this line starts, inside `container`.
fn BlockParser::open_new_blocks(
  self : BlockParser,
  container : Int32,
  all_matched : Bool,
) -> Int32 {
  let mut container = container
  let mut maybe_lazy = self.tree.nodes[self.current].kind == Paragraph
  let mut cont_type = self.tree.nodes[container].kind
  let mut depth = 0
  while cont_type != Code && cont_type != Html {
    depth = depth + 1
    self.find_first_nonspace()
    let indented = self.indent >= CODE_INDENT
    let first = self.first_nonspace
    let text = self.line[:]
    let atx = if indented { 0 } else { scan_atx_heading_start(text, first) }
    let fence = if indented { 0 } else { scan_open_code_fence(text, first) }
    let html_start = if indented {
      0
    } else {
      scan_html_block_start(text, first)
    }
    let html_start_seven = if indented ||
      html_start != 0 ||
      cont_type == Paragraph {
      0
    } else if scan_html_block_start_7(text, first) {
      7
    } else {
      0
    }
    let setext = if !indented && cont_type == Paragraph {
      scan_setext_heading_line(text, first)
    } else {
      0
    }
    let thematic = if !indented && !(cont_type == Paragraph && !all_matched) {
      scan_thematic_break(text, first)
    } else {
      0
    }
    let marker = if (!indented || cont_type == List) &&
      self.indent < CODE_INDENT &&
      depth < MAX_LIST_DEPTH {
      parse_list_marker(text, first, cont_type == Paragraph)
    } else {
      None
    }
    let marker_matched = marker is Some(_)
    let opened_html = if html_start != 0 {
      html_start
    } else {
      html_start_seven
    }
    if !indented && self.peek(first) == 0x3E {
      let start = first
      self.advance_offset(start + 1 - self.offset, false)
      if is_space_or_tab(self.peek(self.offset)) {
        self.advance_offset(1, true)
      }
      container = self.add_child(container, Quote)
    } else if atx != 0 {
      let heading_start = first
      self.advance_offset(heading_start + atx - self.offset, false)
      container = self.add_child(container, Heading)
      let mut hashpos = first
      let mut level = 0
      while self.peek(hashpos) == 0x23 {
        level = level + 1
        hashpos = hashpos + 1
      }
      self.tree.nodes[container].level = level
      self.tree.nodes[container].setext = false
    } else if fence != 0 {
      container = self.add_child(container, Code)
      self.tree.nodes[container].fenced = true
      self.tree.nodes[container].fence_char = self.peek(first)
      self.tree.nodes[container].fence_length = fence
      self.tree.nodes[container].fence_offset = first - self.offset
      self.tree.nodes[container].info = ""
      self.advance_offset(first + fence - self.offset, false)
    } else if opened_html != 0 {
      container = self.add_child(container, Html)
      self.tree.nodes[container].html_type = opened_html
    } else if setext != 0 {
      let has_content = self.resolve_reference_link_definitions(container)
      if has_content {
        self.tree.nodes[container].kind = Heading
        self.tree.nodes[container].level = setext
        self.tree.nodes[container].setext = true
        self.advance_offset(self.line.length() - 1 - self.offset, false)
      }
    } else if thematic != 0 {
      container = self.add_child(container, ThematicBreak)
      self.advance_offset(self.line.length() - 1 - self.offset, false)
    } else if marker_matched {
      container = self.open_list_item(
        container,
        cont_type,
        marker.unwrap(),
        first,
      )
    } else if indented && !maybe_lazy && !self.blank {
      self.advance_offset(CODE_INDENT, true)
      container = self.add_child(container, Code)
      self.tree.nodes[container].fenced = false
      self.tree.nodes[container].fence_char = 0
      self.tree.nodes[container].fence_length = 0
      self.tree.nodes[container].fence_offset = 0
      self.tree.nodes[container].info = ""
    } else if !indented &&
      cont_type == Paragraph &&
      self.flavor.tables &&
      scan_table_start(text, first) != 0 {
      let table = self.open_table(container)
      if table < 0 {
        break
      }
      container = table
    } else if !indented && cont_type == Table {
      let row = self.open_table_row(container)
      if row < 0 {
        break
      }
      container = row
    } else if cont_type == Item {
      match self.take_task_marker() {
        Plain => break
        task => self.tree.nodes[container].task = task
      }
    } else {
      break
    }
    if accepts_lines(self.tree.nodes[container].kind) {
      break
    }
    cont_type = self.tree.nodes[container].kind
    maybe_lazy = false
  }
  container
}

///|
/// Open a list item, and the list around it when the item starts a new one.
fn BlockParser::open_list_item(
  self : BlockParser,
  container : Int32,
  cont_type : Kind,
  marker : Marker,
  first : Int32,
) -> Int32 {
  let mut container = container
  self.advance_offset(first + marker.matched - self.offset, false)
  let save_partial = self.partial_tab
  let save_offset = self.offset
  let save_column = self.column
  while self.column - save_column <= 5 &&
        is_space_or_tab(self.peek(self.offset)) {
    self.advance_offset(1, true)
  }
  let spaces = self.column - save_column
  let mut padding = 0
  if spaces >= 5 || spaces < 1 || is_line_end(self.peek(self.offset)) {
    padding = marker.matched + 1
    self.offset = save_offset
    self.column = save_column
    self.partial_tab = save_partial
    if spaces > 0 {
      self.advance_offset(1, true)
    }
  } else {
    padding = marker.matched + spaces
  }
  let marker_offset = self.indent
  if cont_type != List ||
    !lists_match(self.tree.nodes[container].shape, marker.shape) {
    container = self.add_child(container, List)
    self.tree.nodes[container].shape = marker.shape
    self.tree.nodes[container].marker_offset = marker_offset
    self.tree.nodes[container].padding = padding
  }
  container = self.add_child(container, Item)
  self.tree.nodes[container].shape = marker.shape
  self.tree.nodes[container].marker_offset = marker_offset
  self.tree.nodes[container].padding = padding
  container
}

///|
fn accepts_lines(kind : Kind) -> Bool {
  kind == Paragraph || kind == Heading || kind == Code
}

///|
/// Add a child block, closing parents that cannot hold it. Returns the child.
fn BlockParser::add_child(
  self : BlockParser,
  parent : Int32,
  kind : Kind,
) -> Int32 {
  let mut parent = parent
  while !self.tree.can_contain(parent, kind) {
    parent = self.finalize(parent)
  }
  let child = self.tree.make(kind, self.line_number - 1)
  self.tree.append_child(parent, child)
  child
}

///|
/// Strip the link reference definitions a paragraph starts with. Returns false
/// when nothing is left, in which case the paragraph is not a paragraph at all.
fn BlockParser::resolve_reference_link_definitions(
  self : BlockParser,
  index : Int32,
) -> Bool {
  let content = self.tree.nodes[index].content
  let text = content.to_string()
  let mut pos = 0
  while pos < text.length() && cu(text[:], pos) == 0x5B {
    match parse_reference(text[:], pos, self.refs) {
      Some(next) => pos = next
      None => break
    }
  }
  let rest = text.clamped_view(start=pos, end=text.length())
  let keep = rest.to_owned()
  content.reset()
  content.write_string(keep)
  !is_blank(rest)
}

///|
/// Close a block: whatever the block phase still has to do with it happens
/// here. Returns the parent, which becomes the new innermost open block.
fn BlockParser::finalize(self : BlockParser, index : Int32) -> Int32 {
  let parent = self.tree.nodes[index].parent
  self.tree.nodes[index].open = false
  match self.tree.nodes[index].kind {
    Paragraph =>
      if !self.resolve_reference_link_definitions(index) {
        self.tree.unlink(index)
      }
    Code => {
      let node = self.tree.nodes[index]
      if !node.fenced {
        remove_trailing_blank_lines(node.content)
        node.content.write_char('\n')
      } else {
        let text = node.content.to_string()
        let mut eol = 0
        while eol < text.length() &&
              !(cu(text[:], eol) == 0x0A || cu(text[:], eol) == 0x0D) {
          eol = eol + 1
        }
        let info = text.clamped_view(start=0, end=eol)
        node.info = unescape_backslashes(trim_view(html_unescape(info)))
        let mut start = eol
        if cu(text[:], start) == 0x0D {
          start = start + 1
        }
        if cu(text[:], start) == 0x0A {
          start = start + 1
        }
        let rest = text.clamped_view(start~, end=text.length()).to_owned()
        node.content.reset()
        node.content.write_string(rest)
      }
    }
    List => {
      let mut tight = true
      let mut item = self.tree.nodes[index].first_child
      while item >= 0 && tight {
        let item_node = self.tree.nodes[item]
        if item_node.blank && item_node.next >= 0 {
          tight = false
          break
        }
        let mut sub = item_node.first_child
        while sub >= 0 {
          let sub_node = self.tree.nodes[sub]
          if (item_node.next >= 0 || sub_node.next >= 0) &&
            self.tree.ends_with_blank_line(sub) {
            tight = false
            break
          }
          sub = sub_node.next
        }
        item = item_node.next
      }
      self.tree.nodes[index].tight = tight
    }
    _ => ()
  }
  parent
}

///|
/// Drop the blank lines a block ended with, then cut at the first line ending
/// after the last line that had something on it.
fn remove_trailing_blank_lines(content : StringBuilder) -> Unit {
  let text = content.to_string()
  let n = text.length()
  let mut i = n - 1
  while i >= 0 {
    let c = cu(text[:], i)
    if c != 0x20 && c != 0x09 && c != 0x0A && c != 0x0D {
      break
    }
    i = i - 1
  }
  if i < 0 {
    content.reset()
    return
  }
  let mut end = i
  while end < n && !(cu(text[:], end) == 0x0A || cu(text[:], end) == 0x0D) {
    end = end + 1
  }
  let keep = text.clamped_view(start=0, end~).to_owned()
  content.reset()
  content.write_string(keep)
}

///|
/// Add the rest of the line to the innermost container, closing the blocks the
/// line did not match.
fn BlockParser::add_text_to_container(
  self : BlockParser,
  container : Int32,
  last_matched : Int32,
) -> Unit {
  let mut container = container
  self.find_first_nonspace()
  let container_kind = self.tree.nodes[container].kind
  if self.tree.nodes[container].last_child >= 0 && self.blank {
    let last = self.tree.nodes[container].last_child
    self.tree.nodes[last].blank = true
  }
  let last_line_blank = self.blank &&
    container_kind != Quote &&
    container_kind != Heading &&
    container_kind != ThematicBreak &&
    !(container_kind == Code && self.tree.nodes[container].fenced) &&
    !(container_kind == Item &&
    self.tree.nodes[container].first_child < 0 &&
    self.tree.nodes[container].start_line == self.line_number - 1)
  self.tree.nodes[container].blank = last_line_blank
  let mut ancestor = self.tree.nodes[container].parent
  while ancestor >= 0 {
    self.tree.nodes[ancestor].blank = false
    ancestor = self.tree.nodes[ancestor].parent
  }
  if self.current != last_matched &&
    container == last_matched &&
    !self.blank &&
    self.tree.nodes[self.current].kind == Paragraph {
    self.add_line(self.current)
    return
  }
  while self.current != last_matched {
    self.current = self.finalize(self.current)
  }
  if container_kind == Code {
    self.add_line(container)
  } else if container_kind == Html {
    self.add_line(container)
    let html_type = self.tree.nodes[container].html_type
    if scan_html_block_end(self.line[:], self.first_nonspace, html_type) {
      container = self.finalize(container)
    }
  } else if self.blank {
    ()
  } else if accepts_lines(container_kind) {
    if container_kind == Heading && !self.tree.nodes[container].setext {
      self.chop_trailing_hashtags()
    }
    self.advance_offset(self.first_nonspace - self.offset, false)
    self.add_line(container)
  } else if container_kind == Table ||
    container_kind == TableRow ||
    container_kind == TableCell {
    ()
  } else {
    container = self.add_child(container, Paragraph)
    self.advance_offset(self.first_nonspace - self.offset, false)
    self.add_line(container)
  }
  self.current = container
}

///|
/// Remove the closing `#` sequence of an ATX heading from its content.
fn BlockParser::chop_trailing_hashtags(self : BlockParser) -> Unit {
  let text = self.line[:]
  let mut end = self.line_end
  while end > 0 && is_blank_char(cu(text, end - 1)) {
    end = end - 1
  }
  let original = end - 1
  let mut n = original
  while n >= 0 && cu(text, n) == 0x23 {
    n = n - 1
  }
  if n != original && n >= 0 && is_space_or_tab(cu(text, n)) {
    while n > 0 && is_blank_char(cu(text, n - 1)) {
      n = n - 1
    }
    self.line_end = n
  } else {
    self.line_end = end
  }
}

///|
/// Process one line, which always ends with a newline.
fn BlockParser::process_line(self : BlockParser, line : String) -> Unit {
  self.line = line
  self.line_end = line.length()
  self.offset = 0
  self.column = 0
  self.first_nonspace = 0
  self.first_nonspace_column = 0
  self.indent = 0
  self.blank = false
  self.partial_tab = false
  self.line_number = self.line_number + 1
  let (last_matched, all_matched) = self.check_open_blocks()
  if last_matched < 0 {
    return
  }
  let container = self.open_new_blocks(last_matched, all_matched)
  self.add_text_to_container(container, last_matched)
}

///|
/// Close everything still open. The document is the last to go.
fn BlockParser::close_all(self : BlockParser) -> Unit {
  while self.current != self.root {
    self.current = self.finalize(self.current)
  }
  let _ = self.finalize(self.root)
}
