import 'equality.dart';

/// A node of inline Markdown content (text, emphasis, links, …).
///
/// The hierarchy is `sealed`, so consumers can use exhaustive `switch`
/// expressions. All nodes are immutable and have value equality.
sealed class Inline {
  /// Creates an inline node.
  const Inline();
}

/// A run of literal text.
final class InlineText extends Inline {
  /// Creates a text node.
  const InlineText(this.text);

  /// The literal text, with escapes and entities already decoded.
  final String text;

  @override
  bool operator ==(Object other) => other is InlineText && other.text == text;

  @override
  int get hashCode => Object.hash(InlineText, text);

  @override
  String toString() => 'Text(${text.replaceAll('\n', r'\n')})';
}

/// Emphasized (usually italic) content: `*text*` or `_text_`.
final class InlineEmphasis extends Inline {
  /// Creates an emphasis node.
  const InlineEmphasis(this.children);

  /// The emphasized content.
  final List<Inline> children;

  @override
  bool operator ==(Object other) =>
      other is InlineEmphasis && listEquals(children, other.children);

  @override
  int get hashCode => Object.hash(InlineEmphasis, Object.hashAll(children));

  @override
  String toString() => 'Em($children)';
}

/// Strongly emphasized (usually bold) content: `**text**`.
final class InlineStrong extends Inline {
  /// Creates a strong node.
  const InlineStrong(this.children);

  /// The strongly emphasized content.
  final List<Inline> children;

  @override
  bool operator ==(Object other) =>
      other is InlineStrong && listEquals(children, other.children);

  @override
  int get hashCode => Object.hash(InlineStrong, Object.hashAll(children));

  @override
  String toString() => 'Strong($children)';
}

/// Struck-through content: `~~text~~`.
final class InlineStrikethrough extends Inline {
  /// Creates a strikethrough node.
  const InlineStrikethrough(this.children);

  /// The struck-through content.
  final List<Inline> children;

  @override
  bool operator ==(Object other) =>
      other is InlineStrikethrough && listEquals(children, other.children);

  @override
  int get hashCode =>
      Object.hash(InlineStrikethrough, Object.hashAll(children));

  @override
  String toString() => 'Strike($children)';
}

/// An inline code span: `` `code` ``.
final class InlineCode extends Inline {
  /// Creates a code span.
  const InlineCode(this.code);

  /// The code text.
  final String code;

  @override
  bool operator ==(Object other) => other is InlineCode && other.code == code;

  @override
  int get hashCode => Object.hash(InlineCode, code);

  @override
  String toString() => 'Code($code)';
}

/// A hyperlink: `[label](url "title")`, `<url>` or a bare `https://` URL.
final class InlineLink extends Inline {
  /// Creates a link node.
  const InlineLink({required this.url, required this.children, this.title});

  /// The link destination.
  final String url;

  /// The optional link title.
  final String? title;

  /// The link label.
  final List<Inline> children;

  @override
  bool operator ==(Object other) =>
      other is InlineLink &&
      other.url == url &&
      other.title == title &&
      listEquals(children, other.children);

  @override
  int get hashCode =>
      Object.hash(InlineLink, url, title, Object.hashAll(children));

  @override
  String toString() => 'Link($url, $children)';
}

/// An image: `![alt](url "title")`.
final class InlineImage extends Inline {
  /// Creates an image node.
  const InlineImage({required this.url, required this.alt, this.title});

  /// The image source URL.
  final String url;

  /// The plain-text alternative text.
  final String alt;

  /// The optional image title.
  final String? title;

  @override
  bool operator ==(Object other) =>
      other is InlineImage &&
      other.url == url &&
      other.alt == alt &&
      other.title == title;

  @override
  int get hashCode => Object.hash(InlineImage, url, alt, title);

  @override
  String toString() => 'Image($url, $alt)';
}

/// A hard line break (two trailing spaces or a trailing backslash).
final class InlineLineBreak extends Inline {
  /// Creates a hard line break.
  const InlineLineBreak();

  @override
  bool operator ==(Object other) => other is InlineLineBreak;

  @override
  int get hashCode => (InlineLineBreak).hashCode;

  @override
  String toString() => 'LineBreak';
}

/// A soft line break: a single newline inside a paragraph.
final class InlineSoftBreak extends Inline {
  /// Creates a soft line break.
  const InlineSoftBreak();

  @override
  bool operator ==(Object other) => other is InlineSoftBreak;

  @override
  int get hashCode => (InlineSoftBreak).hashCode;

  @override
  String toString() => 'SoftBreak';
}
