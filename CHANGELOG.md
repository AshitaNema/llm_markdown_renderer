## 0.1.0

Initial release.

* Incremental, chunk-boundary-independent Markdown parser (`IncrementalMarkdownParser`), usable without Flutter.
* `StreamingMarkdown` widget with controller (`MarkdownStreamController.append`), `Stream<String>` and static constructors.
* Stable rendering of unclosed code fences, tables, lists, emphasis and links while streaming.
* Syntax-highlighted code blocks with copy button; pure-Dart incremental highlighter for 18 languages and a pluggable `CodeHighlighter` interface.
* `MarkdownTheme` / `SyntaxTheme` styling via `ThemeExtension`.
* Example chat app simulating a streaming LLM.
