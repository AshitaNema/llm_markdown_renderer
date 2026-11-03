# Architecture

`llm_markdown_renderer` renders Markdown that arrives in small chunks (LLM
tokens) and keeps the cost of each chunk independent of how much text has
already been rendered. This document explains how it does that, which
guarantees it makes, and where the code for each part lives.

## Contents

1. [Layers](#layers)
2. [The incremental parser](#the-incremental-parser)
3. [Stability rules while streaming](#stability-rules-while-streaming)
4. [Cost model](#cost-model)
5. [Rendering](#rendering)
6. [Theming](#theming)
7. [Security and privacy](#security-and-privacy)
8. [Accessibility and right-to-left text](#accessibility-and-right-to-left-text)
9. [Public API surface](#public-api-surface)
10. [Differences from CommonMark](#differences-from-commonmark)
11. [Tests: what each file proves](#tests-what-each-file-proves)
12. [Benchmark](#benchmark)

## Layers

```
 chunk ──► LineBuffer ──► block engine ──► MarkdownDocument ──► widgets
           (complete       (state machine     (committed blocks     (only the open
            lines + one     over lines)        + one open tail)      block rebuilds)
            pending line)
```

Dependencies only point left to right. Everything up to and including
`MarkdownDocument` is plain Dart with no Flutter import, so the parser can run
in an isolate, a test or a Dart script. (The package itself depends on the
Flutter SDK, so a pure-Dart project without Flutter installed cannot depend on
it; splitting the parser into its own package would change that.)

```
lib/
  llm_markdown_renderer.dart        public entry point (Flutter): re-exports parser.dart
  parser.dart                       public entry point (plain Dart)
  src/
    ast/
      block.dart                    sealed Block hierarchy: ParagraphBlock, HeadingBlock,
                                    CodeBlock, BlockQuoteBlock, ListBlock/ListItem,
                                    TableBlock, ThematicBreakBlock
      inline.dart                   sealed Inline hierarchy: InlineText, InlineStrong, …
      document.dart                 MarkdownDocument (immutable snapshot)
      equality.dart                 list equality helper for the value types
    parser/
      line_buffer.dart              chunks -> lines; CR/LF/CRLF and surrogate handling
      block_parser.dart             IncrementalMarkdownParser and the block state machine
      inline_parser.dart            inline syntax, with a streaming-tolerant mode
      options.dart                  MarkdownParserOptions
    highlight/
      highlighter.dart              CodeHighlighter, Token, TokenKind, LineHighlight
      rule_highlighter.dart         RuleBasedHighlighter, LanguageDefinition, LexRule
      languages.dart                the built-in language definitions
    controller/
      markdown_stream_controller.dart   MarkdownStreamController (ChangeNotifier)
    theme/
      markdown_theme.dart           MarkdownTheme (ThemeExtension)
      syntax_theme.dart             SyntaxTheme
    widgets/
      streaming_markdown.dart       StreamingMarkdown (controller / stream / static)
      block_view.dart               BlockColumn, BlockView, list views, WidgetCache
      inline_renderer.dart          Inline AST -> InlineSpan, link safety, text direction
      code_block.dart               CodeBlockView (header, copy button, chunked body)
      table_view.dart               MarkdownTableView (never-shrinking columns)
      render_config.dart            MarkdownRenderConfig and the public typedefs
```

## The incremental parser

### Line assembly

`LineBuffer` turns arbitrary chunks into complete lines and keeps the
unterminated remainder as the *pending line*.

* `\n`, `\r\n` and a lone `\r` all end a line, even when `\r` is the last
  character of one chunk and `\n` the first of the next.
* A high UTF-16 surrogate at the end of a chunk is held back until its low
  half arrives, so a split emoji never produces U+FFFD.

### Block state machine

`IncrementalMarkdownParser` owns a block engine (`_Engine` in
`block_parser.dart`). The engine holds:

* `committed`: finished blocks, append-only and immutable;
* `open`: at most one block that may still change (paragraph, fenced code,
  indented code, block quote, list, table).

Each complete line is fed to the open block, which either absorbs it or closes
(moving to `committed`) and lets the line start a new block. A block is only
committed when later input provably cannot change it: a paragraph on a blank
line or an interrupting block, a fence on its closing fence, a table on a
non-row line, and so on. Because commits depend only on complete lines, the
result does not depend on how the text was chunked.

Containers reuse the same machinery:

* **List items** are committed one at a time. An item is built (and its
  children parsed by a child engine over the de-indented lines) once, when the
  next sibling begins; only the last item is re-parsed per chunk.
* **Block quotes** run a child engine over the stripped lines. An open quote is
  re-parsed as a whole, which is cheap for the short quotes LLMs write.
* **Fenced code** is append-only: lines are never interpreted.
* **Tables** keep their parsed rows; only the row being typed is parsed again.

### The pending line

The text after the last newline is not committed. For every snapshot the engine
clones its *open* state, feeds the pending line to the clone, and renders the
result. This is what lets a heading, list item or table row appear while it is
still being typed, without ever committing a guess.

### Inline parsing

`parseInlines` (in `inline_parser.dart`) implements emphasis with the
CommonMark delimiter-run algorithm, plus code spans, links, images, autolinks,
escapes and entities. With `streaming: true` it treats its input as the growing
end of a document (see the next section). Inline content is parsed per block,
once when the block is committed and once per snapshot for the open block.

### Chunking independence

The central invariant, enforced by the tests:

> For every partition of an input into chunks, the document after appending all
> chunks equals the document from appending the input in one piece, and at
> every intermediate point it equals the one-shot parse of the prefix received
> so far.

## Stability rules while streaming

Everything the user sees while text is still arriving follows these rules, so
that nothing flashes and later text never has to "undo" what was painted.

| Situation | Behavior |
|---|---|
| Opening fence (```` ``` ````) | The code block shell (header, copy button) appears when the third backtick arrives. `` ` `` and ```` `` ```` are hidden. |
| Unclosed fence | Rendered as an open block; lines only ever append. A partial closing fence on the last line is never painted as code. |
| Table header only | A paragraph, until the delimiter row (`|---|`) arrives. A partial delimiter row is hidden. |
| Partial table row | A full-width row; missing cells are empty. Column widths never shrink. |
| `**bold`, `*em`, `~~x`, `` `code `` | Speculatively closed at the end of the block, so styled text appears immediately. A trailing delimiter run (`**`) is hidden. |
| `[label](http://ex` | Only the label is shown; it becomes a link when `)` arrives. An incomplete image is hidden. |
| A marker-only pending line (`-`, `1.`, `#`, `>`, `|`, …) | Hidden until it has content. |
| `snake_case_word` | Never treated as emphasis. |

When the stream is completed (`complete()`), speculative constructs that never
closed become literal text, exactly as in a one-shot parse.

## Cost model

For one `append(chunk)`:

* lines completed by the chunk are processed once: O(chunk);
* the open block's inline content is parsed again: O(open block);
* committed blocks are untouched and keep their object identity;
* reading `document` copies the list of block references: O(blocks), a pointer
  copy with no parsing.

For one frame, `StreamingMarkdown` rebuilds only blocks whose object changed
(see below). The [benchmark](#benchmark) measures the parser side.

## Rendering

### Skipping finished blocks

Flutter does not allow overriding `Widget.==`, so finished blocks are skipped
by *reusing widget instances*. `BlockColumn` keeps a `WidgetCache` keyed by
`Block.id`; a cached widget is reused when the block is the same object (or an
equal, closed block) and the configuration is unchanged. Flutter short-circuits
on identical widgets, so a finished block costs nothing per frame.

`Block.id` is a counter at the top level and `parentId * 31 + index` for nested
blocks. It only has to be unique among siblings (it is a widget key), and it
stays small enough for JavaScript's 53-bit integers.

### Notification coalescing

`MarkdownStreamController.append` parses synchronously (so `document` is always
current) but notifies listeners at most once per frame, through
`SchedulerBinding.scheduleFrameCallback`. Two hundred tokens per second cost one
rebuild per frame.

### Code blocks

`CodeBlockView` keeps, per block: the token lists of finished lines, the
highlighter's carried state, and a cache of laid-out chunks of 32 lines. A new
token touches only the last chunk; the last line is re-highlighted on every
frame because it is still growing. The copy button copies the raw text.

Highlighting goes through `CodeHighlighter.highlightLine(language, line,
state)`, which returns tokens and an opaque end state. `RuleBasedHighlighter`
implements it with small regular-expression lexers (`LanguageDefinition`,
`LexRule`), including states for multi-line comments and strings.

### Tables

`MarkdownTableView` uses Flutter's `Table` with a custom `TableColumnWidth`
(`_GrowingColumnWidth`) that delegates to `IntrinsicColumnWidth` and remembers
the widest value ever returned, capped at 360 logical pixels. Column widths are
computed by Flutter's own layout, so they match the text exactly for any font
or theme, and they cannot shrink while rows stream in.

## Theming

`MarkdownTheme` is a `ThemeExtension`. `StreamingMarkdown` resolves it in this
order:

1. the `theme:` argument;
2. `Theme.of(context).extension<MarkdownTheme>()`;
3. `MarkdownTheme.fromTheme(Theme.of(context))`.

`SyntaxTheme` maps `TokenKind` to `TextStyle` and ships light and dark presets.

## Security and privacy

* Links are always styled, but only `http`, `https`, `mailto`, `tel` and
  scheme-less (relative) URLs are tappable. `javascript:`, `data:`, `file:` and
  other schemes are rendered as text and never reported. The package never
  launches a URL; `onTapLink` is the application's decision.
* Images are not fetched by default, because model output can point anywhere.
  A placeholder with the alt text is shown unless the application supplies an
  `imageBuilder`.
* Raw HTML is never interpreted; it is shown as text.

## Accessibility and right-to-left text

* Headings are marked as semantic headers.
* Lists expose `SemanticsRole.list` and `SemanticsRole.listItem`.
* Code blocks are labelled `Code block, <language>`; the copy button has a
  tooltip. Task-list checkboxes have a checked/unchecked label.
* Tables have no semantics roles: Flutter requires a table's children to carry
  a `row` role, and `Table` offers no way to attach one to a `TableRow`.
* Text direction is detected per paragraph, heading and table cell with the
  Unicode "first strong character" rule, so Arabic or Hebrew text lays out
  right-to-left even in a left-to-right app (and the reverse). List markers and
  block-quote bars use directional geometry and mirror in right-to-left
  contexts. Code is always left-to-right.
* Large text scale factors are covered by tests for headings, lists, quotes,
  code and tables.

## Public API surface

Exported from `package:llm_markdown_renderer/llm_markdown_renderer.dart`:

* widgets and controller: `StreamingMarkdown`, `MarkdownStreamController`,
  `CodeBlockView`;
* theming: `MarkdownTheme`, `SyntaxTheme`;
* callbacks: `MarkdownLinkCallback`, `MarkdownImageBuilder`,
  `MarkdownCodeBlockBuilder`;
* everything in `parser.dart`.

Exported from `package:llm_markdown_renderer/parser.dart` (no Flutter):

* `IncrementalMarkdownParser`, `MarkdownParserOptions`, `MarkdownDocument`;
* the `Block` and `Inline` hierarchies;
* the highlighting types: `CodeHighlighter`, `RuleBasedHighlighter`,
  `LanguageDefinition`, `LexRule`, `Token`, `TokenKind`, `LineHighlight`.

Deliberately internal: `LineBuffer`, `parseInlines`, `isSafeLinkUrl`,
`MarkdownRenderConfig`, `BlockView`, `BlockColumn`, `WidgetCache`,
`MarkdownTableView`, `InlineRichText`. Every exported symbol is something the
package has to keep stable, so the surface is kept small.

## Differences from CommonMark

The parser covers what LLMs emit, not the whole specification. Deliberate
differences, made so that every append stays cheap:

* Tight and loose are decided **per list item**, not per list.
* Reference-style links (`[x][ref]`) and raw HTML are not supported.
* Math (`$…$`) is not rendered.
* A list item under `1.` indented by only two spaces is treated as nested,
  because that is what models intend.
* A list ends at a blank line followed by unindented text; setext headings and
  tables are recognized without requiring a preceding blank line.

## Tests: what each file proves

| File | Proves |
|---|---|
| `test/parser/chunk_boundary_test.dart` | Chunking independence for 20 fixtures: every 2-way split, one character at a time against every prefix, and random partitions all equal the one-shot parse. Plus CRLF/CR splits, surrogate pairs, fence and table-row splits, `complete()` mid-construct. |
| `test/parser/incremental_test.dart` | Only the open block is parsed: per-append inline-parse count is the same for 10 and 1,500 paragraphs, committed blocks and list items keep identity, huge code blocks and tables are not re-parsed, plus a coarse bound against quadratic behavior. |
| `test/parser/block_test.dart` | Block recognition and the streaming previews: headings, fences, lists (nesting, tasks, loose/tight), quotes, tables, hidden partial markers. |
| `test/parser/inline_test.dart` | Inline syntax and the streaming mode (speculative closing, hidden partial links and delimiters). |
| `test/parser/line_buffer_test.dart` | Line splitting, CR/LF handling across chunks, surrogate hold-back. |
| `test/highlight/highlighter_test.dart` | Every built-in language yields ordered, in-range tokens; multi-line state carries across lines; incremental equals one-shot; custom languages. |
| `test/controller_test.dart` | Controller semantics, per-frame notification coalescing, disposal safety. |
| `test/widgets/streaming_markdown_test.dart` | The three constructors, finished blocks are not rebuilt, link safety, image placeholders, theme resolution order, table columns never shrink and never wrap mid-word (with real Roboto), stream errors, robustness while streaming. |
| `test/widgets/code_block_test.dart` | Copy button and feedback, theme colors, language changes, chunked rendering of long blocks, custom builder. |
| `test/widgets/accessibility_test.dart` | Semantics roles and labels, RTL layout and mirroring, large text scales. |
| `test/golden/streaming_golden_test.dart` | A mid-stream snapshot (open fence, table, list) in light and dark, against `test/golden/goldens/*.png`. Rendered with the default test font so layout is identical everywhere, and compared with a 2% pixel tolerance because the rasterizer anti-aliases edges slightly differently per operating system (a changed layout, color or missing widget moves far more pixels; a size change always fails). Regenerate with `flutter test --update-goldens test/golden`. |

## Benchmark

`benchmark/append_cost.dart` compares the cost of one streamed chunk with the
cost of re-parsing the whole text, for documents from 40 to 40,000 blocks:

```sh
dart run benchmark/append_cost.dart
```

Results are in the README.
