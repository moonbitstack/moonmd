// Incremental parsing: feed the text as it arrives, and take the blocks that
// are already settled. A block settles when no later line can change it, which
// is when a following line has closed it.

///|
/// A parser that reads a document in pieces. Text that has arrived is parsed
/// again on every call, but only the part that has not been handed out yet, so
/// the work per chunk is proportional to the unfinished tail rather than to the
/// whole document.
pub struct Stream {
  priv mut pending : String
  priv flavor : Flavor
  priv refs : Map[String, Reference]
  /// Whether a block that may hold a reference link waits for the definitions
  /// at the end of the document before it is handed out.
  priv defer_links : Bool
  priv mut finished : Bool
  /// Whether the last chunk ended in a carriage return, which the following
  /// line ending has to pair with.
  priv mut pending_cr : Bool
}

///|
/// Start a stream.
///
/// `defer_links` keeps a block that mentions `[` back until the whole document
/// has arrived, because a link reference definition written later still applies
/// to it. With it off such a block is handed out as soon as it closes, at the
/// cost of a forward reference not resolving; the blocks are then the same as a
/// whole parse for any document that defines its labels before using them.
pub fn Stream::new(
  flavor~ : Flavor = flavor,
  defer_links~ : Bool = true,
) -> Stream {
  {
    pending: "",
    flavor,
    refs: (Map([]) : Map[String, Reference]),
    defer_links,
    finished: false,
    pending_cr: false,
  }
}

///|
/// Take the next piece of the document and return the blocks it completed.
pub fn Stream::feed(self : Stream, chunk : StringView) -> Array[Block] {
  if self.finished {
    return []
  }
  let normalized = StringBuilder()
  for c in chunk {
    if self.pending_cr {
      self.pending_cr = false
      if c == '\n' {
        continue
      }
    }
    if c == '\r' {
      normalized.write_char('\n')
      self.pending_cr = true
    } else if c == '\u{0}' {
      normalized.write_char('\u{FFFD}')
    } else {
      normalized.write_char(c)
    }
  }
  let text = self.pending + normalized.to_string()
  // Only whole lines can be parsed; a partial line waits for the next chunk.
  let mut complete = 0
  let n = text.length()
  let mut i = 0
  while i < n {
    if cu(text[:], i) == 0x0A {
      complete = i + 1
    }
    i = i + 1
  }
  if complete == 0 {
    self.pending = text
    return []
  }
  let ready = text.clamped_view(start=0, end=complete).to_owned()
  let (blocks, cut) = parse_prefix(
    ready,
    self.flavor,
    self.refs,
    self.defer_links,
  )
  self.pending = text.clamped_view(start=cut, end=n).to_owned()
  blocks
}

///|
/// Close the stream and return whatever was still open.
pub fn Stream::finish(self : Stream) -> Array[Block] {
  if self.finished {
    return []
  }
  self.finished = true
  let mut text = self.pending
  if text.length() == 0 {
    return []
  }
  if cu(text[:], text.length() - 1) != 0x0A {
    text = text + "\n"
  }
  let parser = BlockParser::new(self.flavor, self.refs)
  for line in split_lines(text) {
    parser.process_line(line)
  }
  parser.close_all()
  build_blocks(parser.tree, parser.refs, self.flavor, parser.root, -1)
}

///|
/// Parse the text that is known to be complete, and return the blocks that no
/// later line can change together with the offset the unfinished part starts at.
fn parse_prefix(
  text : String,
  flavor : Flavor,
  refs : Map[String, Reference],
  defer_links : Bool,
) -> (Array[Block], Int32) {
  let lines = split_lines(text)
  let starts : Array[Int32] = []
  let mut offset = 0
  for line in lines {
    starts.push(offset)
    offset = offset + line.length()
  }
  let parser = BlockParser::new(flavor, refs)
  for line in lines {
    parser.process_line(line)
  }
  // The part that is settled ends where the first block that is still open, or
  // the first block that may want a definition from later on, begins.
  let mut stop = -1
  let mut cut = text.length()
  let mut child = parser.tree.nodes[parser.root].first_child
  while child >= 0 {
    let node = parser.tree.nodes[child]
    if node.open {
      stop = child
      cut = starts[node.start_line]
      break
    }
    if defer_links && block_mentions_bracket(text, starts, node, parser) {
      stop = child
      cut = starts[node.start_line]
      break
    }
    child = node.next
  }
  let blocks = build_blocks(parser.tree, parser.refs, flavor, parser.root, stop)
  (blocks, cut)
}

///|
/// Whether the source of a block holds a `[`, which is the only way a link
/// reference definition written later can change what it means.
fn block_mentions_bracket(
  text : String,
  starts : Array[Int32],
  node : TreeNode,
  parser : BlockParser,
) -> Bool {
  let start = starts[node.start_line]
  let end = if node.next >= 0 {
    starts[parser.tree.nodes[node.next].start_line]
  } else {
    text.length()
  }
  let mut i = start
  let limit = if end > text.length() { text.length() } else { end }
  while i < limit {
    if cu(text[:], i) == 0x5B {
      return true
    }
    i = i + 1
  }
  false
}
