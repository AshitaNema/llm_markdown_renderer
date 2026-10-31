import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ast/block.dart';
import '../ast/inline.dart';
import 'inline_renderer.dart';
import 'render_config.dart';

/// Renders a [TableBlock] with column widths that never shrink while the table
/// is streaming, so cells do not jitter as rows arrive.
class MarkdownTableView extends StatefulWidget {
  /// Creates the widget.
  const MarkdownTableView({
    super.key,
    required this.block,
    required this.config,
  });

  /// The table to render.
  final TableBlock block;

  /// Rendering configuration.
  final MarkdownRenderConfig config;

  @override
  State<MarkdownTableView> createState() => _MarkdownTableViewState();
}

class _MarkdownTableViewState extends State<MarkdownTableView> {
  static const double _minColumn = 40;
  static const double _maxColumn = 360;

  List<double> _widths = [];
  Map<List<Inline>, double> _measured = Map.identity();

  double _measure(
    BuildContext context,
    List<Inline> cell,
    TextStyle style,
    Map<List<Inline>, double> next,
  ) {
    if (cell.isEmpty) return 0;
    final known = _measured[cell] ?? next[cell];
    if (known != null) {
      next[cell] = known;
      return known;
    }
    final painter = TextPainter(
      text: TextSpan(
        style: style,
        children: buildInlineSpans(cell, widget.config, context, null),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final w = painter.maxIntrinsicWidth;
    painter.dispose();
    next[cell] = w;
    return w;
  }

  TextAlign _align(TableAlignment a) => switch (a) {
    TableAlignment.none || TableAlignment.left => TextAlign.start,
    TableAlignment.center => TextAlign.center,
    TableAlignment.right => TextAlign.end,
  };

  @override
  Widget build(BuildContext context) {
    final theme = widget.config.theme;
    final b = widget.block;
    final cols = b.alignments.length;
    final pad = theme.tableCellPadding;
    final next = Map<List<Inline>, double>.identity();

    if (_widths.length != cols) {
      _widths = List.filled(cols, _minColumn);
    }
    for (var c = 0; c < cols; c++) {
      var w = _measure(context, b.header[c], theme.tableHeaderStyle, next);
      for (final row in b.rows) {
        w = math.max(w, _measure(context, row[c], theme.bodyStyle, next));
      }
      final target = (w + pad.horizontal + 2).ceilToDouble().clamp(
        _minColumn,
        _maxColumn,
      );
      _widths[c] = math.max(_widths[c], target);
    }
    _measured = next;

    Widget cell(List<Inline> content, TextStyle style, int c) => Padding(
      padding: pad,
      child: InlineRichText(
        children: content,
        style: style,
        config: widget.config,
        textAlign: _align(b.alignments[c]),
      ),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        columnWidths: {
          for (var c = 0; c < cols; c++) c: FixedColumnWidth(_widths[c]),
        },
        border: TableBorder.all(color: theme.tableBorderColor),
        children: [
          TableRow(
            decoration: BoxDecoration(color: theme.tableHeaderBackground),
            children: [
              for (var c = 0; c < cols; c++)
                cell(b.header[c], theme.tableHeaderStyle, c),
            ],
          ),
          for (final row in b.rows)
            TableRow(
              children: [
                for (var c = 0; c < cols; c++) cell(row[c], theme.bodyStyle, c),
              ],
            ),
        ],
      ),
    );
  }
}
