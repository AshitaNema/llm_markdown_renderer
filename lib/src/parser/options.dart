import '../ast/block.dart';
import '../ast/inline.dart';

/// Feature switches for the Markdown parser.
final class MarkdownParserOptions {
  /// Creates parser options. Everything is enabled by default.
  const MarkdownParserOptions({
    this.tables = true,
    this.strikethrough = true,
    this.taskLists = true,
    this.autolinks = true,
    this.math = true,
    this.citations = true,
    this.thinking = true,
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

  /// Whether citation markers become [InlineCitation]s: `[1]`, `[12]`,
  /// `[1, 2]`, `[^1]` and `[^note]`.
  ///
  /// Not when the `[` indexes something (`array[1]`, `m[i][0]`, `f()[0]`),
  /// when a label is `0` (`[0, 1]` is a range), or when followed by `(` (a
  /// link such as `[1](url)`) or by `:` (a definition such as `[1]: url`).
  /// `[^1]` may follow a word directly, as GFM footnote references do.
  final bool citations;

  /// Whether `<think>…</think>` and `<thinking>…</thinking>` at the start of
  /// the reply become a [ThinkingBlock], as reasoning models emit them.
  ///
  /// The opening tag must come before any other content (blank lines
  /// aside); later in the text it is ordinary text. The closing tag must
  /// start or end a line (`</think>`, `…done.</think>`, `</think> Answer`)
  /// and is ignored inside code blocks and in the middle of a line.
  final bool thinking;
}
