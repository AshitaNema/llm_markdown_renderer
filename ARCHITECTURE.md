# llm_markdown_renderer — Architecture & Public API proposal

Status: **APPROVED and IMPLEMENTED** (v0.1.0). §1–§10 are the approved proposal; §11 lists where the implementation differs from it.

## 1. Goals and non-goals

**Goals**

- Render Markdown arriving token by token from an LLM with no visible jank: constant work per token regardless of document length.
- Never show "broken" intermediate states: unclosed fences, half-arrived tables, in-progress lists and dangling `**` all render as a sensible, *stable* preview.
- Syntax-highlighted code blocks with a copy button.
- Two entry points: `Stream<String>` and a controller with `append(chunk)`.
- Themeable via `ThemeExtension`.
- Pure Dart + Flutter SDK only. No plugins, no `dart:io`, no `dart:html`, so all six pub.dev platforms (Android, iOS, Linux, macOS, Windows, Web) are supported.

**Non-goals (v1)**

- Full CommonMark spec compliance. We target the subset LLMs actually emit (see §3.1), plus GFM tables, strikethrough, task lists and autolinks.
- Reference-style links (`[x][ref]` / `[ref]: url`). They need whole-document lookahead and LLMs rarely emit them.
- Raw HTML rendering (shown as plain text), math (LaTeX), Mermaid.
- Editing / authoring Markdown.
- Typewriter pacing/smoothing of bursty streams (can be layered on later in the controller without API breakage).

## 2. Package layout

```
lib/
  llm_markdown_renderer.dart       # barrel: widgets, controller, theme (Flutter)
  parser.dart                      # barrel: Flutter-free parser + AST + highlighter
  src/
    parser/                        # NO flutter imports; usable in plain Dart
      line_buffer.dart             # chunk -> complete lines (+ pending partial line)
      block_parser.dart            # incremental block state machine
      inline_parser.dart           # inline spans, streaming-tolerant
      table.dart                   # GFM table state
    ast/
      block.dart                   # sealed Block hierarchy
      inline.dart                  # sealed Inline hierarchy
      document.dart                # MarkdownDocument snapshot
    highlight/
      highlighter.dart             # CodeHighlighter interface, Token, TokenKind
      lexer.dart                   # incremental, state-carrying rule-based lexer
      languages/                   # dart, js/ts, python, json, yaml, bash, sql,
                                   # html/xml, css, c-family, diff, ...
    controller/
      markdown_stream_controller.dart
    theme/
      markdown_theme.dart          # ThemeExtension<MarkdownTheme>
      syntax_theme.dart
    widgets/
      streaming_markdown.dart      # main widget
      block_view.dart              # block -> widget dispatch
      code_block.dart              # header + highlighted body + copy button
      table_view.dart
      inline_renderer.dart         # Inline AST -> InlineSpan (cached)
example/                           # chat demo that simulates streaming
test/
```

Two public libraries: `llm_markdown_renderer.dart` (everything) and `parser.dart` (Flutter-free parser, so it is testable under plain `dart test` and reusable in CLIs/servers).

## 3. Core design: incremental parsing

### 3.1 Supported syntax

