import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ast/block.dart';
import '../highlight/highlighter.dart';
import '../theme/markdown_theme.dart';

/// A code block with a language label, a copy button and syntax highlighting.
///
/// Built for streaming: lines that are finished are tokenized and laid out
/// once and then cached (in chunks of 32 lines), so each new token only
/// touches the last chunk. The copy button copies the raw code, never the
/// highlighted spans.
class CodeBlockView extends StatefulWidget {
  /// Creates a code block view.
  ///
  /// When [theme] is `null` it is resolved with [MarkdownTheme.of].
  const CodeBlockView({
    super.key,
    required this.block,
    this.theme,
    this.highlighter = const CodeHighlighter.defaults(),
  });

  /// The block to display.
  final CodeBlock block;

  /// The theme, or `null` to use the ambient one.
  final MarkdownTheme? theme;

  /// The highlighter used to colour tokens.
  final CodeHighlighter highlighter;

  @override
  State<CodeBlockView> createState() => _CodeBlockViewState();
}

class _CodeBlockViewState extends State<CodeBlockView> {
  static const int _chunkLines = 32;

  final List<List<Token>> _tokens = [];
  final List<Widget> _chunkCache = [];
  Object? _lexState;
  String? _language;
  CodeHighlighter? _highlighter;
  MarkdownTheme? _theme;
  bool _copied = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.block.text));
    if (!mounted) return;
    setState(() => _copied = true);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _reset() {
    _tokens.clear();
    _chunkCache.clear();
    _lexState = null;
  }

  TextSpan _lineSpan(String line, List<Token> tokens, MarkdownTheme theme) {
    final children = <InlineSpan>[];
    var pos = 0;
    for (final t in tokens) {
      final start = t.start.clamp(pos, line.length);
      final end = t.end.clamp(start, line.length);
      if (start > pos) children.add(TextSpan(text: line.substring(pos, start)));
      if (end > start) {
        children.add(
          TextSpan(
            text: line.substring(start, end),
            style: t.kind == TokenKind.plain
                ? null
                : theme.syntaxTheme.styleFor(t.kind),
          ),
        );
      }
      pos = end;
    }
    if (pos < line.length) children.add(TextSpan(text: line.substring(pos)));
    return TextSpan(children: children);
  }

  Widget _buildChunk(int from, int to, MarkdownTheme theme) {
    final b = widget.block;
    final children = <InlineSpan>[];
    for (var i = from; i < to; i++) {
      final tokens = i < _tokens.length
          ? _tokens[i]
          : widget.highlighter
                .highlightLine(b.language, b.lines[i], _lexState)
                .tokens;
      children.add(_lineSpan(b.lines[i], tokens, theme));
      if (i < to - 1) children.add(const TextSpan(text: '\n'));
    }
    return Text.rich(
      TextSpan(style: theme.codeBlockStyle, children: children),
      softWrap: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme ?? MarkdownTheme.of(context);
    final b = widget.block;
    final hl = widget.highlighter;

    if (b.language != _language ||
        hl != _highlighter ||
        theme != _theme ||
        b.lines.length < _tokens.length) {
      _reset();
      _language = b.language;
      _highlighter = hl;
      _theme = theme;
    }
    final stable = b.isOpen ? math.max(0, b.lines.length - 1) : b.lines.length;
    while (_tokens.length < stable) {
      final r = hl.highlightLine(
        b.language,
        b.lines[_tokens.length],
        _lexState,
      );
      _tokens.add(r.tokens);
      _lexState = r.endState;
    }

    final chunks = <Widget>[];
    final full = stable ~/ _chunkLines;
    for (var c = 0; c < full; c++) {
      if (c >= _chunkCache.length) {
        _chunkCache.add(
          _buildChunk(c * _chunkLines, (c + 1) * _chunkLines, theme),
        );
      }
      chunks.add(_chunkCache[c]);
    }
    final tailStart = full * _chunkLines;
    if (tailStart < b.lines.length) {
      chunks.add(_buildChunk(tailStart, b.lines.length, theme));
    } else if (b.lines.isEmpty) {
      chunks.add(Text(' ', style: theme.codeBlockStyle));
    }

    final headerColor = theme.codeBlockHeaderStyle.color;
    final label = b.language ?? (b.isFenced ? 'code' : 'text');
    return Semantics(
      container: true,
      label: 'Code block, $label',
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: theme.codeBlockBackground,
          borderRadius: BorderRadius.circular(theme.codeBlockBorderRadius),
          border: Border.all(color: theme.codeBlockBorderColor),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: theme.codeBlockHeaderBackground,
              padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: theme.codeBlockHeaderStyle,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Material(
                    type: MaterialType.transparency,
                    child: IconButton(
                      onPressed: _copy,
                      tooltip: _copied ? 'Copied' : 'Copy code',
                      iconSize: 16,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      icon: Icon(
                        _copied ? Icons.check : Icons.content_copy_outlined,
                        color: headerColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: theme.codeBlockPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: chunks,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
