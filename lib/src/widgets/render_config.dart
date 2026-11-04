import 'package:flutter/widgets.dart';

import '../ast/block.dart';
import '../highlight/highlighter.dart';
import '../theme/markdown_theme.dart';

/// Called when the user taps a link.
///
/// [url] is the raw destination and [title] the optional link title. The
/// package never launches URLs itself; open them with your preferred plugin.
typedef MarkdownLinkCallback = void Function(String url, String? title);

/// Builds the widget shown for an image `![alt](url)`.
///
/// By default images are *not* fetched; a placeholder with the alt text is
/// shown instead. Supply a builder (for example returning `Image.network`)
/// to opt in.
typedef MarkdownImageBuilder =
    Widget Function(BuildContext context, String url, String alt);

/// Builds a custom widget for a code block, replacing `CodeBlockView`.
typedef MarkdownCodeBlockBuilder =
    Widget Function(BuildContext context, CodeBlock block);

/// Builds the widget for LaTeX math, usually with a math typesetting package.
///
/// [tex] is the TeX source without its delimiters; [display] is `true` for
/// display math (`$$…$$`, `\[…\]`) and `false` for inline math (`$…$`,
/// `\(…\)`). For example, with `flutter_math_fork`:
///
/// ```dart
/// mathBuilder: (context, tex, display) => Math.tex(
///   tex,
///   mathStyle: display ? MathStyle.display : MathStyle.text,
///   onErrorFallback: (error) => Text(tex),
/// ),
/// ```
///
/// It is only called for complete math. While the closing delimiter has not
/// arrived yet, the TeX source is shown in the code style instead, so the
/// builder never sees half-written TeX such as `\frac{a}{`.
typedef MarkdownMathBuilder =
    Widget Function(BuildContext context, String tex, bool display);

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
}
