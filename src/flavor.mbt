///|
/// What a parser accepts beyond the CommonMark core. The presets `commonmark`
/// and `gfm` cover the two dialects this library is asked for; the fields are
/// public so a caller can take one and drop what it does not want.
pub(all) struct Flavor {
  /// Pipe tables.
  tables : Bool
  /// `~one~` and `~~two~~` strikethrough.
  strikethrough : Bool
  /// Links written bare, without angle brackets or a destination.
  autolinks : Bool
  /// `- [ ]` and `- [x]` list items.
  task_lists : Bool
  /// Escape the raw HTML tags that would change the meaning of the page.
  tag_filter : Bool
  /// `[^label]` references with their `[^label]:` definitions.
  footnotes : Bool
}

///|
/// CommonMark without any of the extensions.
pub let commonmark : Flavor = {
  tables: false,
  strikethrough: false,
  autolinks: false,
  task_lists: false,
  tag_filter: false,
  footnotes: false,
}

///|
/// CommonMark as GitHub reads it: tables, strikethrough, bare links, task list
/// items, the tag filter and footnotes. This is the default.
pub let gfm : Flavor = {
  tables: true,
  strikethrough: true,
  autolinks: true,
  task_lists: true,
  tag_filter: true,
  footnotes: true,
}

///|
/// The preset `parse` uses when the caller does not pass one: `gfm`.
pub let flavor : Flavor = gfm
