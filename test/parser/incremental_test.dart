import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown_renderer/parser.dart';

String paragraphs(int n) =>
    [for (var i = 0; i < n; i++) 'Paragraph **$i** text.\n'].join('\n');

/// Streams [tail] char by char after [prefix] and returns the largest number
/// of inline parses a single append caused.
int worstPerAppend(String prefix, String tail) {
  final p = IncrementalMarkdownParser()..append(prefix);
  p.document;
  var worst = 0;
  for (final ch in tail.split('')) {
    final before = p.debugInlineParseCount;
    p.append(ch);
    p.document;
    final d = p.debugInlineParseCount - before;
    if (d > worst) worst = d;
  }
  return worst;
}

void main() {
  group('only the open block is parsed', () {
    const tail =
        '\nNew paragraph with **bold** and `code` streaming in slowly.';

    test('cost per append does not grow with document size', () {
      final small = worstPerAppend(paragraphs(10), tail);
      final large = worstPerAppend(paragraphs(1500), tail);
      expect(large, small);
      expect(large, lessThanOrEqualTo(3));
    });

    test(
      'committed blocks are the identical object in every later snapshot',
      () {
        final p = IncrementalMarkdownParser()..append(paragraphs(50));
        final before = p.document.blocks;
        for (final ch in tail.split('')) {
          p.append(ch);
        }
        final after = p.document.blocks;
        // All blocks except possibly the previously-last (it was closed by the
        // blank line) must be identical objects.
        for (var i = 0; i < before.length - 1; i++) {
          expect(identical(before[i], after[i]), isTrue, reason: 'block $i');
        }
        expect(after.length, before.length + 1);
      },
    );

    test('a long list costs O(current item), not O(list)', () {
      final list = [
        for (var i = 0; i < 600; i++) '- item $i with text',
      ].join('\n');
      final small = worstPerAppend('- a\n- b\n', '- item streaming in now');
      final large = worstPerAppend('$list\n', '- item streaming in now');
      expect(large, small);
    });

    test('earlier list items keep their identity', () {
      final p = IncrementalMarkdownParser()..append('- a\n- b\n- c');
      final first = (p.document.blocks.single as ListBlock).items;
      p.append('\n- d');
      final second = (p.document.blocks.single as ListBlock).items;
      expect(identical(first[0], second[0]), isTrue);
      // Item b was only *previewed* as closed; once committed it is an equal
      // (not identical) value, which the widget cache also accepts.
      expect(first[1], second[1]);
      expect(identical(first[2], second[2]), isFalse); // was open
      expect(second[2].isOpen, isFalse);
      expect(second[3].isOpen, isTrue);
    });

    test('a huge code block does not re-parse inline content', () {
      final code = [for (var i = 0; i < 3000; i++) 'line $i **x**'].join('\n');
      final p = IncrementalMarkdownParser()..append('```txt\n$code\n');
      final before = p.debugInlineParseCount;
      for (final ch in 'more code'.split('')) {
        p.append(ch);
        p.document;
      }
      expect(p.debugInlineParseCount, before);
    });

    test('table rows are parsed once', () {
      final rows = [for (var i = 0; i < 300; i++) '| $i | x |'].join('\n');
      final p = IncrementalMarkdownParser()
        ..append('| a | b |\n|---|---|\n$rows\n');
      p.document;
      final before = p.debugInlineParseCount;
      p.append('| 3');
      p.document;
      // only the partial row (2 cells) is parsed, not the 300 committed rows
      expect(p.debugInlineParseCount - before, lessThanOrEqualTo(2));
    });
  });

  test('the open block is the last block and the only one marked open', () {
    final p = IncrementalMarkdownParser()..append('a\n\nb\n\nc');
    final blocks = p.document.blocks;
    expect(blocks.map((b) => b.isOpen), [false, false, true]);
  });

  test('document snapshot is cached until the next append', () {
    final p = IncrementalMarkdownParser()..append('a');
    expect(identical(p.document, p.document), isTrue);
    final d = p.document;
    p.append('b');
    expect(identical(d, p.document), isFalse);
  });

  test('block-level parse of 20k-token stream finishes quickly', () {
    final sw = Stopwatch()..start();
    final p = IncrementalMarkdownParser();
    final text = [
      for (var i = 0; i < 400; i++)
        '## Section $i\n\nSome **bold** text with `code` and a [link](http://x.y).\n\n'
            '- one\n- two\n\n```dart\nvoid f$i() {}\n```\n\n| a | b |\n|---|---|\n| $i | x |\n\n',
    ].join();
    for (var i = 0; i < text.length; i += 3) {
      p.append(text.substring(i, i + 3 > text.length ? text.length : i + 3));
      p.document;
    }
    p.complete();
    // Generous bound; guards against accidental quadratic behaviour.
    expect(sw.elapsed, lessThan(const Duration(seconds: 10)));
    expect(p.document.blocks.length, greaterThan(1500));
  });
}
