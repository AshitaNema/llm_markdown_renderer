import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'syntax_theme.dart';

/// Visual configuration for rendered Markdown, as a [ThemeExtension].
///
/// Register it on your [ThemeData] to restyle every Markdown view below it:
///
/// ```dart
/// ThemeData(
///   extensions: [
///     MarkdownTheme.fromTheme(base).copyWith(blockSpacing: 20),
///   ],
/// )
/// ```
///
/// When no extension is registered, [MarkdownTheme.fromTheme] derives a
/// theme from the surrounding [ThemeData] (light and dark are both handled).
@immutable
final class MarkdownTheme extends ThemeExtension<MarkdownTheme> {
  /// Creates a Markdown theme from explicit values.
  const MarkdownTheme({
    required this.bodyStyle,
    required this.headingStyles,
    required this.linkStyle,
    required this.inlineCodeStyle,
    required this.codeBlockStyle,
    required this.codeBlockBackground,
    required this.codeBlockBorderColor,
    required this.codeBlockBorderRadius,
    required this.codeBlockPadding,
    required this.codeBlockHeaderBackground,
    required this.codeBlockHeaderStyle,
    required this.blockquoteBarColor,
    required this.blockquoteBarWidth,
    required this.blockquoteStyle,
    required this.tableBorderColor,
    required this.tableHeaderBackground,
    required this.tableHeaderStyle,
    required this.tableCellPadding,
    required this.dividerColor,
    required this.dividerThickness,
    required this.listIndent,
    required this.blockSpacing,
    required this.listItemSpacing,
    required this.syntaxTheme,
  }) : assert(headingStyles.length == 6, 'Provide exactly six heading styles');

