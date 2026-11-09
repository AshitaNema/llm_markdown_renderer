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
///
/// [style] is the resolved text style around [nodes]; it is passed on to the
/// builders of widget spans (math, images, citations), which do not inherit
/// the span styles.
List<InlineSpan> buildInlineSpans(
  List<Inline> nodes,
  MarkdownRenderConfig config,
  BuildContext context,
  List<GestureRecognizer>? recognizers, {
  TextStyle style = const TextStyle(),
}) {
  List<InlineSpan> nested(List<Inline> children, TextStyle inner) =>
      buildInlineSpans(
        children,
        config,
        context,
        recognizers,
        style: style.merge(inner),
      );

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
            children: nested(
              children,
              const TextStyle(fontStyle: FontStyle.italic),
            ),
          ),
        );
      case InlineStrong(:final children):
        out.add(
          TextSpan(
            style: const TextStyle(fontWeight: FontWeight.bold),
            children: nested(
              children,
              const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        );
      case InlineStrikethrough(:final children):
        out.add(
          TextSpan(
            style: const TextStyle(decoration: TextDecoration.lineThrough),
            children: nested(
              children,
              const TextStyle(decoration: TextDecoration.lineThrough),
            ),
          ),
        );
      case InlineCode(:final code):
        out.add(TextSpan(text: code, style: theme.inlineCodeStyle));
      case final InlineCitation cite:
        out.add(_citationSpan(cite, config, context, recognizers, style));
      case final InlineMath math:
        final builder = config.mathBuilder;
        if (builder == null || math.isOpen) {
          out.add(TextSpan(text: math.tex, style: theme.inlineCodeStyle));
        } else {
          // Scrolls (rather than overflowing) if wider than the line.
          out.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: builder(context, math, style),
              ),
            ),
          );
        }
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
            children: nested(children, theme.linkStyle),
          ),
        );
      case final InlineImage image:
        final alt = image.alt;
        final builder = config.imageBuilder;
        if (builder != null) {
          out.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: builder(context, image, style),
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

InlineSpan _citationSpan(
  InlineCitation cite,
  MarkdownRenderConfig config,
  BuildContext context,
  List<GestureRecognizer>? recognizers,
  TextStyle style,
) {
  final labels = cite.labels;
  final builder = config.citationBuilder;
  if (builder != null) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: builder(context, cite, style),
    );
  }
  final tap = config.onTapCitation;
  if (tap == null || recognizers == null) {
    return TextSpan(text: cite.source);
  }
  final children = <InlineSpan>[const TextSpan(text: '[')];
  for (var k = 0; k < labels.length; k++) {
    final label = labels[k];
    final recognizer = TapGestureRecognizer()..onTap = () => tap(label);
    recognizers.add(recognizer);
    children.addAll([
      if (k > 0) const TextSpan(text: ', '),
      TextSpan(
        text: label,
        style: config.theme.linkStyle,
        recognizer: recognizer,
        mouseCursor: SystemMouseCursors.click,
      ),
    ]);
  }
  children.add(const TextSpan(text: ']'));
  return TextSpan(children: children);
}

bool _isRtlLetter(int c) =>
    (c >= 0x0590 && c <= 0x08FF) ||
    (c >= 0xFB1D && c <= 0xFDFF) ||
    (c >= 0xFE70 && c <= 0xFEFF) ||
    (c >= 0x10800 && c <= 0x10FFF) ||
    (c >= 0x1E800 && c <= 0x1EFFF);

bool _isLtrLetter(int c) =>
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x61 && c <= 0x7A) ||
    (c >= 0xC0 && c <= 0x58F) ||
    (c >= 0x900 && c <= 0x1FFF) ||
    (c >= 0x3040 && c <= 0xFB1C);

/// The direction implied by the first strong character of [nodes]
/// (the Unicode "first strong" heuristic), or `null` when there is none.
///
/// This lets a right-to-left paragraph (Arabic, Hebrew, …) be laid out and
/// aligned right-to-left even inside an otherwise left-to-right app, which is
/// common in LLM chat where the model answers in the user's language.
TextDirection? detectTextDirection(List<Inline> nodes) {
  TextDirection? found;
  bool scan(String text) {
    for (final c in text.runes) {
      if (_isRtlLetter(c)) {
        found = TextDirection.rtl;
        return true;
      }
      if (_isLtrLetter(c)) {
        found = TextDirection.ltr;
        return true;
      }
    }
    return false;
  }

  bool walk(List<Inline> list) {
    for (final node in list) {
      final done = switch (node) {
        InlineText(:final text) => scan(text),
        InlineCode() || InlineMath() || InlineCitation() => false,
        InlineEmphasis(:final children) ||
        InlineStrong(:final children) ||
        InlineStrikethrough(:final children) ||
        InlineLink(:final children) => walk(children),
        InlineImage(:final alt) => scan(alt),
        InlineLineBreak() || InlineSoftBreak() => false,
      };
      if (done) return true;
    }
    return false;
  }

  walk(nodes);
  return found;
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
      style: DefaultTextStyle.of(context).style.merge(widget.style),
    );
    final text = Text.rich(
      TextSpan(style: widget.style, children: spans),
      textAlign: widget.textAlign,
    );
    final direction = detectTextDirection(widget.children);
    if (direction == null || direction == Directionality.of(context)) {
      return text;
    }
    return Directionality(textDirection: direction, child: text);
  }
}
