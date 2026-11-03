/// Feature switches for the Markdown parser.
final class MarkdownParserOptions {
  /// Creates parser options. Everything is enabled by default.
  const MarkdownParserOptions({
    this.tables = true,
    this.strikethrough = true,
    this.taskLists = true,
    this.autolinks = true,
    this.math = true,
  });

  /// Whether GitHub-flavoured tables are recognised.
  final bool tables;

  /// Whether `~~text~~` is parsed as strikethrough.
  final bool strikethrough;

  /// Whether `- [ ]` / `- [x]` list items become task-list items.
  final bool taskLists;

  /// Whether bare `http://` / `https://` URLs and `<url>` become links.
  final bool autolinks;

  /// Whether LaTeX math is recognised: `$…$` and `\(…\)` inline,
  /// `$$…$$` for display math, and `$$` or `\[` blocks on their own lines.
  ///
  /// Dollar signs follow Pandoc's rules so prices are left alone: the
  /// opening `$` must be followed by a non-space, the closing `$` must be
  /// preceded by a non-space and not followed by a digit. `\$` is always a
  /// literal dollar sign.
  final bool math;
}
