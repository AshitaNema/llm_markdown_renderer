import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown_renderer/parser.dart';
import 'package:llm_markdown_renderer/src/parser/inline_parser.dart';

import '../helpers.dart';

List<Inline> inl(String s, {bool streaming = false, bool citations = true}) =>
    parseInlines(
      s,
      streaming: streaming,
      options: MarkdownParserOptions(citations: citations),
    );

const t = InlineText.new;

List<Block> streamingBlocks(String md) =>
    (IncrementalMarkdownParser()..append(md)).document.blocks;

void main() {
  group('citations', () {
    test('numbers, lists and footnote-style labels', () {
      expect(inl('capital [1].'), [
        t('capital '),
        const InlineCitation(['1']),
        t('.'),
      ]);
      expect(inl('[1, 2][3]'), [
        const InlineCitation(['1', '2']),
        const InlineCitation(['3']),
      ]);
      expect(inl('[^note] and [^1]'), [
        const InlineCitation(['note'], source: '[^note]'),
        t(' and '),
        const InlineCitation(['1'], source: '[^1]'),
      ]);
    });

    test('footnote references may be glued to a word', () {
      expect(inl('Text[^1].'), [
        t('Text'),
        const InlineCitation(['1'], source: '[^1]'),
        t('.'),
      ]);
    });

    test('the source is kept as written', () {
      final c = inl('see [1,2]')[1] as InlineCitation;
      expect(c.labels, ['1', '2']);
      expect(c.source, '[1,2]');
    });

    test(
      'links, definitions, indexing, tasks and escapes are not citations',
      () {
        expect(inl('[1](http://x)').single, isA<InlineLink>());
        expect(inl('[1]: http://x').first, t('[1]: '));
        expect(inl('[label] [ ] [x] [1a] [1234]'), [
          t('[label] [ ] [x] [1a] [1234]'),
        ]);
        expect(inl(r'\[1\]'), [t('[1]')]);
        for (final code in [
          'array[1]',
          'blue[1][2].',
          'm[i][0]',
          'split()[0]',
          '数组[1]',
          'é[1]',
          'range [0, 1]',
        ]) {
          expect(inl(code), [t(code)], reason: code);
        }
      },
    );

    test('disabled: plain text', () {
      expect(inl('see [1]', citations: false), [t('see [1]')]);
    });

    test('partial markers are held back while streaming', () {
      expect(inl('see [1', streaming: true), [t('see ')]);
      expect(inl('see [1, 2', streaming: true), [t('see ')]);
      expect(inl('see [^no', streaming: true), [t('see ')]);
      expect(inl('see [label', streaming: true), [t('see [label')]);
    });

    test('a marker at the very end waits for the next character', () {
      expect(inl('see [1]', streaming: true), [t('see [1]')]);
      expect(inl('see [1] ', streaming: true), [
        t('see '),
        const InlineCitation(['1']),
        t(' '),
      ]);
      expect(inl('[1]:', streaming: true), [t('[1]:')]);
    });

    test('indexing and escapes are not held back while streaming', () {
      expect(inl('a[1', streaming: true), [t('a[1')]);
      expect(inl(r'foo \[1', streaming: true), [t('foo [1')]);
    });

    test('alt text keeps the marker', () {
      final img = inl('![chart [1] here](a.png)').single as InlineImage;
      expect(img.alt, 'chart [1] here');
    });
  });

  group('thinking sections', () {
    test('content is ordinary Markdown, followed by the answer', () {
      final doc = IncrementalMarkdownParser.parse(
        '<think>\nThe user asks X.\n\n- a\n- b\n</think>\n\nAnswer.',
      );
      final th = doc.blocks[0] as ThinkingBlock;
      expect(th.children.map((b) => b.runtimeType), [
        ParagraphBlock,
        ListBlock,
      ]);
      expect(doc.blocks[1], isA<ParagraphBlock>());
    });

    test('tags on the same line as text, either name, any case', () {
      final a = IncrementalMarkdownParser.parse(
        '<think>Quick.</think>\nAnswer.',
      );
      expect((a.blocks[0] as ThinkingBlock).children, hasLength(1));
      expect(a.blocks[1], isA<ParagraphBlock>());
      final b = IncrementalMarkdownParser.parse(
        '<Thinking>\nA\nend.</THINKING>',
      );
      expect(
        (b.blocks.single as ThinkingBlock).children.single,
        isA<ParagraphBlock>(),
      );
    });

    test('only at the start of the reply', () {
      for (final md in [
        'Intro\n<think>\nx\n</think>',
        'Intro\n\n<think> tags wrap reasoning.\n\nMore.\n\n# Heading',
      ]) {
        final doc = IncrementalMarkdownParser.parse(md);
        expect(doc.blocks.whereType<ThinkingBlock>(), isEmpty, reason: md);
      }
      expect(first('\n\n<think>\nx\n</think>'), isA<ThinkingBlock>());
    });

    test('</think> inside code does not close the section', () {
      final doc = IncrementalMarkdownParser.parse(
        '<think>\n```html\n<p></think></p>\n</think>\n```\n'
        'use `</think>` here\n</think>\nAnswer',
      );
      final th = doc.blocks[0] as ThinkingBlock;
      expect(th.children.map((b) => b.runtimeType), [
        CodeBlock,
        ParagraphBlock,
      ]);
      expect((th.children[0] as CodeBlock).lines, [
        '<p></think></p>',
        '</think>',
      ]);
      expect(doc.blocks[1], isA<ParagraphBlock>());
    });

    test('text after the closing tag starts the answer', () {
      final doc = IncrementalMarkdownParser.parse(
        '<think>\nhmm\n</think> The answer is **42**.',
      );
      expect(doc.blocks, hasLength(2));
      expect(doc.blocks[1], isA<ParagraphBlock>());
    });

    test('only at the top level, and not inside code', () {
      expect(first('- <think>\n  x\n  </think>'), isA<ListBlock>());
      expect(first('```\n<think>\n```'), isA<CodeBlock>());
    });

    test('an unclosed section ends with the input', () {
      final th = first('<think>\nstill going') as ThinkingBlock;
      expect(th.isOpen, isFalse);
      expect(th.children.single, isA<ParagraphBlock>());
    });

    test('disabled: the tags are text', () {
      final doc = IncrementalMarkdownParser.parse(
        '<think>\nx\n</think>',
        options: const MarkdownParserOptions(thinking: false),
      );
      expect(doc.blocks.single, isA<ParagraphBlock>());
    });
  });

  group('thinking sections while streaming', () {
    test('open from the first line, growing', () {
      final th = streamingBlocks('<think>').single as ThinkingBlock;
      expect(th.isOpen, isTrue);
      expect(th.children, isEmpty);
      final th2 =
          streamingBlocks('<think>\nThe user\n\nLet me').single
              as ThinkingBlock;
      expect(th2.children, hasLength(2));
      expect(th2.children.last.isOpen, isTrue);
    });

    test('partial tags are not painted', () {
      expect(streamingBlocks('<thi'), isEmpty);
      final th = streamingBlocks('<think>\nhmm\n</thi').single as ThinkingBlock;
      expect(th.children.single, isA<ParagraphBlock>());
      for (var k = 1; k <= '</think'.length; k++) {
        final md = '<think>\nok done.${'</think'.substring(0, k)}';
        final para =
            (streamingBlocks(md).single as ThinkingBlock).children.single
                as ParagraphBlock;
        expect(para.children, [const InlineText('ok done.')], reason: md);
      }
    });

    test('finished blocks inside keep their identity', () {
      final p = IncrementalMarkdownParser()
        ..append('<think>\nfirst para\n\nsecond');
      final firstPara = (p.document.blocks.single as ThinkingBlock).children[0];
      p.append(' grows');
      final again = (p.document.blocks.single as ThinkingBlock).children[0];
      expect(identical(firstPara, again), isTrue);
    });

    test('each append costs the same however long the section is', () {
      int costOfAppend(int paragraphs) {
        final p = IncrementalMarkdownParser()..append('<think>\n');
        for (var k = 0; k < paragraphs; k++) {
          p.append('Paragraph $k with **bold**.\n\n');
        }
        p
          ..append('tail')
          ..document;
        final before = p.debugInlineParseCount;
        p
          ..append(' more')
          ..document;
        return p.debugInlineParseCount - before;
      }

      expect(costOfAppend(1500), costOfAppend(10));
    });
  });
}
