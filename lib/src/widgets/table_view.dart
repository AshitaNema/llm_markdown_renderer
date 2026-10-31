import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ast/block.dart';
import '../ast/inline.dart';
import 'inline_renderer.dart';
import 'render_config.dart';

/// The widest a column may grow before its text wraps.
const double _maxColumnWidth = 360;

/// The narrowest a column is laid out.
const double _minColumnWidth = 40;

/// Remembers the widest size a column has ever needed.
class _ColumnMemory {
  double width = 0;
}

/// A column that is as wide as its widest cell (like [IntrinsicColumnWidth])
/// but never shrinks.
///
/// While a table streams in, a plain intrinsic column can get *narrower* when
/// a cell is replaced by a shorter version of itself, which makes the whole
/// table jitter. The widths are computed by Flutter's own layout, so they are
/// exactly what the text needs, whatever the theme or font.
class _GrowingColumnWidth extends TableColumnWidth {
  const _GrowingColumnWidth(this.memory);

  final _ColumnMemory memory;

  static const IntrinsicColumnWidth _intrinsic = IntrinsicColumnWidth();

  @override
  double maxIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) {
    final needed = _intrinsic
        .maxIntrinsicWidth(cells, containerWidth)
        .clamp(_minColumnWidth, _maxColumnWidth);
    memory.width = math.max(memory.width, needed);
    return memory.width;
  }

  @override
  double minIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) =>
      maxIntrinsicWidth(cells, containerWidth);
}

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
  List<_ColumnMemory> _memory = [];

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
    if (_memory.length != cols) {
      _memory = List.generate(cols, (_) => _ColumnMemory());
    }

    Widget cell(List<Inline> content, TextStyle style, int c) => Padding(
      padding: theme.tableCellPadding,
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
          for (var c = 0; c < cols; c++) c: _GrowingColumnWidth(_memory[c]),
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
