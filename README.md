# llm_markdown_renderer

Render Markdown that is streamed **token by token from an LLM** without jank.

* **Incremental parsing.** Each chunk costs time proportional to the chunk plus
  the *one* block that is still being written. Finished blocks are never parsed
  again and are not rebuilt by Flutter.
* **Stable while streaming.** Unclosed code fences, half-arrived tables, lists
  and dangling `**` render as a sensible preview that does not flicker or
  re-layout as the rest arrives.
* **Syntax-highlighted code blocks** with a language label and a copy button.
  Highlighting is incremental too, so a 5,000-line block stays cheap.
* **Two APIs:** feed a `MarkdownStreamController` with `append(chunk)`, or hand
  the widget a `Stream<String>`.
* **Themeable** through a `ThemeExtension` (`MarkdownTheme`), light and dark.
* **Pure Dart + Flutter.** No plugins, no native code, no `dart:io`/`dart:html`:
  Android, iOS, Web (including WebAssembly), Windows, macOS and Linux.
* The parser is **Flutter-free** (`package:llm_markdown_renderer/parser.dart`),
  so you can also use it from plain Dart.

## Quick start

```yaml
dependencies:
  llm_markdown_renderer: ^0.1.0
```

### Controller API

```dart
final controller = MarkdownStreamController();

// as tokens arrive from your model / SSE / websocket:
llmTokens.listen(controller.append, onDone: controller.complete);

// in build():
StreamingMarkdown(controller: controller)
```

Call `controller.reset()` to clear the view (for "regenerate"), and
`controller.dispose()` when you are done. `append` is cheap and can be called
hundreds of times per second: listeners are notified at most once per frame.

### Stream API

```dart
StreamingMarkdown.fromStream(stream: llmTokens)
```

The widget owns the subscription and completes the document when the stream
ends. Keep the `Stream` instance stable across rebuilds; passing a different
one starts over. Handle failures with `onStreamError`.

### Static content

```dart
const StreamingMarkdown.static(data: '# Hello **world**')
```

### Links, images, code

```dart
StreamingMarkdown(
  controller: controller,
  onTapLink: (url, title) => launchUrl(Uri.parse(url)), // your choice of plugin
  imageBuilder: (context, url, alt) => Image.network(url), // opt in to images
  highlighter: const CodeHighlighter.defaults(),
)
```

* Links are styled always, but only `http`, `https`, `mailto`, `tel` and
  relative URLs are tappable; `javascript:` and friends are inert. The package
  never launches anything itself.
* Images are **not fetched by default** (model output could point anywhere); an
  alt-text placeholder is shown until you supply an `imageBuilder`.
* Replace the code block entirely with `codeBlockBuilder`, or reuse
  `CodeBlockView` in your own layout.

## Theming

`MarkdownTheme` is a `ThemeExtension`. Without configuration it is derived from
your `ThemeData`; to customise, register it:

```dart
final base = ThemeData(colorSchemeSeed: Colors.teal);
MaterialApp(
  theme: base.copyWith(extensions: [
    MarkdownTheme.fromTheme(base).copyWith(
      blockSpacing: 18,
      codeBlockBorderRadius: 12,
      syntaxTheme: SyntaxTheme.light().copyWith(styles: {
        TokenKind.keyword: const TextStyle(color: Colors.deepPurple),
      }),
    ),
  ]),
);
```

Resolution order: the widget's `theme:` argument, then the `ThemeData`
extension, then a theme derived from the ambient `ThemeData`.

## Syntax highlighting

Built in (pure Dart, rule based, no dependencies): Dart, JavaScript/TypeScript,
JSON, Python, Bash, YAML, SQL, HTML/XML, CSS, C, C++, Java, Kotlin, Swift, Go,
Rust, C#, and diffs, plus common aliases (`js`, `py`, `sh`, `yml`, …). Unknown
languages render as plain monospace.

Add or override a language:

```dart
final highlighter = RuleBasedHighlighter(extraLanguages: [
  LanguageDefinition(name: 'toy', states: {
    'root': [LexRule(r'\bgo\b', TokenKind.keyword)],
  }),
]);
```

or implement the `CodeHighlighter` interface to plug in another engine. The
interface is line-oriented with an opaque carried state, which is what makes
incremental highlighting possible.

## What "stable while streaming" means

| While it is arriving…            | …you see                                                                 |
| -------------------------------- | ------------------------------------------------------------------------ |
| ```` ``` ```` (opening fence)    | a code block shell (header + copy button) as soon as the 3rd backtick lands; a partial ```` `` ```` paints nothing |
| unclosed code fence              | the block, growing append-only; partial closing fence is never painted as code |
| table header only                | a paragraph, until the delimiter row (`\|---\|`) arrives                 |
| partial table row                | a full-width row, missing cells empty; column widths never shrink         |
| `**bold` / `*em` / `` `code ``   | already styled (speculatively closed); a trailing `**` is hidden          |
| `[label](http://ex`              | just the label; it becomes a link when `)` arrives                        |
| `-`, `1.`, `#` alone on a line   | nothing, until there is something to show                                 |

## Using the parser without Flutter

```dart
import 'package:llm_markdown_renderer/parser.dart';

final parser = IncrementalMarkdownParser();
parser.append('# Hi\n\nSome **bo');
print(parser.document.blocks); // [Heading1(...), Paragraph(...)]
parser.append('ld**');
parser.complete();
```

The guarantee that the test-suite enforces: **for every way of splitting the
input into chunks** (down to one character, splitting fences, `\r\n` pairs and
UTF-16 surrogate pairs), the result equals parsing the input in one go.

## Supported Markdown and known differences

ATX/setext headings, paragraphs, emphasis/strong/strikethrough, inline code,
links, images, autolinks, fenced and indented code, block quotes, nested
ordered/unordered lists, task lists, thematic breaks, GFM tables, backslash
escapes and common entities.

Deliberate differences from CommonMark, to keep every append cheap:

* Tight/loose is decided **per list item**, not per list.
* Reference-style links (`[x][ref]`) and raw HTML are not supported (HTML is
  shown as text).
* A block quote is re-parsed as a whole while it is the open block.
* Lists with sub-bullets indented by only 2 spaces under `1.` are treated as
  nested, as most LLMs intend.

## Performance notes

* Parsing is synchronous and proportional to the new text plus the open block.
* Finished blocks are the identical objects between snapshots and their widgets
  are reused by identity.
* Code blocks cache tokenization and layout per 32-line chunk.
* Pass **stable** callbacks/builders to `StreamingMarkdown`; new closures on
  every parent build make the configuration look changed and rebuild finished
  blocks.

## Example

`example/` is a chat app with a fake LLM that streams canned answers in
irregular 1–12 character chunks (so boundaries fall inside fences, tables and
links), with speed control, light/dark toggle, regenerate, a stress test and a
frame-time readout.

```sh
cd example && flutter run
```

## License

MIT, see [LICENSE](https://github.com/AshitaNema/llm_markdown_renderer/blob/main/LICENSE). Design notes are in [ARCHITECTURE.md](https://github.com/AshitaNema/llm_markdown_renderer/blob/main/ARCHITECTURE.md).
