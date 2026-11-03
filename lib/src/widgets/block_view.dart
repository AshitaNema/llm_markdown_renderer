import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import '../ast/block.dart';
import 'code_block.dart';
import 'inline_renderer.dart';
import 'render_config.dart';
import 'table_view.dart';

/// Remembers the widget built for each child so unchanged children can be
/// reused *by identity*, which makes Flutter skip them entirely.
///
/// Flutter forbids overriding `Widget.==`, so this is how finished blocks
/// avoid being rebuilt while the block after them is streaming.
class WidgetCache {
  Map<int, _CacheEntry> _prev = {};
  Map<int, _CacheEntry> _next = {};

  /// Returns the cached widget for [id] if [value] is the same object (or,
  /// when [closed], an equal one) and [deps] are unchanged; otherwise calls
  /// [build].
  Widget obtain({
    required int id,
    required Object value,
    required bool closed,
    required List<Object?> deps,
    required Widget Function() build,
  }) {
    final e = _prev[id];
    final Widget widget;
    if (e != null &&
        _sameDeps(e.deps, deps) &&
        (identical(e.value, value) ||
            (closed && e.closed && e.value == value))) {
      widget = e.widget;
    } else {
      widget = build();
    }
    _next[id] = _CacheEntry(value, closed, deps, widget);
    return widget;
  }

  /// Ends a build pass: entries not requested during it are dropped.
  void endPass() {
    _prev = _next;
    _next = {};
  }

  static bool _sameDeps(List<Object?> a, List<Object?> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _CacheEntry {
  _CacheEntry(this.value, this.closed, this.deps, this.widget);
  final Object value;
  final bool closed;
  final List<Object?> deps;
  final Widget widget;
}

/// A vertical stack of blocks separated by [gap].
class BlockColumn extends StatefulWidget {
  /// Creates the column.
  const BlockColumn({
    super.key,
    required this.blocks,
    required this.config,
    required this.textStyle,
    required this.gap,
  });

  /// The blocks to show.
  final List<Block> blocks;

  /// Rendering configuration.
  final MarkdownRenderConfig config;

  /// The paragraph text style.
  final TextStyle textStyle;

  /// Vertical space between blocks.
  final double gap;

  @override
  State<BlockColumn> createState() => _BlockColumnState();
}

class _BlockColumnState extends State<BlockColumn> {
  final WidgetCache _cache = WidgetCache();

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final children = <Widget>[
      for (var i = 0; i < w.blocks.length; i++)
        _cache.obtain(
          id: w.blocks[i].id,
          value: w.blocks[i],
          closed: !w.blocks[i].isOpen,
          deps: [w.config, w.textStyle, i == 0 ? 0.0 : w.gap],
          build: () => BlockView(
            key: ValueKey(w.blocks[i].id),
            block: w.blocks[i],
            config: w.config,
            textStyle: w.textStyle,
            topGap: i == 0 ? 0 : w.gap,
          ),
        ),
    ];
    _cache.endPass();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

/// Renders one [Block].
///
/// Instances are cached by [BlockColumn], so finished blocks are not rebuilt.
class BlockView extends StatelessWidget {
  /// Creates a view for [block].
  const BlockView({
    super.key,
    required this.block,
    required this.config,
    required this.textStyle,
    required this.topGap,
  });

  /// The block to render.
  final Block block;

  /// Rendering configuration.
  final MarkdownRenderConfig config;

  /// The paragraph text style (differs inside block quotes).
  final TextStyle textStyle;

  /// Space above the block.
  final double topGap;

  @override
  Widget build(BuildContext context) {
    final theme = config.theme;
    final content = switch (block) {
      ParagraphBlock(:final children) => InlineRichText(
        children: children,
        style: textStyle,
        config: config,
      ),
      HeadingBlock(:final level, :final children) => Semantics(
        header: true,
        child: InlineRichText(
          children: children,
          style: theme.headingStyle(level),
          config: config,
        ),
      ),
      final CodeBlock code =>
        config.codeBlockBuilder?.call(context, code) ??
            CodeBlockView(
              block: code,
              theme: theme,
              highlighter: config.highlighter,
            ),
      BlockQuoteBlock(:final children) => Container(
        padding: const EdgeInsetsDirectional.only(start: 12),
        decoration: BoxDecoration(
          border: BorderDirectional(
            start: BorderSide(
              color: theme.blockquoteBarColor,
              width: theme.blockquoteBarWidth,
            ),
          ),
        ),
        child: BlockColumn(
          blocks: children,
          config: config,
          textStyle: theme.blockquoteStyle,
          gap: theme.blockSpacing,
        ),
      ),
      final ListBlock list => _ListView(
        list: list,
        config: config,
        textStyle: textStyle,
      ),
      final TableBlock table => MarkdownTableView(block: table, config: config),
      final MathBlock math => _MathBlockView(block: math, config: config),
      ThematicBreakBlock() => Container(
        height: theme.dividerThickness,
        margin: EdgeInsets.symmetric(vertical: theme.blockSpacing / 2),
        color: theme.dividerColor,
      ),
    };
    return Padding(
      padding: EdgeInsets.only(top: topGap),
      child: RepaintBoundary(child: content),
    );
  }
}

/// Display math: typeset by [MarkdownRenderConfig.mathBuilder] and centered,
/// or, without a builder or while still open, the TeX source in a code box.
/// Wide content scrolls horizontally instead of overflowing.
class _MathBlockView extends StatelessWidget {
  const _MathBlockView({required this.block, required this.config});

  final MathBlock block;
  final MarkdownRenderConfig config;

  @override
  Widget build(BuildContext context) {
    final builder = config.mathBuilder;
    if (builder != null && !block.isOpen) {
      return Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: builder(context, block.tex, true),
        ),
      );
    }
    final theme = config.theme;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        padding: theme.codeBlockPadding,
        decoration: BoxDecoration(
          color: theme.codeBlockBackground,
          border: Border.all(color: theme.codeBlockBorderColor),
          borderRadius: BorderRadius.circular(theme.codeBlockBorderRadius),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Text(block.tex, style: theme.codeBlockStyle),
        ),
      ),
    );
  }
}

