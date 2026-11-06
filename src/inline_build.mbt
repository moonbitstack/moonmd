// Turning the inline scratch tree into the public `Inline` values.

///|
/// The inlines inside `parent`, in order. Empty text nodes are dropped: they
//  only exist while delimiters are being paired up.
fn materialize_inlines(tree : InlineTree, parent : Int32) -> Array[Inline] {
  let out : Array[Inline] = []
  let mut node = tree.nodes[parent].first_child
  while node >= 0 {
    let next = tree.nodes[node].next
    let current = tree.nodes[node]
    match current.kind {
      TextNode => {
        let text = tree.literal(node)
        if text.length() > 0 {
          out.push(Text(text.to_owned()))
        }
      }
      CodeNode => out.push(Code(current.text))
      HtmlNode => out.push(Html(current.text))
      SoftBreakNode => out.push(Break(Soft))
      HardBreakNode => out.push(Break(Hard))
      EmphNode => out.push(Emphasis(materialize_inlines(tree, node)))
      StrongNode => out.push(Strong(materialize_inlines(tree, node)))
      StrikeNode => out.push(Strike(materialize_inlines(tree, node)))
      LinkNode =>
        out.push(
          Link({
            dest: current.text,
            title: current.title,
            content: materialize_inlines(tree, node),
          }),
        )
      ImageNode =>
        out.push(
          Image({
            dest: current.text,
            title: current.title,
            content: materialize_inlines(tree, node),
          }),
        )
    }
    node = next
  }
  out
}
