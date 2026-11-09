import 'package:flutter/widgets.dart';

import '../ast/block.dart';
import '../ast/inline.dart';
import '../highlight/highlighter.dart';
import '../theme/markdown_theme.dart';

/// Called when the user taps a link.
///
/// [url] is the raw destination and [title] the optional link title. The
/// package never launches URLs itself; open them with your preferred plugin.
typedef MarkdownLinkCallback = void Function(String url, String? title);

/// Builds the widget shown for an image `![alt](url "title")`.
///
/// By default images are *not* fetched; a placeholder with the alt text is
/// shown instead. Supply a builder to opt in:
///
/// ```dart
/// imageBuilder: (context, image, style) =>
///     Image.network(image.url, semanticLabel: image.alt),
/// ```
///
/// [style] is the text style around the image (a widget inside text does
/// not inherit it).
typedef MarkdownImageBuilder =
    Widget Function(BuildContext context, InlineImage image, TextStyle style);

/// Builds a custom widget for a code block, replacing `CodeBlockView`.
///
/// Return `null` to use the default view for this block, so you can take
/// over only some languages:
///
/// ```dart
/// codeBlockBuilder: (context, block) =>
///     block.language == 'mermaid' ? MermaidView(block.text) : null,
/// ```
typedef MarkdownCodeBlockBuilder =
    Widget? Function(BuildContext context, CodeBlock block);

/// Builds the widget for a `<think>…</think>` section.
///
/// [content] is the section's Markdown, already rendered; wrap it in your own
/// chrome (a card, an `ExpansionTile`, a "Thought for 12s" header). Check
/// [ThinkingBlock.isOpen] to tell whether the model is still thinking. By
/// default a collapsible section is shown that is expanded while the model
/// thinks and collapses when the section closes (at `</think>`, or when the
/// stream ends). Its header labels are English ("Thinking…", "Thoughts");
/// supply this builder to localize them.
typedef MarkdownThinkingBuilder =
    Widget Function(BuildContext context, ThinkingBlock block, Widget content);

/// Builds the widget for a citation marker such as `[1]` or `[1, 2]`.
///
/// [InlineCitation.labels] are the cited labels (`['1', '2']`) and
/// [InlineCitation.source] the marker as written. The widget is placed inline
/// with the text, so keep it small (a superscript chip, for example); [style]
/// is the text style around it.
typedef MarkdownCitationBuilder =
    Widget Function(
      BuildContext context,
      InlineCitation citation,
      TextStyle style,
    );

/// Called when the user taps one label of a citation marker.
typedef MarkdownCitationCallback = void Function(String label);

/// Builds the widget for LaTeX math, usually with a math typesetting package.
///
/// [InlineMath.tex] is the TeX source without its delimiters, and
/// [InlineMath.display] is `true` for display math (`$$…$$`, a `MathBlock`)
/// and `false` for inline math (`$…$`, `\(…\)`). For a `MathBlock` the
/// builder gets `InlineMath(block.tex, display: true)`. [style] is the text
/// style around the math, so inline math in a heading can match its size.
/// For example, with `flutter_math_fork`:
///
/// ```dart
/// mathBuilder: (context, math, style) => Math.tex(
///   math.tex,
///   mathStyle: math.display ? MathStyle.display : MathStyle.text,
///   textStyle: style,
///   onErrorFallback: (error) => Text(math.tex, style: style),
/// ),
/// ```
///
/// It is only called for complete math. While the closing delimiter has not
/// arrived yet, the TeX source is shown in the code style instead, so the
/// builder never sees half-written TeX such as `\frac{a}{`.
typedef MarkdownMathBuilder =
    Widget Function(BuildContext context, InlineMath math, TextStyle style);

/// Everything the block widgets need to render; compared by identity so that
/// finished blocks are not rebuilt unless the configuration really changes.
class MarkdownRenderConfig {
  /// Creates a configuration.
  const MarkdownRenderConfig({
    required this.theme,
    required this.highlighter,
    this.onTapLink,
    this.imageBuilder,
    this.codeBlockBuilder,
    this.mathBuilder,
    this.thinkingBuilder,
    this.citationBuilder,
    this.onTapCitation,
  });

  /// The resolved theme.
  final MarkdownTheme theme;

  /// The code highlighter.
  final CodeHighlighter highlighter;

  /// Link tap handler.
  final MarkdownLinkCallback? onTapLink;

  /// Image builder.
  final MarkdownImageBuilder? imageBuilder;

  /// Code block builder.
  final MarkdownCodeBlockBuilder? codeBlockBuilder;

  /// Math builder.
  final MarkdownMathBuilder? mathBuilder;

  /// Thinking section builder.
  final MarkdownThinkingBuilder? thinkingBuilder;

  /// Citation builder.
  final MarkdownCitationBuilder? citationBuilder;

  /// Citation tap handler.
  final MarkdownCitationCallback? onTapCitation;
}
