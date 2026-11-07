// The scratch tree the block phase builds. Nodes live in one array and refer to
// each other by index, so a parent can be linked and unlinked without the
// ownership questions a tree of pointers would raise in MoonBit.

///|
#derive(Eq)
priv enum Kind {
  Document
  Quote
  List
  Item
  Paragraph
  Heading
  Code
  Html
  ThematicBreak
  Table
  TableRow
  TableCell
  FootnoteDefinition
}

///|
/// The marks a list carries: the bullet character, or the number and delimiter
/// of an ordered list.
priv enum ListShape {
  NoList
  Bullet(Char)
  Ordered(Int32, Char)
}

///|
priv struct TreeNode {
  mut kind : Kind
  mut parent : Int32
  mut first_child : Int32
  mut last_child : Int32
  mut next : Int32
  mut prev : Int32
  mut open : Bool
  /// Whether the last line that belonged to this block was blank.
  mut blank : Bool
  /// Whether `blank` already stands for the whole subtree.
  mut settled : Bool
  content : StringBuilder
  start_line : Int32
  mut level : Int32
  mut setext : Bool
  mut fenced : Bool
  mut fence_char : Int32
  mut fence_length : Int32
  mut fence_offset : Int32
  mut info : String
  mut html_type : Int32
  mut shape : ListShape
  mut marker_offset : Int32
  mut padding : Int32
  mut tight : Bool
  mut task : Task
  mut align : Array[Align]
  mut header : Bool
  /// Whether a paragraph already failed to become a table, so the delimiter row
  /// is not tried again with every following line.
  mut visited : Bool
}

///|
/// The tree: node zero is the document.
priv struct Tree {
  nodes : Array[TreeNode]
}

///|
fn Tree::new() -> Tree {
  let tree : Tree = { nodes: [], }
  tree.nodes.push(TreeNode::{
    kind: Document,
    parent: -1,
    first_child: -1,
    last_child: -1,
    next: -1,
    prev: -1,
    open: true,
    blank: false,
    settled: false,
    content: StringBuilder(),
    start_line: 0,
    level: 0,
    setext: false,
    fenced: false,
    fence_char: 0,
    fence_length: 0,
    fence_offset: 0,
    info: "",
    html_type: 0,
    shape: NoList,
    marker_offset: 0,
    padding: 0,
    tight: true,
    task: Plain,
    align: [],
    header: false,
    visited: false,
  })
  tree
}

///|
fn Tree::make(self : Tree, kind : Kind, line : Int32) -> Int32 {
  self.nodes.push(TreeNode::{
    kind,
    parent: -1,
    first_child: -1,
    last_child: -1,
    next: -1,
    prev: -1,
    open: true,
    blank: false,
    settled: false,
    content: StringBuilder(),
    start_line: line,
    level: 0,
    setext: false,
    fenced: false,
    fence_char: 0,
    fence_length: 0,
    fence_offset: 0,
    info: "",
    html_type: 0,
    shape: NoList,
    marker_offset: 0,
    padding: 0,
    tight: true,
    task: Plain,
    align: [],
    header: false,
    visited: false,
  })
  self.nodes.length() - 1
}

///|

///|
/// Whether a block of `parent` kind may hold one of `child` kind. A child that
/// does not fit closes its parent first, which is how a heading inside a table
/// ends the table.
fn Tree::can_contain(self : Tree, parent : Int32, child : Kind) -> Bool {
  match self.nodes[parent].kind {
    Document | Quote | Item | FootnoteDefinition => true
    List => child == Item
    Table => child == TableRow
    TableRow => child == TableCell
    _ => false
  }
}

///|
fn Tree::append_child(self : Tree, parent : Int32, child : Int32) -> Unit {
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
/// Put `node` in front of `index` in the same parent.
fn Tree::insert_before(self : Tree, index : Int32, node : Int32) -> Unit {
  let parent = self.nodes[index].parent
  let prev = self.nodes[index].prev
  self.nodes[node].parent = parent
  self.nodes[node].prev = prev
  self.nodes[node].next = index
  self.nodes[index].prev = node
  if prev >= 0 {
    self.nodes[prev].next = node
  } else {
    self.nodes[parent].first_child = node
  }
}

///|
fn Tree::unlink(self : Tree, index : Int32) -> Unit {
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
/// Whether the block, or the last block inside it, ended on a blank line. This
/// is what makes a list loose.
fn Tree::ends_with_blank_line(self : Tree, index : Int32) -> Bool {
  if self.nodes[index].settled {
    return self.nodes[index].blank
  }
  let node = self.nodes[index]
  if (node.kind == List || node.kind == Item) && node.last_child >= 0 {
    self.nodes[index].settled = true
    self.ends_with_blank_line(node.last_child)
  } else {
    self.nodes[index].settled = true
    node.blank
  }
}

///|
fn Tree::last_child_is_open(self : Tree, index : Int32) -> Bool {
  let last = self.nodes[index].last_child
  last >= 0 && self.nodes[last].open
}
