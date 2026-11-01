import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown_renderer/parser.dart';

import '../fixtures.dart';
import '../helpers.dart';

void main() {
  group('chunking independence', () {
    for (final entry in fixtures.entries) {
      final name = entry.key;
      final text = entry.value;

      test('$name: every 2-way split equals the one-shot parse', () {
        final expected = oneShot(text);
        for (var cut = 0; cut <= text.length; cut++) {
          final got = streamed([text.substring(0, cut), text.substring(cut)]);
          expect(got, expected, reason: 'split at $cut of ${text.length}');
        }
      });

      test('$name: char-by-char equals one-shot parse of every prefix', () {
        final p = IncrementalMarkdownParser();
        for (var i = 0; i < text.length; i++) {
          p.append(text[i]);
          expect(
            p.document,
            oneShot(text.substring(0, i + 1)),
            reason: 'prefix of length ${i + 1}',
          );
        }
      });

      test('$name: random partitions (and complete()) agree', () {
        final rnd = Random(name.hashCode);
        final expected = IncrementalMarkdownParser.parse(text);
        for (var round = 0; round < 40; round++) {
          final p = IncrementalMarkdownParser();
          for (final c in randomChunks(text, rnd, maxLen: 1 + round % 9)) {
            p.append(c);
            if (rnd.nextInt(7) == 0) p.document; // snapshots must not matter
            if (rnd.nextInt(5) == 0) p.append(''); // empty chunks are no-ops
          }
          p.complete();
          expect(p.document, expected, reason: 'round $round');
        }
      });

      test('$name: complete() leaves nothing open', () {
        final doc = IncrementalMarkdownParser.parse(text);
        expect(doc.isComplete, isTrue);
        expect(doc.blocks.where((b) => b.isOpen), isEmpty);
      });
    }
  });

  group('boundary cases', () {
    test('CRLF split between CR and LF is one line break, not two', () {
      final a = streamed(['a\r', '\nb\r\n']);
      final b = streamed(['a\r\nb\r\n']);
      expect(a, b);
      expect(a.blocks, hasLength(1));
      expect((a.blocks.single as ParagraphBlock).children, [
        const InlineText('a'),
        const InlineSoftBreak(),
        const InlineText('b'),
      ]);
    });

    test('lone CR ends a line', () {
      final doc = IncrementalMarkdownParser.parse('# a\rb');
      expect(doc.blocks, hasLength(2));
      expect(doc.blocks.first, isA<HeadingBlock>());
    });

    test('surrogate pair split across chunks is never torn', () {
      const crab = '🦀'; // two UTF-16 code units
      final p = IncrementalMarkdownParser()
        ..append('hi ${crab[0]}')
        ..append(crab[1])
        ..append(' there');
      final para = p.document.blocks.single as ParagraphBlock;
      expect(para.children, [const InlineText('hi 🦀 there')]);
    });

    test('dangling high surrogate at the end does not crash or leak', () {
      final p = IncrementalMarkdownParser()..append('x 🦀'.substring(0, 3));
      expect(p.document.blocks, hasLength(1));
      p.complete();
      expect(p.document.isComplete, isTrue);
    });

    test('fence marker split across chunks opens one code block', () {
      for (var cut = 1; cut < 3; cut++) {
        final p = IncrementalMarkdownParser()
          ..append('`' * cut)
          ..append('${'`' * (3 - cut)}dart\nvoid f() {}\n');
        final code = p.document.blocks.whereType<CodeBlock>().single;
        expect(code.language, 'dart');
        expect(code.lines, ['void f() {}']);
        expect(code.isOpen, isTrue);
      }
    });

    test('closing fence split across chunks closes the block', () {
      final p = IncrementalMarkdownParser()
        ..append('```\ncode\n``')
        ..append('`\nafter');
      final blocks = p.document.blocks;
      expect(blocks.first, isA<CodeBlock>());
      expect(blocks.first.isOpen, isFalse);
      expect(blocks.last, isA<ParagraphBlock>());
    });

    test('table delimiter row split in the middle still produces a table', () {
      final p = IncrementalMarkdownParser()
        ..append('| a | b |\n|--')
        ..append('-|---|\n| 1 | 2 |\n');
      final table = p.document.blocks.single as TableBlock;
      expect(table.alignments, hasLength(2));
      expect(table.rows, hasLength(1));
    });

    test('empty chunks and chunks of only newlines are harmless', () {
      final p = IncrementalMarkdownParser()
        ..append('')
        ..append('a')
        ..append('\n')
        ..append('')
        ..append('\n')
        ..append('b');
      expect(p.document.blocks, hasLength(2));
    });

    test('complete() mid-construct finalizes it', () {
      final p = IncrementalMarkdownParser()..append('text **bo');
      p.complete();
      final para = p.document.blocks.single as ParagraphBlock;
      expect(para.isOpen, isFalse);
      // After completion the unclosed delimiter is literal text.
      expect(para.children, [const InlineText('text **bo')]);
    });

    test('append after complete throws until reset', () {
      final p = IncrementalMarkdownParser()
        ..append('a')
        ..complete();
      expect(() => p.append('b'), throwsStateError);
      p.reset();
      p.append('b');
      expect(p.document.blocks, hasLength(1));
    });

    test('very long single line without newline', () {
      final long = 'word ' * 20000;
      final p = IncrementalMarkdownParser()..append(long);
      expect(p.document.blocks, hasLength(1));
    });
  });
}
