/// Feature switches for the Markdown parser.
final class MarkdownParserOptions {
  /// Creates parser options. Everything is enabled by default.
  const MarkdownParserOptions({
    this.tables = true,
    this.strikethrough = true,
    this.taskLists = true,
    this.autolinks = true,
  });

  /// Whether GitHub-flavoured tables are recognised.
  final bool tables;

  /// Whether `~~text~~` is parsed as strikethrough.
  final bool strikethrough;

  /// Whether `- [ ]` / `- [x]` list items become task-list items.
  final bool taskLists;

  /// Whether bare `http://` / `https://` URLs and `<url>` become links.
  final bool autolinks;
}
