/// Render Markdown streamed token by token from an LLM without jank.
///
/// * [StreamingMarkdown] is the widget; feed it with a
///   [MarkdownStreamController] (`append(chunk)`) or a `Stream<String>`.
/// * [IncrementalMarkdownParser] is the parser underneath (no Flutter
///   imports, so it also runs in isolates). Only the block that is still
///   being written is re-parsed for each chunk.
/// * [MarkdownTheme] (a `ThemeExtension`) and [SyntaxTheme] style the output.
/// * [CodeBlockView] is the highlighted code block with a copy button;
///   [CodeHighlighter] lets you swap the highlighting engine.
///
/// ```dart
/// final controller = MarkdownStreamController();
/// tokens.listen(controller.append, onDone: controller.complete);
///
/// StreamingMarkdown(controller: controller);
/// ```
library;

export 'parser.dart';
export 'src/controller/markdown_stream_controller.dart';
export 'src/theme/markdown_theme.dart';
export 'src/theme/syntax_theme.dart';
export 'src/widgets/code_block.dart' show CodeBlockView;
export 'src/widgets/render_config.dart'
    show
        MarkdownCitationBuilder,
        MarkdownCitationCallback,
        MarkdownCodeBlockBuilder,
        MarkdownImageBuilder,
        MarkdownLinkCallback,
        MarkdownMathBuilder,
        MarkdownThinkingBuilder;
export 'src/widgets/streaming_markdown.dart';
