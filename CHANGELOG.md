## 1.0.0

The first stable release. From here on the package follows semantic versioning: the API exported from `llm_markdown_renderer.dart` and `parser.dart` only changes incompatibly in a major release, and new `Block` or `Inline` subclasses also wait for a major release. See "Versioning" in the README.

New:

* **Smooth typing.** `MarkdownStreamController(pace: TypingPace(...))` shows bursty streams at a steady speed, never more than `maxDelay` behind what has arrived. `StreamingMarkdown.fromStream` takes a `pace` too.
* `MarkdownStreamController.flush()` shows all waiting text at once (for a "Stop" button), and `pendingLength` says how much is waiting. With a pace, `complete()` finishes the document once the waiting text has been shown.

Breaking changes (made now so the stable API can grow without more of them):

* **Builders get the node and the surrounding text style.** `MarkdownImageBuilder`, `MarkdownMathBuilder` and `MarkdownCitationBuilder` now take `(context, node, style)`: the `InlineImage`, `InlineMath` or `InlineCitation` (which can gain fields without breaking your code) and the `TextStyle` around it, which a widget inside text does not inherit. Inline math in a heading can now match the heading's size, and an image builder can read `image.title`. Migrate:
  * `imageBuilder: (context, url, alt) => …` → `(context, image, style) => …` with `image.url`, `image.alt`.
  * `mathBuilder: (context, tex, display) => …` → `(context, math, style) => …` with `math.tex`, `math.display`; pass `style` to your typesetter. For a `MathBlock` you get `InlineMath(block.tex, display: true)`.
  * `citationBuilder: (context, labels) => …` → `(context, citation, style) => …` with `citation.labels`.
* `MarkdownTheme` is now a `final class`; build variants with `copyWith` instead of subclassing.

Fixes:

* `StreamingMarkdown.fromStream` stops listening after a stream error, so data the stream emits afterwards no longer throws a `StateError`.

Example:

* The example app paces its replies, flushes them when you tap "Stop", and passes the text style to its math typesetter.

## 0.3.0

LaTeX math, thinking sections and citations, the syntax models emit most that plain Markdown does not cover.

New:

* **LaTeX math.** `$…$` and `\(…\)` inline, `$$…$$` for display math, and `$$` or `\[` blocks on their own lines, as `InlineMath` and `MathBlock` nodes. Typeset it with the new `mathBuilder` (`MarkdownMathBuilder`) and the package of your choice, for example `flutter_math_fork`; without one the TeX source is shown in the code style. The builder is only called once the closing delimiter has arrived, so it never sees half-written TeX. Prices and shell variables (`$5 and $10`, `$HOME`) stay text, also while streaming.
* **Thinking sections.** `<think>…</think>` (and `<thinking>`) at the start of a reply, as reasoning models emit it, becomes a `ThinkingBlock`, shown as a collapsible section: open while the model thinks, folded to "Thoughts" once the section closes. `</think>` inside code does not close it. Customize it with `thinkingBuilder`. Its content is parsed incrementally, so long reasoning stays cheap per token.
* **Citations.** `[1]`, `[1, 2]` and `[^note]` become `InlineCitation`s. They look like the original text unless you pass `onTapCitation` (tappable labels) or `citationBuilder` (your own widget).
* `codeBlockBuilder` may return `null` to keep the default view, so an app can take over only some languages (for example `mermaid`).
* New parser options `math`, `citations` and `thinking`, all on by default.

Behavior changes (pre-1.0):

* With math on, `$x$`, `$$x$$` and `\(x\)`, and `$$` or `\[` blocks on their own lines, no longer render as literal text. Use `\$` for a literal dollar sign, or set `MarkdownParserOptions(math: false)`.
* The new `Block` and `Inline` subclasses mean an exhaustive `switch` over those sealed types needs new cases: `MathBlock`, `ThinkingBlock`, `InlineMath` and `InlineCitation`.
* `MarkdownCodeBlockBuilder` now returns `Widget?`. Existing builders keep working, but code that calls a stored builder must handle `null`.

Docs and example:

* Correct the claim that the parser can be used from plain Dart. It imports nothing from Flutter, but the package depends on the Flutter SDK.
* The example app typesets math with `flutter_math_fork` and shows a reply with a thinking section and citations.

## 0.2.2

Replace the `chat` topic with `ai`, and give the web demo a real title and description.

## 0.2.1

Add homepage, refresh the demo GIF, and fix the demo's frame-time readout and sample text.

## 0.2.0

Tagged but not published to pub.dev; these changes shipped in 0.2.1.

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
