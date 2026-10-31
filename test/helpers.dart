import 'dart:math';

import 'package:llm_markdown_renderer/parser.dart';

/// Parses [chunks] one after another and returns the resulting document
/// *without* completing it.
MarkdownDocument streamed(
  Iterable<String> chunks, {
  MarkdownParserOptions options = const MarkdownParserOptions(),
}) {
  final p = IncrementalMarkdownParser(options: options);
  chunks.forEach(p.append);
  return p.document;
}

/// Parses [text] as a single chunk, without completing.
MarkdownDocument oneShot(String text) => streamed([text]);

/// Splits [text] into pseudo-random chunks of 1..[maxLen] code units.
List<String> randomChunks(String text, Random rnd, {int maxLen = 6}) {
  final out = <String>[];
  var i = 0;
  while (i < text.length) {
    final n = min(text.length - i, 1 + rnd.nextInt(maxLen));
    out.add(text.substring(i, i + n));
    i += n;
  }
  return out;
}

/// Shorthand: the first block of a one-shot, completed parse.
Block first(String md) => IncrementalMarkdownParser.parse(md).blocks.first;
