## 0.2.0

Breaking (pre-1.0): the public API is smaller.

* `LineBuffer`, `parseInlines` and `isSafeLinkUrl` are no longer exported; they were implementation details. Use `IncrementalMarkdownParser` and `StreamingMarkdown` instead.

Improvements:

* Right-to-left text: paragraphs, headings and table cells take the direction of their first strong character (Arabic, Hebrew), list markers and block-quote bars mirror in right-to-left contexts, and code stays left-to-right.
* Accessibility: headings are semantic headers and lists expose list/list-item roles.
* Reading `MarkdownStreamController.document` no longer copies the block list twice (about 2x faster for very large documents).
* Add `benchmark/append_cost.dart`, golden tests, accessibility, RTL and text-scale tests, `doc/integrations.md` (Firebase AI, OpenAI-compatible and Anthropic streaming), CI, GitHub Pages demo and contribution docs.
* Stricter lints (`strict-casts`, `strict-inference`, `strict-raw-types` and more).

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
