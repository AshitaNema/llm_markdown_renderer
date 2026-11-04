import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown_renderer/parser.dart';
import 'package:llm_markdown_renderer/src/parser/inline_parser.dart';

import '../helpers.dart';

List<Inline> inl(String s, {bool streaming = false, bool math = true}) =>
    parseInlines(
      s,
      streaming: streaming,
      options: MarkdownParserOptions(math: math),
    );

const t = InlineText.new;

/// The blocks of [md] streamed in one chunk, without completing.
List<Block> streamingBlocks(String md) =>
    (IncrementalMarkdownParser()..append(md)).document.blocks;

void main() {
  group('inline math', () {
    test(r'$…$ and \(…\) are inline, $$…$$ is display', () {
      expect(inl(r'a $x^2$ b'), [t('a '), const InlineMath('x^2'), t(' b')]);
      expect(inl(r'\(a+b\)'), [const InlineMath('a+b')]);
      expect(inl(r'so $$\sum_i x_i$$ ok'), [
        t('so '),
        const InlineMath(r'\sum_i x_i', display: true),
        t(' ok'),
      ]);
    });

    test(r'inline \[…\] stays an escaped bracket', () {
      expect(inl(r'Press \[Enter\] to go'), [t('Press [Enter] to go')]);
      expect(inl(r'array\[0\]'), [t('array[0]')]);
    });

    test('shell variables are text', () {
      for (final s in [
        r'Set $HOME first',
        r'echo $PATH and $USER',
        r'export A=$B',
        r'echo $$ prints the PID',
        r'use \( to start a group',
      ]) {
        final plain = s.replaceAll(r'\(', '(');
        expect(inl(s), [t(plain)], reason: s);
        expect(inl(s, streaming: true), [t(plain)], reason: '$s (streaming)');
      }
    });

    test(r'many unclosed \( stay linear', () {
      final text = r'a \( b ' * 4000;
      final sw = Stopwatch()..start();
      inl(text, streaming: true);
      expect(sw.elapsedMilliseconds, lessThan(40));
    });

    test('math content is not parsed as Markdown', () {
      expect(inl(r'$a*b*c_d_$'), [const InlineMath('a*b*c_d_')]);
      expect(inl(r'$[x](y)$'), [const InlineMath('[x](y)')]);
    });

    test('prices are left alone', () {
      expect(inl(r'costs $5 and $10'), [t(r'costs $5 and $10')]);
      expect(inl(r'from $5-$10 a month'), [t(r'from $5-$10 a month')]);
      expect(inl(r'$5.99, or $ 3'), [t(r'$5.99, or $ 3')]);
      expect(inl(r'$5. Then $x$ wins'), [
        t(r'$5. Then '),
        const InlineMath('x'),
        t(' wins'),
      ]);
    });

    test('Pandoc rules for the closing dollar', () {
      expect(inl(r'$x $'), [t(r'$x $')], reason: 'space before closer');
      expect(inl(r'$x$5'), [t(r'$x$5')], reason: 'digit after closer');
      expect(inl(r'$ x$'), [t(r'$ x$')], reason: 'space after opener');
      expect(inl(r'$$$$'), [t(r'$$$$')], reason: 'empty display math');
    });

    test(r'\$ is a literal dollar, also inside math', () {
      expect(inl(r'a \$5 fee'), [t(r'a $5 fee')]);
      expect(inl(r'$a\$b$'), [const InlineMath(r'a\$b')]);
    });

    test('with math disabled, dollars and escapes behave as before', () {
      expect(inl(r'$x$ and \(y\)', math: false), [t(r'$x$ and (y)')]);
    });

    test('plain alt text of an image keeps the TeX', () {
      final img = inl(r'![area $r^2$](a.png)').single as InlineImage;
      expect(img.alt, 'area r^2');
    });
  });

  group('inline math while streaming', () {
    test(r'unclosed $\ (unambiguous TeX) is shown as open math', () {
      expect(inl(r'value $\frac{a}{', streaming: true), [
        t('value '),
        const InlineMath(r'\frac{a}{', isOpen: true),
      ]);
    });

    test('other unclosed math stays text until it closes', () {
      expect(inl(r'see \(a + ', streaming: true), [t('see (a + ')]);
      expect(inl(r'see \(a + b\)', streaming: true), [
        t('see '),
        const InlineMath('a + b'),
      ]);
      expect(inl(r'so $$x', streaming: true), [t(r'so $$x')]);
      expect(inl(r'so $x^2 +', streaming: true), [t(r'so $x^2 +')]);
    });

    test('a price is not speculatively shown as math', () {
      expect(inl(r'it costs $5', streaming: true), [t(r'it costs $5')]);
      expect(inl(r'it costs $5 or $', streaming: true), [
        t(r'it costs $5 or '),
      ]);
    });

    test('a trailing dollar or backslash is held back', () {
      expect(inl(r'cost: $', streaming: true), [t('cost: ')]);
      expect(inl(r'see \', streaming: true), [t('see ')]);
      expect(inl(r'then $x$', streaming: true), [t(r'then $x')]);
      expect(inl(r'So \[', streaming: true), [t('So ')]);
      expect(inl(r'So \(', streaming: true), [t('So (')]);
    });
  });

  group('math blocks', () {
    test(r'$$ on its own lines', () {
      final doc = IncrementalMarkdownParser.parse(
        'Formula:\n\$\$\n\\int_0^1 x\\,dx\n= \\tfrac12\n\$\$\nAfter.',
      );
      expect(doc.blocks, hasLength(3));
      expect(doc.blocks[1], isA<MathBlock>());
      expect((doc.blocks[1] as MathBlock).tex, '\\int_0^1 x\\,dx\n= \\tfrac12');
      expect(doc.blocks[2], isA<ParagraphBlock>());
    });

    test(r'one-line $$…$$ and \[…\] blocks', () {
      expect((first(r'$$E=mc^2$$') as MathBlock).tex, 'E=mc^2');
      expect((first('\\[\na^2\n\\]') as MathBlock).tex, 'a^2');
      expect((first(r'\[ x \]') as MathBlock).tex, 'x');
    });

    test(r'TeX after an opening $$ makes a paragraph with display math', () {
      final p = first('\$\$ a\nb \$\$') as ParagraphBlock;
      expect(p.children.single, const InlineMath('a\nb', display: true));
    });

    test('prose starting with \$\$ or \\[ does not swallow the document', () {
      for (final md in [
        '\$\$ is the shell PID.\n\nNext.\n\n# Heading',
        '\\[note] see below\n\nNext.\n\n# Heading',
        '\\[1\\] Smith et al.\n\nNext.\n\n# Heading',
      ]) {
        final doc = IncrementalMarkdownParser.parse(md);
        expect(doc.blocks.map((b) => b.runtimeType), [
          ParagraphBlock,
          ParagraphBlock,
          HeadingBlock,
        ], reason: md);
      }
    });

    test('an unclosed block ends at a blank line and is re-read as text', () {
      final doc = IncrementalMarkdownParser.parse(
        'text\n\$\$\nx\n\nblank inside\n\n# Head',
      );
      expect(doc.blocks.map((b) => b.runtimeType), [
        ParagraphBlock,
        ParagraphBlock,
        ParagraphBlock,
        HeadingBlock,
      ]);
      expect(
        (doc.blocks[1] as ParagraphBlock).children.first,
        const InlineText(r'$$'),
      );
    });

    test('a closer followed by text closes the block', () {
      final doc = IncrementalMarkdownParser.parse('\$\$\nx\n\$\$ trailing\n');
      expect((doc.blocks[0] as MathBlock).tex, 'x');
      expect(doc.blocks[1], isA<ParagraphBlock>());
    });

    test('an escaped closer does not close the block', () {
      final m = first('\$\$\na \\\$\$\nb\n\$\$') as MathBlock;
      expect(m.tex, 'a \\\$\$\nb');
      final b = first('\\[\nx \\\\]\ny\n\\]') as MathBlock;
      expect(b.tex, 'x \\\\]\ny');
    });

    test('empty one-line blocks are text', () {
      expect(first(r'$$ $$'), isA<ParagraphBlock>());
      expect(first(r'\[\]'), isA<ParagraphBlock>());
    });

    test(r'$$…$$ followed by text is a paragraph', () {
      final p = first(r'$$x$$ is the answer') as ParagraphBlock;
      expect(p.children.first, const InlineMath('x', display: true));
    });

    test(r'$$$ does not open a math block', () {
      expect(first(r'$$$ money'), isA<ParagraphBlock>());
    });

    test('a math block interrupts a paragraph', () {
      final doc = IncrementalMarkdownParser.parse('text\n\$\$\nx\n\$\$');
      expect(doc.blocks.map((b) => b.runtimeType), [ParagraphBlock, MathBlock]);
    });

    test('inside list items and block quotes', () {
      final list = first('- a:\n  \$\$\n  y\n  \$\$\n') as ListBlock;
      expect(list.items.single.children.last, isA<MathBlock>());
      final quote = first('> \$\$\n> q\n> \$\$\n') as BlockQuoteBlock;
      expect((quote.children.single as MathBlock).tex, 'q');
    });

    test('an unterminated block is text at the end of the input', () {
      final doc = IncrementalMarkdownParser.parse('\$\$\na = 1');
      expect(doc.blocks.single, isA<ParagraphBlock>());
      final item = first('- \$\$\n  a = 1') as ListBlock;
      expect(item.items.single.children.single, isA<ParagraphBlock>());
    });

    test('math disabled: a dollar line is a paragraph', () {
      final doc = IncrementalMarkdownParser.parse(
        '\$\$\nx\n\$\$',
        options: const MarkdownParserOptions(math: false),
      );
      expect(doc.blocks.single, isA<ParagraphBlock>());
    });
  });

  group('math blocks while streaming', () {
    test('an open block grows and is marked open', () {
      final m = streamingBlocks('\$\$\n\\int_0^1\n').single as MathBlock;
      expect(m.isOpen, isTrue);
      expect(m.tex, r'\int_0^1');
    });

    test('a partial opener on the pending line paints nothing', () {
      expect(streamingBlocks('text\n\n\$').length, 1);
      expect(streamingBlocks('text\n\n\$\$').length, 1);
      expect(streamingBlocks('text\n\n\\').length, 1);
    });

    test('a partial closer is not painted inside the math', () {
      expect((streamingBlocks('\$\$\nx\n\$').single as MathBlock).tex, 'x');
      expect(
        (streamingBlocks('\$\$\nx\n\$\$').single as MathBlock).isOpen,
        isTrue,
      );
      expect((streamingBlocks('\$\$\nx \$').single as MathBlock).tex, 'x');
      expect((streamingBlocks('\\[\nx \\').single as MathBlock).tex, 'x');
    });

    test(r'a TeX line break \\ is kept while streaming', () {
      expect((streamingBlocks('\\[\na \\\\').single as MathBlock).tex, r'a \\');
    });

    test('a one-line block on the pending line stays open', () {
      final m = streamingBlocks(r'$$E=mc^2$$').single as MathBlock;
      expect(m.isOpen, isTrue);
      final done = IncrementalMarkdownParser.parse(r'$$E=mc^2$$').blocks.single;
      expect(done.isOpen, isFalse);
    });

    test(
      'closed math blocks keep their identity while streaming continues',
      () {
        final p = IncrementalMarkdownParser()..append('\$\$\nx\n\$\$\n\nmore');
        final before = p.document.blocks.first;
        p.append(' text');
        expect(identical(p.document.blocks.first, before), isTrue);
      },
    );
  });
}