ATX headings, setext headings, paragraphs, hard/soft breaks, emphasis/strong/strikethrough, inline code, links, autolinks, images, fenced code (``` and ~~~), indented code, blockquotes, ordered/unordered/nested lists, task lists, thematic breaks, GFM tables.

### 3.2 Pipeline

```
chunk ──► LineBuffer ──► BlockParser ──► MarkdownDocument ──► widgets
          (complete      (state machine   (committed blocks    (only the tail
           lines +        over lines)      + one open tail)      block rebuilds)
           pending
           partial line)
```

1. **LineBuffer** splits arbitrary chunks into complete lines and keeps the unterminated remainder (the *pending line*). It normalises `\r\n`/`\r` (including a `\r` at the end of one chunk and `\n` at the start of the next) and holds back a dangling high surrogate so a chunk split inside a surrogate pair never produces U+FFFD.
2. **BlockParser** is a line-oriented state machine. Its state is a stack of *open* blocks (container → leaf). It consumes complete lines once, and re-examines only the pending line on each append.
3. Blocks are either **committed** (immutable, will never change) or **open** (only the tail path of the stack). A block commits only when the parser can *prove* later input cannot alter it: paragraphs on blank line or when another block start interrupts; fences on closing fence; tables when a non-row line arrives; etc.
4. **Inline parsing is per block** and runs only for the open leaf block. Results for committed blocks are cached on the block, never recomputed.

### 3.3 Cost model

Per `append(chunk)`:

- complete lines in the chunk are processed once (O(chunk));
- the open leaf block's inline content is re-parsed (O(size of that block));
- everything committed is untouched, with identical object identity, so widgets for it are not rebuilt.

Containers (lists, blockquotes) use the same protocol recursively: each **list item** and each blockquote child commits independently, so a 200-item list costs O(current item), not O(list). *Deviation from CommonMark:* tight/loose is decided per item (blank line after *that* item) rather than per list, because the per-list rule retroactively changes earlier items. This is invisible for typical LLM output and is the price of O(1) appends. Documented in the README.

Fenced code is special-cased: **append-only lines, never re-parsed**, and highlighted incrementally (§5), so a 5,000-line code block costs O(new lines).

### 3.4 Streaming-stability rules ("never flicker")

| Situation | Behaviour while streaming |
|---|---|
| Partial opening fence (`` ` ``, ``` `` ```) | Shown as paragraph text until the 3rd backtick arrives; then converts to a code block *shell* immediately (header + copy button visible), empty body. |
| Unclosed fence | Rendered as a code block; body grows append-only; no layout shift in the header. Auto-finalized on `complete()`. |
| Partial closing fence (` `` `) at end of a code line | Held back from the code body (not painted) until the line is complete or disambiguated. |
| Table header only (`\| a \| b \|`) | Ambiguous with a paragraph → rendered as paragraph until the delimiter row (`\|---\|---\|`) arrives, then switches to a table (one controlled transition). |
| Table, partial row | Missing cells render empty; the partial last cell is shown as it grows. Column count is fixed by the delimiter row. |
| Table column widths | Widths are **monotonic non-decreasing** while the table is open (no re-shrink jitter) and settle on commit. Horizontally scrollable if wider than the viewport. |
| Unclosed `**`, `*`, `~~`, `` ` `` | Speculatively closed at end of the open block, so text appears styled immediately and un-styles nothing already shown. |
| Incomplete link `[label](ur` / image | Label shown as plain text; promoted to a link when `)` arrives. URL fragment never shown mid-flight. |
| Trailing lone marker (`*`, `_`, `` ` ``, `#`, `-`, `>`, `\|`) on pending line | Lines are classified by a pure function of the (possibly partial) line, with hysteresis only for the fence and table cases above. |
| List marker without content yet (`-`, `1.`) | Not painted as an item until marker + space + at least one char (or newline) has arrived. |

### 3.5 Key invariant (and the heart of the test strategy)

> **Chunking independence:** for any document `D` and any partition of `D` into chunks, the resulting `MarkdownDocument` after feeding all chunks equals the one-shot parse of `D`; and at every intermediate point it equals the one-shot streaming-mode parse of the prefix received so far.

Tests assert this with exhaustive 1-char splits, every 2-way split, and seeded random partitions over a fixture corpus. Splits are deliberately aimed at fence markers, `\r\n`, surrogate pairs, table delimiter rows, list markers, link syntax and emphasis runs. A parse-counter hook proves committed blocks are never re-parsed.

## 4. Public API

### 4.1 Controller

```dart
/// Accumulates streamed Markdown and exposes an incrementally-parsed document.
class MarkdownStreamController extends ChangeNotifier {
  MarkdownStreamController({
    String initialText = '',
    MarkdownParserOptions options = const MarkdownParserOptions(),
  });

  /// Appends [chunk]. Cheap; notifications are coalesced to once per frame.
  void append(String chunk);

  /// Marks the stream finished: commits the open tail, finalizes unclosed
  /// fences/tables/emphasis, and sets [isComplete].
  void complete();

  /// Discards everything and starts over (e.g. "regenerate").
  void reset([String initialText = '']);

  MarkdownDocument get document;   // immutable snapshot
  String get text;                 // raw accumulated markdown
  bool get isComplete;
}
```