class _ListView extends StatefulWidget {
  const _ListView({
    required this.list,
    required this.config,
    required this.textStyle,
  });

  final ListBlock list;
  final MarkdownRenderConfig config;
  final TextStyle textStyle;

  @override
  State<_ListView> createState() => _ListViewState();
}

class _ListViewState extends State<_ListView> {
  final WidgetCache _cache = WidgetCache();

  @override
  Widget build(BuildContext context) {
    final list = widget.list;
    final config = widget.config;
    final theme = config.theme;
    final children = <Widget>[
      for (var i = 0; i < list.items.length; i++)
        _cache.obtain(
          id: list.items[i].id,
          value: list.items[i],
          closed: !list.items[i].isOpen,
          deps: [
            config,
            widget.textStyle,
            list.ordered ? list.start + i : -1,
            i == 0
                ? 0.0
                : (list.items[i].isLoose || list.items[i - 1].isLoose
                      ? theme.blockSpacing
                      : theme.listItemSpacing),
          ],
          build: () => Padding(
            key: ValueKey(list.items[i].id),
            padding: EdgeInsets.only(
              top: i == 0
                  ? 0
                  : (list.items[i].isLoose || list.items[i - 1].isLoose
                        ? theme.blockSpacing
                        : theme.listItemSpacing),
            ),
            child: _ListItemView(
              item: list.items[i],
              marker: list.ordered ? '${list.start + i}.' : '\u2022',
              config: config,
              textStyle: widget.textStyle,
            ),
          ),
        ),
    ];
    _cache.endPass();
    return Semantics(
      role: SemanticsRole.list,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _ListItemView extends StatelessWidget {
  const _ListItemView({
    required this.item,
    required this.marker,
    required this.config,
    required this.textStyle,
  });

  final ListItem item;
  final String marker;
  final MarkdownRenderConfig config;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    final theme = config.theme;
    final checked = item.checked;
    final size = (textStyle.fontSize ?? 14) * 1.2;
    final Widget markerWidget = checked == null
        ? Text(
            marker,
            style: textStyle,
            softWrap: false,
            overflow: TextOverflow.visible,
          )
        : Icon(
            checked ? Icons.check_box : Icons.check_box_outline_blank,
            size: size,
            color: textStyle.color,
            semanticLabel: checked ? 'Checked' : 'Unchecked',
          );
    return Semantics(
      role: SemanticsRole.listItem,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: theme.listIndent,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: Align(
                alignment: AlignmentDirectional.topEnd,
                child: markerWidget,
              ),
            ),
          ),
          Expanded(
            child: BlockColumn(
              blocks: item.children,
              config: config,
              textStyle: textStyle,
              gap: item.isLoose ? theme.blockSpacing : theme.listItemSpacing,
            ),
          ),
        ],
      ),
    );
  }
}