  /// Derives a complete theme from [theme]'s colour scheme and text theme.
  factory MarkdownTheme.fromTheme(ThemeData theme) {
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final body = (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      color: scheme.onSurface,
      height: 1.5,
    );
    final base = body.fontSize ?? 14;
    const mono = <String>[
      'Menlo',
      'Consolas',
      'Roboto Mono',
      'Courier New',
      'monospace',
    ];
    final code = body.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: mono,
      fontSize: base * 0.9,
      height: 1.45,
    );
    TextStyle heading(double scale, FontWeight weight) =>
        body.copyWith(fontSize: base * scale, fontWeight: weight, height: 1.3);
    return MarkdownTheme(
      bodyStyle: body,
      headingStyles: [
        heading(1.8, FontWeight.w700),
        heading(1.5, FontWeight.w700),
        heading(1.3, FontWeight.w600),
        heading(1.15, FontWeight.w600),
        heading(1.0, FontWeight.w600),
        heading(0.9, FontWeight.w600),
      ],
      linkStyle: TextStyle(
        color: scheme.primary,
        decoration: TextDecoration.underline,
        decorationColor: scheme.primary,
      ),
      inlineCodeStyle: code.copyWith(
        backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
      ),
      codeBlockStyle: code,
      codeBlockBackground: dark
          ? Color.alphaBlend(
              Colors.white.withValues(alpha: 0.05),
              scheme.surface,
            )
          : Color.alphaBlend(
              Colors.black.withValues(alpha: 0.04),
              scheme.surface,
            ),
      codeBlockBorderColor: scheme.outlineVariant,
      codeBlockBorderRadius: 8,
      codeBlockPadding: const EdgeInsets.all(12),
      codeBlockHeaderBackground: scheme.onSurface.withValues(
        alpha: dark ? 0.10 : 0.06,
      ),
      codeBlockHeaderStyle: body.copyWith(
        fontSize: base * 0.8,
        color: scheme.onSurfaceVariant,
        height: 1.2,
      ),
      blockquoteBarColor: scheme.outline,
      blockquoteBarWidth: 3,
      blockquoteStyle: body.copyWith(color: scheme.onSurfaceVariant),
      tableBorderColor: scheme.outlineVariant,
      tableHeaderBackground: scheme.onSurface.withValues(alpha: 0.06),
      tableHeaderStyle: body.copyWith(fontWeight: FontWeight.w600),
      tableCellPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      dividerColor: scheme.outlineVariant,
      dividerThickness: 1,
      listIndent: 24,
      blockSpacing: 12,
      listItemSpacing: 4,
      syntaxTheme: dark ? SyntaxTheme.dark() : SyntaxTheme.light(),
    );
  }

  /// Returns the theme in effect for [context]: the [MarkdownTheme] extension
  /// of the closest [Theme] if registered, otherwise one derived with
  /// [MarkdownTheme.fromTheme].
  static MarkdownTheme of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<MarkdownTheme>() ?? MarkdownTheme.fromTheme(theme);
  }

  /// Style of normal paragraph text; every other text style builds on it.
  final TextStyle bodyStyle;

  /// Styles for headings `h1`…`h6` (exactly six entries).
  final List<TextStyle> headingStyles;

  /// Style merged over text inside links.
  final TextStyle linkStyle;

  /// Style of inline `code` spans.
  final TextStyle inlineCodeStyle;

  /// Base (monospace) style of fenced and indented code blocks.
  final TextStyle codeBlockStyle;

  /// Background of code blocks.
  final Color codeBlockBackground;

  /// Border colour of code blocks.
  final Color codeBlockBorderColor;

  /// Corner radius of code blocks.
  final double codeBlockBorderRadius;

  /// Padding around the code inside a code block.
  final EdgeInsets codeBlockPadding;

  /// Background of the code block header (language label and copy button).
  final Color codeBlockHeaderBackground;

  /// Text style of the language label in the code block header.
  final TextStyle codeBlockHeaderStyle;

  /// Colour of the vertical bar of block quotes.
  final Color blockquoteBarColor;

  /// Width of the block quote bar.
  final double blockquoteBarWidth;

  /// Text style inside block quotes.
  final TextStyle blockquoteStyle;

  /// Colour of table borders.
  final Color tableBorderColor;

  /// Background of the table header row.
  final Color tableHeaderBackground;

  /// Text style of table header cells.
  final TextStyle tableHeaderStyle;

  /// Padding of each table cell.
  final EdgeInsets tableCellPadding;

  /// Colour of thematic breaks (`---`).
  final Color dividerColor;

  /// Thickness of thematic breaks.
  final double dividerThickness;

  /// Width reserved for list markers (bullets and numbers).
  final double listIndent;

  /// Vertical space between blocks.
  final double blockSpacing;

  /// Vertical space between tight list items.
  final double listItemSpacing;

  /// Token colours for syntax-highlighted code.
  final SyntaxTheme syntaxTheme;

  /// The style for a heading of [level] (1–6).
  TextStyle headingStyle(int level) => headingStyles[(level - 1).clamp(0, 5)];

  @override
  MarkdownTheme copyWith({
    TextStyle? bodyStyle,
    List<TextStyle>? headingStyles,
    TextStyle? linkStyle,
    TextStyle? inlineCodeStyle,
    TextStyle? codeBlockStyle,
    Color? codeBlockBackground,
    Color? codeBlockBorderColor,
    double? codeBlockBorderRadius,
    EdgeInsets? codeBlockPadding,
    Color? codeBlockHeaderBackground,
    TextStyle? codeBlockHeaderStyle,
    Color? blockquoteBarColor,
    double? blockquoteBarWidth,
    TextStyle? blockquoteStyle,
    Color? tableBorderColor,
    Color? tableHeaderBackground,
    TextStyle? tableHeaderStyle,
    EdgeInsets? tableCellPadding,
    Color? dividerColor,
    double? dividerThickness,
    double? listIndent,
    double? blockSpacing,
    double? listItemSpacing,
    SyntaxTheme? syntaxTheme,
  }) {
    return MarkdownTheme(
      bodyStyle: bodyStyle ?? this.bodyStyle,
      headingStyles: headingStyles ?? this.headingStyles,
      linkStyle: linkStyle ?? this.linkStyle,
      inlineCodeStyle: inlineCodeStyle ?? this.inlineCodeStyle,
      codeBlockStyle: codeBlockStyle ?? this.codeBlockStyle,
      codeBlockBackground: codeBlockBackground ?? this.codeBlockBackground,
      codeBlockBorderColor: codeBlockBorderColor ?? this.codeBlockBorderColor,
      codeBlockBorderRadius:
          codeBlockBorderRadius ?? this.codeBlockBorderRadius,
      codeBlockPadding: codeBlockPadding ?? this.codeBlockPadding,
      codeBlockHeaderBackground:
          codeBlockHeaderBackground ?? this.codeBlockHeaderBackground,
      codeBlockHeaderStyle: codeBlockHeaderStyle ?? this.codeBlockHeaderStyle,
      blockquoteBarColor: blockquoteBarColor ?? this.blockquoteBarColor,
      blockquoteBarWidth: blockquoteBarWidth ?? this.blockquoteBarWidth,
      blockquoteStyle: blockquoteStyle ?? this.blockquoteStyle,
      tableBorderColor: tableBorderColor ?? this.tableBorderColor,
      tableHeaderBackground:
          tableHeaderBackground ?? this.tableHeaderBackground,
      tableHeaderStyle: tableHeaderStyle ?? this.tableHeaderStyle,
      tableCellPadding: tableCellPadding ?? this.tableCellPadding,
      dividerColor: dividerColor ?? this.dividerColor,
      dividerThickness: dividerThickness ?? this.dividerThickness,
      listIndent: listIndent ?? this.listIndent,
      blockSpacing: blockSpacing ?? this.blockSpacing,
      listItemSpacing: listItemSpacing ?? this.listItemSpacing,
      syntaxTheme: syntaxTheme ?? this.syntaxTheme,
    );
  }

  @override
  MarkdownTheme lerp(ThemeExtension<MarkdownTheme>? other, double t) {
    if (other is! MarkdownTheme) return this;
    TextStyle ts(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t)!;
    Color col(Color a, Color b) => Color.lerp(a, b, t)!;
    double d(double a, double b) => lerpDouble(a, b, t)!;
    return MarkdownTheme(
      bodyStyle: ts(bodyStyle, other.bodyStyle),
      headingStyles: [
        for (var i = 0; i < 6; i++)
          ts(headingStyles[i], other.headingStyles[i]),
      ],
      linkStyle: ts(linkStyle, other.linkStyle),
      inlineCodeStyle: ts(inlineCodeStyle, other.inlineCodeStyle),
      codeBlockStyle: ts(codeBlockStyle, other.codeBlockStyle),
      codeBlockBackground: col(codeBlockBackground, other.codeBlockBackground),
      codeBlockBorderColor: col(
        codeBlockBorderColor,
        other.codeBlockBorderColor,
      ),
      codeBlockBorderRadius: d(
        codeBlockBorderRadius,
        other.codeBlockBorderRadius,
      ),
      codeBlockPadding: EdgeInsets.lerp(
        codeBlockPadding,
        other.codeBlockPadding,
        t,
      )!,
      codeBlockHeaderBackground: col(
        codeBlockHeaderBackground,
        other.codeBlockHeaderBackground,
      ),
      codeBlockHeaderStyle: ts(
        codeBlockHeaderStyle,
        other.codeBlockHeaderStyle,
      ),
      blockquoteBarColor: col(blockquoteBarColor, other.blockquoteBarColor),
      blockquoteBarWidth: d(blockquoteBarWidth, other.blockquoteBarWidth),
      blockquoteStyle: ts(blockquoteStyle, other.blockquoteStyle),
      tableBorderColor: col(tableBorderColor, other.tableBorderColor),
      tableHeaderBackground: col(
        tableHeaderBackground,
        other.tableHeaderBackground,
      ),
      tableHeaderStyle: ts(tableHeaderStyle, other.tableHeaderStyle),
      tableCellPadding: EdgeInsets.lerp(
        tableCellPadding,
        other.tableCellPadding,
        t,
      )!,
      dividerColor: col(dividerColor, other.dividerColor),
      dividerThickness: d(dividerThickness, other.dividerThickness),
      listIndent: d(listIndent, other.listIndent),
      blockSpacing: d(blockSpacing, other.blockSpacing),
      listItemSpacing: d(listItemSpacing, other.listItemSpacing),
      syntaxTheme: SyntaxTheme.lerp(syntaxTheme, other.syntaxTheme, t),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MarkdownTheme &&
      other.bodyStyle == bodyStyle &&
      _listEq(other.headingStyles, headingStyles) &&
      other.linkStyle == linkStyle &&
      other.inlineCodeStyle == inlineCodeStyle &&
      other.codeBlockStyle == codeBlockStyle &&
      other.codeBlockBackground == codeBlockBackground &&
      other.codeBlockBorderColor == codeBlockBorderColor &&
      other.codeBlockBorderRadius == codeBlockBorderRadius &&
      other.codeBlockPadding == codeBlockPadding &&
      other.codeBlockHeaderBackground == codeBlockHeaderBackground &&
      other.codeBlockHeaderStyle == codeBlockHeaderStyle &&
      other.blockquoteBarColor == blockquoteBarColor &&
      other.blockquoteBarWidth == blockquoteBarWidth &&
      other.blockquoteStyle == blockquoteStyle &&
      other.tableBorderColor == tableBorderColor &&
      other.tableHeaderBackground == tableHeaderBackground &&
      other.tableHeaderStyle == tableHeaderStyle &&
      other.tableCellPadding == tableCellPadding &&
      other.dividerColor == dividerColor &&
      other.dividerThickness == dividerThickness &&
      other.listIndent == listIndent &&
      other.blockSpacing == blockSpacing &&
      other.listItemSpacing == listItemSpacing &&
      other.syntaxTheme == syntaxTheme;

  @override
  int get hashCode => Object.hashAll([
    bodyStyle,
    Object.hashAll(headingStyles),
    linkStyle,
    inlineCodeStyle,
    codeBlockStyle,
    codeBlockBackground,
    codeBlockBorderColor,
    codeBlockBorderRadius,
    codeBlockPadding,
    codeBlockHeaderBackground,
    codeBlockHeaderStyle,
    blockquoteBarColor,
    blockquoteBarWidth,
    blockquoteStyle,
    tableBorderColor,
    tableHeaderBackground,
    tableHeaderStyle,
    tableCellPadding,
    dividerColor,
    dividerThickness,
    listIndent,
    blockSpacing,
    listItemSpacing,
    syntaxTheme,
  ]);

  static bool _listEq(List<TextStyle> a, List<TextStyle> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
