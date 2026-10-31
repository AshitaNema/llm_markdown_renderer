import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../highlight/highlighter.dart';

/// Colours and styles for syntax-highlighted code, keyed by [TokenKind].
@immutable
final class SyntaxTheme {
  /// Creates a syntax theme. Kinds missing from [styles] use [fallback].
  const SyntaxTheme({required this.styles, this.fallback = const TextStyle()});

  /// A theme for light backgrounds (GitHub-light inspired).
  factory SyntaxTheme.light() => const SyntaxTheme(
    styles: {
      TokenKind.keyword: TextStyle(color: Color(0xFFCF222E)),
      TokenKind.type: TextStyle(color: Color(0xFF953800)),
      TokenKind.string: TextStyle(color: Color(0xFF0A3069)),
      TokenKind.number: TextStyle(color: Color(0xFF0550AE)),
      TokenKind.comment: TextStyle(
        color: Color(0xFF6E7781),
        fontStyle: FontStyle.italic,
      ),
      TokenKind.function: TextStyle(color: Color(0xFF8250DF)),
      TokenKind.operator: TextStyle(color: Color(0xFFCF222E)),
      TokenKind.punctuation: TextStyle(color: Color(0xFF57606A)),
      TokenKind.constant: TextStyle(color: Color(0xFF0550AE)),
      TokenKind.variable: TextStyle(color: Color(0xFF953800)),
      TokenKind.tag: TextStyle(color: Color(0xFF116329)),
      TokenKind.attribute: TextStyle(color: Color(0xFF0550AE)),
      TokenKind.property: TextStyle(color: Color(0xFF0550AE)),
      TokenKind.meta: TextStyle(color: Color(0xFF6639BA)),
      TokenKind.deletion: TextStyle(
        color: Color(0xFF82071E),
        backgroundColor: Color(0x33FF8182),
      ),
      TokenKind.addition: TextStyle(
        color: Color(0xFF116329),
        backgroundColor: Color(0x3382E186),
      ),
    },
  );

  /// A theme for dark backgrounds (GitHub-dark inspired).
  factory SyntaxTheme.dark() => const SyntaxTheme(
    styles: {
      TokenKind.keyword: TextStyle(color: Color(0xFFFF7B72)),
      TokenKind.type: TextStyle(color: Color(0xFFFFA657)),
      TokenKind.string: TextStyle(color: Color(0xFFA5D6FF)),
      TokenKind.number: TextStyle(color: Color(0xFF79C0FF)),
      TokenKind.comment: TextStyle(
        color: Color(0xFF8B949E),
        fontStyle: FontStyle.italic,
      ),
      TokenKind.function: TextStyle(color: Color(0xFFD2A8FF)),
      TokenKind.operator: TextStyle(color: Color(0xFFFF7B72)),
      TokenKind.punctuation: TextStyle(color: Color(0xFF8B949E)),
      TokenKind.constant: TextStyle(color: Color(0xFF79C0FF)),
      TokenKind.variable: TextStyle(color: Color(0xFFFFA657)),
      TokenKind.tag: TextStyle(color: Color(0xFF7EE787)),
      TokenKind.attribute: TextStyle(color: Color(0xFF79C0FF)),
      TokenKind.property: TextStyle(color: Color(0xFF79C0FF)),
      TokenKind.meta: TextStyle(color: Color(0xFFD2A8FF)),
      TokenKind.deletion: TextStyle(
        color: Color(0xFFFFDCD7),
        backgroundColor: Color(0x66F85149),
      ),
      TokenKind.addition: TextStyle(
        color: Color(0xFFAFF5B4),
        backgroundColor: Color(0x663FB950),
      ),
    },
  );

  /// The style for each token kind.
  final Map<TokenKind, TextStyle> styles;

  /// The style used for kinds absent from [styles] (including plain text).
  final TextStyle fallback;

  /// The style for [kind], without the surrounding code-block text style.
  TextStyle styleFor(TokenKind kind) => styles[kind] ?? fallback;

  /// Returns a copy with [styles] entries merged over the existing ones.
  SyntaxTheme copyWith({
    Map<TokenKind, TextStyle>? styles,
    TextStyle? fallback,
  }) => SyntaxTheme(
    styles: styles == null ? this.styles : {...this.styles, ...styles},
    fallback: fallback ?? this.fallback,
  );

  /// Linearly interpolates between two syntax themes.
  static SyntaxTheme lerp(SyntaxTheme a, SyntaxTheme b, double t) {
    final kinds = {...a.styles.keys, ...b.styles.keys};
    return SyntaxTheme(
      styles: {
        for (final k in kinds)
          k: TextStyle.lerp(a.styles[k], b.styles[k], t) ?? const TextStyle(),
      },
      fallback: TextStyle.lerp(a.fallback, b.fallback, t) ?? const TextStyle(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (other is! SyntaxTheme ||
        other.fallback != fallback ||
        other.styles.length != styles.length) {
      return false;
    }
    for (final e in styles.entries) {
      if (other.styles[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    fallback,
    Object.hashAllUnordered(
      styles.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}