Notifications are coalesced to at most one per frame (`SchedulerBinding` post-frame), so a provider emitting 200 tokens/s costs one rebuild per frame. The *parse* still happens synchronously per `append` (it's O(chunk + tail)) so `document` is always current.

### 4.2 Widgets

```dart
/// Renders a controller. Primary, most efficient entry point.
StreamingMarkdown(
  controller: controller,
  theme: null,                       // else Theme.extension<MarkdownTheme>() else derived from ThemeData
  selectable: true,                  // wraps in SelectionArea
  onTapLink: (url, title) {},        // no url_launcher dependency; app decides
  imageBuilder: (context, url, alt) => ...,
  codeBlockBuilder: (context, code) => ...,   // replace the default code block
  highlighter: CodeHighlighter.defaults(),    // pluggable
  shrinkWrap: true,
)

/// Stream convenience: owns an internal controller, completes on stream done.
StreamingMarkdown.fromStream(stream: llmTokens, /* same options */)

/// Static (non-streaming) content, same renderer.
StreamingMarkdown.static(data: '# Hello')
```

Plain-Dart usage, no Flutter:

```dart
final parser = IncrementalMarkdownParser();
parser.append('# Hi\n\nSome **bo');
parser.document.blocks;   // [Heading, Paragraph(open)]
```

### 4.3 AST (public, sealed, immutable, `==`/`hashCode`)

`sealed class Block` → `Paragraph`, `Heading`, `CodeBlock` (language, lines, `isClosed`), `BlockQuote`, `ListBlock` (ordered, start, items), `ListItem` (checked?, children), `Table` (alignments, header, rows), `ThematicBreak`, `HtmlBlock`. Each has a stable `id` and `isOpen`. `sealed class Inline` → `Text`, `Emphasis`, `Strong`, `Strikethrough`, `InlineCode`, `Link`, `Image`, `LineBreak`. Sealed hierarchies give consumers exhaustive `switch`.

### 4.4 Theming

```dart
class MarkdownTheme extends ThemeExtension<MarkdownTheme> {
  // text styles: body, h1..h6, link, inlineCode, strong, emphasis, strikethrough
  // block decor: blockquote bar/colour, code block bg/border/radius/padding,
  //   table border/header bg/cell padding, rule colour, list bullet/indent
  // spacing: blockSpacing, listItemSpacing
  // syntax: SyntaxTheme (Map<TokenKind, TextStyle> + light/dark presets)
  MarkdownTheme({...});
  factory MarkdownTheme.fromTheme(ThemeData theme);  // sensible defaults, light+dark
  @override MarkdownTheme copyWith({...});
  @override MarkdownTheme lerp(MarkdownTheme? other, double t);
}
```

Resolution order: widget `theme:` arg → `Theme.of(context).extension<MarkdownTheme>()` → `MarkdownTheme.fromTheme(Theme.of(context))`. Usage: `ThemeData(extensions: [MarkdownTheme.fromTheme(base).copyWith(...)])`.

## 5. Syntax highlighting

- **Own pure-Dart, rule-based, state-carrying lexer** rather than a dependency. Each language is a small list of regex rules + states (for multi-line comments/strings). Lexer state is saved at the end of each line, so appending lines to a code block tokenizes only the new lines (matches the append-only code model).
- `abstract interface class CodeHighlighter { List<List<Token>> ... }` — the interface is incremental-aware (`HighlightState` in/out per line). Users can plug in any other engine (non-incremental engines are supported by re-highlighting the open block only, which is still bounded).
- Languages v1: Dart, JavaScript/TypeScript, JSON, Python, Bash/shell, YAML, SQL, HTML/XML, CSS, C-family (C, C++, Java, Kotlin, Swift, Go, Rust, C#), Diff, plus alias resolution (`js`, `ts`, `sh`, `yml`, …). Unknown language → plain monospace.
- Token colours come from `SyntaxTheme`, so highlighting follows light/dark automatically.

## 6. Rendering & performance

- `StreamingMarkdown` listens to the controller and builds a `Column` (shrink-wrapped, because it lives inside chat bubbles). Each **committed** block widget has a `ValueKey(block.id)`, is wrapped in `RepaintBoundary`, and compares by identity so `Element.update` short-circuits; only the open tail block rebuilds.
- Inline AST → `InlineSpan` conversion is cached on the (immutable) block.
- Code body is a `Text.rich` per line-batch inside a horizontally scrollable view; the copy button uses `Clipboard.setData` (part of Flutter `services`, works on all platforms), shows transient "copied" feedback, and copies the raw text (never the highlighted spans).
- Images: default renders an alt-text placeholder (no automatic network fetches from LLM-controlled URLs, for privacy/safety); apps opt in via `imageBuilder`.
- Links never auto-launch; `onTapLink` is mandatory to act. Only `http(s)`, `mailto` are treated as links by default (`javascript:` etc. rendered as text).
- Accessibility: semantics labels for headings, code blocks ("code, dart"), copy button tooltip.

## 7. Testing plan

1. **Parser unit tests** per construct (pure `package:test`-style via `flutter_test`).
2. **Chunk-boundary suite** (the §3.5 invariant): 1-char streaming, all 2-way splits, seeded random partitions, aimed at fences, `\r\n` across chunks, surrogate pairs/emoji, table delimiter rows, list markers, nested lists, link/emphasis delimiters, empty chunks, trailing text without newline, `complete()` mid-construct.
3. **Incrementality tests**: parse-count instrumentation proves committed blocks are not re-parsed and keep identity; an O(tail) micro-benchmark (append cost for 10 vs 10,000-block docs must be comparable).
4. **Highlighter tests**: token golden lists per language; incremental == one-shot, split across multi-line comment/string states.
5. **Widget tests**: only tail rebuilds (build counters), copy button writes to clipboard mock, theme resolution order, `fromStream`, dispose safety, `reset`.
6. **Golden tests** for a representative stream snapshot in light & dark.

## 8. Example app (`example/`)

Chat UI with a fake "LLM" that replays a scripted Markdown reply (code, table, nested list, emphasis) as random-sized chunks (1–12 chars, 10–40 ms jitter, including deliberate splits mid-fence/mid-table). Controls: speed slider, light/dark toggle, "regenerate", and a stress button that streams a very long reply with a frame-time readout.

## 9. pub.dev 160-point plan

| Category | Points | How |
|---|---|---|
| Conventions | 30 | Valid pubspec (60–180 char description, `repository`, `issue_tracker`, `topics`), OSI licence, CHANGELOG, README, `example/`, screenshot |
| Documentation | 20 | 100% dartdoc on public API, library docs, an `example/` with README |
| Platforms | 20 | No `dart:io`/`dart:html`; all six platforms detected; WASM-compatible |
| Static analysis | 50 | Zero `flutter analyze` issues (flutter_lints), `dart format` clean |
| Dependencies | 40 | Only `flutter`; up-to-date constraints; supports latest stable SDK |

I will verify locally with `flutter analyze`, `dart format --set-exit-if-changed`, `flutter test`, and `dart pub publish --dry-run` (and `pana` if I can install it).

## 10. Decisions (resolved)

Own lexer for highlighting; repository `https://github.com/AshitaNema/llm_markdown_renderer`; MIT; image placeholder by default; per-item tight/loose and no reference links accepted; language list unchanged. Minimum SDK lowered to `^3.8.0` (the floor required by `flutter_lints` 6).

## 11. Implementation notes: differences from the proposal

* **No `HtmlBlock`.** Raw HTML is rendered as ordinary text, so the AST has no HTML node.
* **AST names** are prefixed to avoid clashing with Flutter: `InlineText`, `InlineStrong`, `ParagraphBlock`, `CodeBlock`, `TableBlock`, ….
* **Block quotes** are re-parsed as a whole while open (cost O(quote)); lists and list items do commit item by item as proposed. Fenced code, tables and lists are the unbounded-size cases and are all append-only / per-item.
* **Partial opening fence:** instead of showing `` ` ``/`` `` `` as paragraph text, short marker-only pending lines (`` ` ``, `#`, `-`, `1.`, `|`, …) are *hidden* until they mean something. This avoids a one-frame flash of stray punctuation.
* **Widget reuse:** Flutter forbids overriding `Widget.==`, so "skip finished blocks" is implemented by caching widget *instances* per block id (`WidgetCache`) and reusing them by identity, with value equality for closed blocks.
* **Block ids** are a counter at top level and `parentId * 31 + index` for nested blocks: unique among siblings, which is all widget keys need, and small enough for JavaScript's 53-bit integers.
* **Highlighter API** is `highlightLine(language, line, state) -> LineHighlight(tokens, endState)`; the built-in engine is `RuleBasedHighlighter`, extensible with `LanguageDefinition`/`LexRule`.
* **Chunk-boundary tests** are exhaustive (every 2-way split, char-by-char against every prefix, random partitions) for each fixture, rather than property-based generation of documents.
