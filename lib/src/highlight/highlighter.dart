import 'rule_highlighter.dart';

/// The syntactic category of a [Token], used to pick a colour from the theme.
enum TokenKind {
  /// Text with no special meaning.
  plain,

  /// A language keyword such as `if` or `class`.
  keyword,

  /// A type or class name.
  type,

  /// A string or character literal.
  string,

  /// A numeric literal.
  number,

  /// A comment.
  comment,

  /// A function or method name at a call/declaration site.
  function,

  /// An operator such as `+` or `=>`.
  operator,

  /// Brackets, braces, commas and other punctuation.
  punctuation,

  /// A language constant such as `true`, `null` or `None`.
  constant,

  /// A variable reference, e.g. `$HOME` in shell.
  variable,

  /// A markup tag name, e.g. `<div>`.
  tag,

  /// A markup attribute name.
  attribute,

  /// A property or object key.
  property,

  /// Meta syntax: annotations, preprocessor directives, diff headers.
  meta,

  /// A line removed in a diff.
  deletion,

  /// A line added in a diff.
  addition,
}

/// A highlighted slice `[start, end)` of a single line.
final class Token {
  /// Creates a token covering `[start, end)` of a line.
  const Token(this.kind, this.start, this.end);

  /// The token's category.
  final TokenKind kind;

  /// Inclusive start offset within the line.
  final int start;

  /// Exclusive end offset within the line.
  final int end;

  @override
  bool operator ==(Object other) =>
      other is Token &&
      other.kind == kind &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(kind, start, end);

  @override
  String toString() => '$kind[$start,$end)';
}

/// The result of highlighting one line.
final class LineHighlight {
  /// Creates a line result.
  const LineHighlight(this.tokens, [this.endState]);

  /// The tokens of the line, ordered and non-overlapping. Gaps are plain text.
  final List<Token> tokens;

  /// Opaque lexer state to pass in when highlighting the *next* line
  /// (for example "inside a block comment"). `null` means the initial state.
  final Object? endState;
}

/// Turns lines of source code into syntax [Token]s.
///
/// Implementations are asked for one line at a time and may carry state from
/// line to line through [LineHighlight.endState]. That is what allows the
/// renderer to highlight a streaming code block incrementally, tokenizing only
/// the lines that arrived since the last frame.
///
/// An engine that cannot work line by line can return `null` state and
/// highlight each line on its own, at the price of losing multi-line
/// constructs.
abstract interface class CodeHighlighter {
  /// The built-in highlighter, supporting the languages listed on
  /// [RuleBasedHighlighter].
  const factory CodeHighlighter.defaults() = RuleBasedHighlighter;

  /// Highlights [line] of code written in [language].
  ///
  /// [language] is the info string's first word (`dart`, `py`, …), or `null`.
  /// [state] is the `endState` of the previous line, or `null` for the first
  /// line. Unknown languages should yield no tokens.
  LineHighlight highlightLine(String? language, String line, Object? state);
}
