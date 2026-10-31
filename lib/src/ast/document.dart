import 'block.dart';
import 'equality.dart';

/// An immutable snapshot of a parsed (possibly still streaming) document.
final class MarkdownDocument {
  /// Creates a document from [blocks].
  MarkdownDocument(List<Block> blocks, {required this.isComplete})
    : blocks = List.unmodifiable(blocks);

  /// The top-level blocks, in order.
  ///
  /// While streaming, only the last block can be open.
  final List<Block> blocks;

  /// Whether the input stream has finished, so no block is open any more.
  final bool isComplete;

  @override
  bool operator ==(Object other) =>
      other is MarkdownDocument &&
      other.isComplete == isComplete &&
      listEquals(blocks, other.blocks);

  @override
  int get hashCode => Object.hash(isComplete, Object.hashAll(blocks));

  @override
  String toString() => 'MarkdownDocument($blocks)';
}
