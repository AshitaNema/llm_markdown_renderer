import 'equality.dart';
import 'inline.dart';

/// A block-level Markdown node.
///
/// Blocks are immutable and have value equality (ignoring [id]). While a
/// document is streaming, at most one top-level block is *open*
/// ([isOpen] is `true`): it may still change on the next chunk. Every other
/// block is final and the very same object is returned from every later
/// snapshot, so UI code can skip rebuilding it by identity.
sealed class Block {
  /// Creates a block.
  const Block({required this.id, required this.isOpen});

  /// An identifier that is stable across snapshots and unique among siblings.
  ///
  /// Use it as a widget key.
  final int id;

  /// Whether this block may still change as more input arrives.
  final bool isOpen;
}

/// A paragraph of inline content.
final class ParagraphBlock extends Block {
  /// Creates a paragraph.
  const ParagraphBlock({
    required super.id,
    required super.isOpen,
    required this.children,
  });

  /// The inline content.
  final List<Inline> children;

  @override
  bool operator ==(Object other) =>
      other is ParagraphBlock &&
      other.isOpen == isOpen &&
      listEquals(children, other.children);

  @override
  int get hashCode =>
      Object.hash(ParagraphBlock, isOpen, Object.hashAll(children));

  @override
  String toString() => 'Paragraph($children)';
}

/// An ATX (`# Title`) or setext heading.
final class HeadingBlock extends Block {
  /// Creates a heading.
  const HeadingBlock({
    required super.id,
    required super.isOpen,
    required this.level,
    required this.children,
  });

  /// The heading level, from 1 to 6.
  final int level;

  /// The inline content.
  final List<Inline> children;

  @override
  bool operator ==(Object other) =>
      other is HeadingBlock &&
      other.isOpen == isOpen &&
      other.level == level &&
      listEquals(children, other.children);

  @override
  int get hashCode =>
      Object.hash(HeadingBlock, isOpen, level, Object.hashAll(children));

  @override
  String toString() => 'Heading$level($children)';
}

/// A fenced (```` ``` ````) or indented code block.
///
/// While streaming, [lines] only ever grows by appending (the last line may
/// still be growing), which lets renderers highlight incrementally.
final class CodeBlock extends Block {
  /// Creates a code block.
  const CodeBlock({
    required super.id,
    required super.isOpen,
    required this.lines,
    this.info = '',
    this.language,
    this.isFenced = true,
  });

  /// The code, one entry per line, without line terminators.
  final List<String> lines;

  /// The raw info string after the opening fence (e.g. `dart title="a"`).
  final String info;

  /// The language: the first word of [info], or `null` when absent.
  final String? language;

  /// Whether the block was written with a fence (as opposed to indentation).
  final bool isFenced;

  /// The code as a single string; this is what the copy button copies.
  String get text => lines.join('\n');

  @override
  bool operator ==(Object other) =>
      other is CodeBlock &&
      other.isOpen == isOpen &&
      other.info == info &&
      other.language == language &&
      other.isFenced == isFenced &&
      listEquals(lines, other.lines);

  @override
  int get hashCode => Object.hash(
    CodeBlock,
    isOpen,
    info,
    language,
    isFenced,
    Object.hashAll(lines),
  );

  @override
  String toString() => 'Code(${language ?? '-'}, ${lines.length} lines)';
}

/// A display math block: `$$` or `\[` alone on a line, up to the matching
/// `$$` or `\]`, or a whole line such as `$$E=mc^2$$`.
///
/// A block that has not closed by the next blank line (display math cannot
/// contain one) or by the end of the input was not math: its lines are read
/// as ordinary text instead.
///
/// ```markdown
/// $$
/// \int_0^1 x^2\,dx = \tfrac13
/// $$
/// ```
///
/// While [isOpen], [tex] is probably incomplete, so renderers should show
/// the source rather than try to typeset it.
final class MathBlock extends Block {
  /// Creates a math block.
  const MathBlock({
    required super.id,
    required super.isOpen,
    required this.tex,
  });

  /// The TeX source, without the delimiters.
  final String tex;

  @override
  bool operator ==(Object other) =>
      other is MathBlock && other.isOpen == isOpen && other.tex == tex;

  @override
  int get hashCode => Object.hash(MathBlock, isOpen, tex);

  @override
  String toString() => 'MathBlock(${tex.replaceAll('\n', r'\n')})';
}

