// Pipe tables. A table starts when the line after a paragraph's last line is a
// delimiter row of the same width, and grows one row per following line until
// a blank line or a block that cannot live inside a table.

///|
/// One row of a table as it was written: the cells, with the escapes of pipes
/// resolved but nothing else, and where the row ended.
priv struct TableRow {
  cells : Array[String]
}

///|
/// Turn `\|` back into `|`, which is how a cell holds a pipe of its own.
fn unescape_pipes(text : StringView) -> String {
  if !text.contains_char('\\') {
    return text.to_owned()
  }
  let buf = StringBuilder()
  let n = text.length()
  let mut i = 0
  while i < n {
    if cu(text, i) == 0x5C && cu(text, i + 1) == 0x7C {
      i = i + 1
    }
    buf.write_char(char_at(text, i))
    i = i + char_at(text, i).utf16_len()
  }
  buf.to_string()
}

///|
/// Parse one row of a table starting at `start`. The row has to reach the end
/// of the text, which is one line.
fn parse_table_row(text : StringView, start : Int32) -> TableRow? {
  let n = text.length()
  let mut offset = start + scan_table_cell_end(text, start)
  let cells : Array[String] = []
  let mut expect_more = true
  while offset < n && expect_more {
    let cell_len = scan_table_cell(text, offset)
    let pipe_len = scan_table_cell_end(text, offset + cell_len)
    if cell_len > 0 || pipe_len > 0 {
      let raw = text.clamped_view(start=offset, end=offset + cell_len)
      cells.push(trim_view(unescape_pipes(raw)[:]).to_owned())
    }
    offset = offset + cell_len + pipe_len
    if pipe_len > 0 {
      expect_more = true
    } else {
      offset = offset + scan_table_row_end(text, offset)
      expect_more = false
    }
  }
  if offset != n || cells.length() == 0 {
    return None
  }
  Some({ cells, })
}

///|
/// The alignment a delimiter cell asks for.
fn alignment_of(cell : StringView) -> Align {
  if cell.is_empty() {
    return Default
  }
  let left = cell.at(0).to_int() == 0x3A
  let right = cell.at(cell.length() - 1).to_int() == 0x3A
  if left && right {
    Center
  } else if left {
    Left
  } else if right {
    Right
  } else {
    Default
  }
}

///|
/// Where the last line of a paragraph starts, and the paragraph without it.
fn split_last_line(text : String) -> (Int32, String) {
  let mut line_start = 0
  let n = text.length()
  let mut i = 0
  while i < n {
    if cu(text[:], i) == 0x0A && i + 1 < n {
      line_start = i + 1
    }
    i = i + 1
  }
  let prefix = if line_start == 0 {
    ""
  } else {
    text.clamped_view(start=0, end=line_start).to_owned()
  }
  (line_start, prefix)
}

///|
/// Turn the open paragraph into a table when the line is a delimiter row of the
/// same width as the paragraph's last line. Returns the table, or `-1` when the
/// line is not one.
fn BlockParser::open_table(self : BlockParser, index : Int32) -> Int32 {
  let node = self.tree.nodes[index]
  if node.kind != Paragraph {
    return -1
  }
  if node.visited {
    return -1
  }
  let delimiter = match parse_table_row(self.line[:], self.first_nonspace) {
    Some(row) => row
    None => return -1
  }
  let content = node.content.to_string()
  let (line_start, prefix) = split_last_line(content)
  let header = match parse_table_row(content[:], line_start) {
    Some(row) => row
    None => return -1
  }
  if header.cells.length() != delimiter.cells.length() {
    node.visited = true
    return -1
  }
  let align : Array[Align] = []
  for cell in delimiter.cells {
    align.push(alignment_of(cell[:]))
  }
  if !is_blank(prefix[:]) {
    let paragraph = self.tree.make(Paragraph, node.start_line)
    self.tree.nodes[paragraph].content.write_string(prefix)
    self.tree.insert_before(index, paragraph)
  }
  node.kind = Table
  node.align = align
  node.content.reset()
  let header_row = self.tree.make(TableRow, node.start_line)
  self.tree.nodes[header_row].open = false
  self.tree.nodes[header_row].header = true
  self.tree.append_child(index, header_row)
  for cell in header.cells {
    let cell_node = self.tree.make(TableCell, node.start_line)
    self.tree.nodes[cell_node].open = false
    self.tree.nodes[cell_node].content.write_string(cell)
    self.tree.append_child(header_row, cell_node)
  }
  self.advance_offset(self.line.length() - 1 - self.offset, false)
  index
}

///|
/// Add a body row to the table at `index`. Returns the row, or `-1` when the
/// line is not a row.
fn BlockParser::open_table_row(self : BlockParser, index : Int32) -> Int32 {
  if self.blank {
    return -1
  }
  match parse_table_row(self.line[:], self.first_nonspace) {
    None => -1
    Some(row) => {
      let columns = self.tree.nodes[index].align.length()
      let row_node = self.tree.make(TableRow, self.line_number - 1)
      self.tree.nodes[row_node].open = false
      self.tree.append_child(index, row_node)
      let mut i = 0
      while i < columns {
        let cell_node = self.tree.make(TableCell, self.line_number - 1)
        self.tree.nodes[cell_node].open = false
        if i < row.cells.length() {
          self.tree.nodes[cell_node].content.write_string(row.cells[i])
        }
        self.tree.append_child(row_node, cell_node)
        i = i + 1
      }
      self.advance_offset(self.line.length() - 1 - self.offset, false)
      row_node
    }
  }
}
