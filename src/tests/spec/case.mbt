// One example of a conformance corpus: the Markdown, and the HTML it has to
// produce.

///|
/// A single example from a corpus, numbered the way the corpus numbers it.
pub(all) struct Case {
  example : Int32
  section : String
  markdown : String
  html : String
}