/// A block quote: `> text`.
final class BlockQuoteBlock extends Block {
  /// Creates a block quote.
  const BlockQuoteBlock({
    required super.id,
    required super.isOpen,
    required this.children,
  });

  /// The quoted blocks.
  final List<Block> children;

  @override
  bool operator ==(Object other) =>
      other is BlockQuoteBlock &&
      other.isOpen == isOpen &&
      listEquals(children, other.children);

  @override
  int get hashCode =>
      Object.hash(BlockQuoteBlock, isOpen, Object.hashAll(children));

  @override
  String toString() => 'Quote($children)';
}

/// One item of a [ListBlock].
final class ListItem {
  /// Creates a list item.
  const ListItem({
    required this.id,
    required this.isOpen,
    required this.children,
    this.checked,
    this.isLoose = false,
  });

  /// An identifier that is stable across snapshots and unique among siblings.
  final int id;

  /// Whether the item may still change as more input arrives.
  final bool isOpen;

  /// The item content.
  final List<Block> children;

  /// For task-list items (`- [x] done`), whether the box is checked;
  /// `null` for ordinary items.
  final bool? checked;

  /// Whether the item is separated from its content by blank lines.
  ///
  /// Loose items are rendered with paragraph spacing, tight ones compactly.
  final bool isLoose;

  @override
  bool operator ==(Object other) =>
      other is ListItem &&
      other.isOpen == isOpen &&
      other.checked == checked &&
      other.isLoose == isLoose &&
      listEquals(children, other.children);

  @override
  int get hashCode =>
      Object.hash(ListItem, isOpen, checked, isLoose, Object.hashAll(children));

  @override
  String toString() => 'Item($children)';
}

/// An ordered or unordered list.
final class ListBlock extends Block {
  /// Creates a list.
  const ListBlock({
    required super.id,
    required super.isOpen,
    required this.ordered,
    required this.start,
    required this.items,
  });

  /// Whether the list is numbered.
  final bool ordered;

  /// The number of the first item (only meaningful when [ordered]).
  final int start;

  /// The list items. All but the last are final while streaming.
  final List<ListItem> items;

  @override
  bool operator ==(Object other) =>
      other is ListBlock &&
      other.isOpen == isOpen &&
      other.ordered == ordered &&
      other.start == start &&
      listEquals(items, other.items);

  @override
  int get hashCode =>
      Object.hash(ListBlock, isOpen, ordered, start, Object.hashAll(items));

  @override
  String toString() => 'List(${ordered ? 'ol' : 'ul'}, $items)';
}

/// Horizontal alignment of a table column.
enum TableAlignment {
  /// No explicit alignment (rendered as start-aligned).
  none,

  /// Left aligned (`:---`).
  left,

  /// Centered (`:---:`).
  center,

  /// Right aligned (`---:`).
  right,
}

/// A GitHub-flavoured Markdown table.
///
/// Every row has exactly `alignments.length` cells; rows that arrived shorter
/// are padded with empty cells so partially streamed rows keep a stable shape.
final class TableBlock extends Block {
  /// Creates a table.
  const TableBlock({
    required super.id,
    required super.isOpen,
    required this.alignments,
    required this.header,
    required this.rows,
  });

  /// Per-column alignment; its length is the column count.
  final List<TableAlignment> alignments;

  /// The header cells.
  final List<List<Inline>> header;

  /// The body rows.
  final List<List<List<Inline>>> rows;

  @override
  bool operator ==(Object other) {
    if (other is! TableBlock ||
        other.isOpen != isOpen ||
        !listEquals(alignments, other.alignments) ||
        !_rowEq(header, other.header) ||
        rows.length != other.rows.length) {
      return false;
    }
    for (var i = 0; i < rows.length; i++) {
      if (!_rowEq(rows[i], other.rows[i])) return false;
    }
    return true;
  }

  static bool _rowEq(List<List<Inline>> a, List<List<Inline>> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!listEquals(a[i], b[i])) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(TableBlock, isOpen, alignments.length, rows.length);

  @override
  String toString() => 'Table(${alignments.length} cols, ${rows.length} rows)';
}

/// A thematic break: `---`, `***` or `___`.
final class ThematicBreakBlock extends Block {
  /// Creates a thematic break.
  const ThematicBreakBlock({required super.id}) : super(isOpen: false);

  @override
  bool operator ==(Object other) => other is ThematicBreakBlock;

  @override
  int get hashCode => (ThematicBreakBlock).hashCode;

  @override
  String toString() => 'Rule';
}
