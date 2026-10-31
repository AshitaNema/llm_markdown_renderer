import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../ast/inline.dart';
import 'render_config.dart';

/// Whether tapping a link to [url] is allowed.
///
/// Only `http`, `https`, `mailto`, `tel` and scheme-less (relative) URLs are
/// interactive; anything else (`javascript:`, `data:`, `file:` …) is shown
/// as styled text and never reported to the app.
bool isSafeLinkUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return false;
  if (!uri.hasScheme) return true;
  return const {
    'http',
    'https',
    'mailto',
    'tel',
  }.contains(uri.scheme.toLowerCase());
}

/// Converts inline nodes to spans. Gesture recognizers created for links are
/// added to [recognizers] (which the caller must dispose); pass `null` to
/// build a non-interactive span, e.g. for measuring.
List<InlineSpan> buildInlineSpans(
  List<Inline> nodes,
  MarkdownRenderConfig config,
  BuildContext context,
  List<GestureRecognizer>? recognizers,
) {
  final theme = config.theme;
  final out = <InlineSpan>[];
  for (final node in nodes) {
    switch (node) {
      case InlineText(:final text):
        out.add(TextSpan(text: text));
      case InlineEmphasis(:final children):
        out.add(
          TextSpan(
            style: const TextStyle(fontStyle: FontStyle.italic),
            children: buildInlineSpans(children, config, context, recognizers),
          ),
        );
      case InlineStrong(:final children):
        out.add(
          TextSpan(
            style: const TextStyle(fontWeight: FontWeight.bold),
            children: buildInlineSpans(children, config, context, recognizers),
          ),
        );
      case InlineStrikethrough(:final children):
        out.add(
          TextSpan(
            style: const TextStyle(decoration: TextDecoration.lineThrough),
            children: buildInlineSpans(children, config, context, recognizers),
          ),
        );
      case InlineCode(:final code):
        out.add(TextSpan(text: code, style: theme.inlineCodeStyle));
      case InlineLink(:final url, :final title, :final children):
        GestureRecognizer? recognizer;
        final tap = config.onTapLink;
        if (recognizers != null && tap != null && isSafeLinkUrl(url)) {
          recognizer = TapGestureRecognizer()..onTap = () => tap(url, title);
          recognizers.add(recognizer);
        }
        out.add(
          TextSpan(
            style: theme.linkStyle,
            recognizer: recognizer,
            mouseCursor: recognizer == null ? null : SystemMouseCursors.click,
            children: buildInlineSpans(children, config, context, recognizers),
          ),
        );
      case InlineImage(:final url, :final alt):
        final builder = config.imageBuilder;
        if (builder != null) {
          out.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: builder(context, url, alt),
            ),
          );
        } else {
          final size = theme.bodyStyle.fontSize ?? 14;
          out.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Icon(Icons.image_outlined, size: size * 1.1),
            ),
          );
          out.add(TextSpan(text: alt.isEmpty ? ' image' : ' $alt'));
        }
      case InlineLineBreak():
        out.add(const TextSpan(text: '\n'));
      case InlineSoftBreak():
        out.add(const TextSpan(text: ' '));
    }
  }
  return out;
}

/// Renders inline Markdown content as a single [Text.rich].
class InlineRichText extends StatefulWidget {
  /// Creates the widget.
  const InlineRichText({
    super.key,
    required this.children,
    required this.style,
    required this.config,
    this.textAlign = TextAlign.start,
  });

  /// The inline nodes.
  final List<Inline> children;

  /// The base text style.
  final TextStyle style;

  /// Rendering configuration.
  final MarkdownRenderConfig config;

  /// Horizontal text alignment.
  final TextAlign textAlign;

  @override
  State<InlineRichText> createState() => _InlineRichTextState();
}

class _InlineRichTextState extends State<InlineRichText> {
  List<GestureRecognizer> _recognizers = [];

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers = [];
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.children.isEmpty) return const SizedBox.shrink();
    _disposeRecognizers();
    final spans = buildInlineSpans(
      widget.children,
      widget.config,
      context,
      _recognizers,
    );
    return Text.rich(
      TextSpan(style: widget.style, children: spans),
      textAlign: widget.textAlign,
    );
  }
}
