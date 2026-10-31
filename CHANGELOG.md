## 0.1.1

* Fix table columns being sized slightly too narrow, which made cell text wrap mid-word (for example `Highlightin` / `g`). It showed up when `MarkdownTheme.fromTheme` was built from a `ThemeData` created outside `MaterialApp`. Column widths now come from Flutter's own layout and still never shrink while a table streams in.
* Add a demo GIF to the pub.dev screenshots.

## 0.1.0

Initial release.

* Incremental, chunk-boundary-independent Markdown parser (`IncrementalMarkdownParser`), usable without Flutter.
* `StreamingMarkdown` widget with controller (`MarkdownStreamController.append`), `Stream<String>` and static constructors.
* Stable rendering of unclosed code fences, tables, lists, emphasis and links while streaming.
* Syntax-highlighted code blocks with copy button; pure-Dart incremental highlighter for 18 languages and a pluggable `CodeHighlighter` interface.
* `MarkdownTheme` / `SyntaxTheme` styling via `ThemeExtension`.
* Example chat app simulating a streaming LLM.
