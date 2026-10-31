import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown_renderer/parser.dart';

List<Block> parse(String md) => IncrementalMarkdownParser.parse(md).blocks;

void main() {
  group('headings & rules', () {
    test('ATX levels and closing hashes', () {
      final h = parse('### Hello ##').single as HeadingBlock;
      expect(h.level, 3);
      expect(h.children, [const InlineText('Hello')]);
    });

    test('# without a space is not a heading', () {
      expect(parse('#hashtag').single, isA<ParagraphBlock>());
    });

    test('setext headings', () {
      expect((parse('Title\n=====').single as HeadingBlock).level, 1);
      expect((parse('Title\n-----').single as HeadingBlock).level, 2);
    });

    test('thematic breaks', () {
      for (final hr in ['---', '***', '___', '- - -', '  ***  ']) {
        expect(parse(hr).single, isA<ThematicBreakBlock>(), reason: hr);
      }
    });
  });

  group('paragraphs', () {
    test('lines join with soft breaks', () {
      final p = parse('a\nb').single as ParagraphBlock;
      expect(p.children, [
        const InlineText('a'),
        const InlineSoftBreak(),
        const InlineText('b'),
      ]);
    });

    test('blank line separates paragraphs', () {
      expect(parse('a\n\nb'), hasLength(2));
    });

    test('heading, fence, quote and list interrupt a paragraph', () {
      final blocks = parse(
        'text\n# h\ntext2\n```\nc\n```\ntext3\n> q\ntext4\n- l',
      );
      expect(blocks.map((b) => b.runtimeType), [
        ParagraphBlock,
        HeadingBlock,
        ParagraphBlock,
        CodeBlock,
        ParagraphBlock,
        BlockQuoteBlock,
        ListBlock,
      ]);
    });

    test(
      'an ordered list not starting at 1 does not interrupt a paragraph',
      () {
        expect(parse('text\n2. not a list'), hasLength(1));
        expect(parse('text\n1. a list'), hasLength(2));
      },
    );
  });

  group('code', () {
    test('fenced block keeps language, info and inner indentation', () {
      final c =
          parse('```dart title="x"\n  indented\n\nblank above\n```').single
              as CodeBlock;
      expect(c.language, 'dart');
      expect(c.info, 'dart title="x"');
      expect(c.lines, ['  indented', '', 'blank above']);
      expect(c.isOpen, isFalse);
    });

    test('longer fence is not closed by a shorter one', () {
      final c = parse('````\n```\ninner\n```\n````\nafter');
      expect((c.first as CodeBlock).lines, ['```', 'inner', '```']);
      expect(c, hasLength(2));
    });

    test('fence content is never interpreted as markdown', () {
      final c =
          parse(
                '```\n# not a heading\n- not a list\n| not | table |\n```',
              ).single
              as CodeBlock;
      expect(c.lines, hasLength(3));
    });

    test(
      'unclosed fence stays open while streaming, closed after complete',
      () {
        final p = IncrementalMarkdownParser()..append('```py\nprint(1)\n');
        expect(p.document.blocks.single.isOpen, isTrue);
        p.complete();
        expect(p.document.blocks.single.isOpen, isFalse);
      },
    );

    test('backtick fence info may not contain backticks', () {
      expect(parse('``` code ```').single, isA<ParagraphBlock>());
    });

    test('indented code', () {
      final c = parse('    a\n\n    b').single as CodeBlock;
      expect(c.isFenced, isFalse);
      expect(c.lines, ['a', '', 'b']);
    });

    test('fence inside a list item', () {
      final l =
          parse('1. step\n\n   ```sh\n   run\n   ```\n2. next').single
              as ListBlock;
      final code = l.items.first.children.whereType<CodeBlock>().single;
      expect(code.lines, ['run']);
      expect(l.items, hasLength(2));
    });
  });

  group('lists', () {
    test('bullets and ordered numbering', () {
      final l = parse('3. a\n4. b').single as ListBlock;
      expect(l.ordered, isTrue);
      expect(l.start, 3);
      expect(l.items, hasLength(2));
    });

    test('changing bullet type starts a new list', () {
      expect(parse('- a\n* b'), hasLength(2));
    });

    test('nested with 2 spaces under a bullet and under an ordered item', () {
      final a = parse('- a\n  - b').single as ListBlock;
      expect(a.items.single.children.last, isA<ListBlock>());
      final b = parse('1. a\n  - b').single as ListBlock;
      expect(b.items.single.children.last, isA<ListBlock>());
    });

    test('lazy continuation joins the item paragraph', () {
      final l = parse('- a\nb').single as ListBlock;
      final p = l.items.single.children.single as ParagraphBlock;
      expect(p.children, hasLength(3));
    });

    test('blank line then unindented text ends the list', () {
      final blocks = parse('- a\n\nb');
      expect(blocks, hasLength(2));
      expect(blocks.last, isA<ParagraphBlock>());
    });

    test('task lists', () {
      final l = parse('- [ ] todo\n- [x] done\n- plain').single as ListBlock;
      expect(l.items.map((i) => i.checked), [false, true, null]);
      expect((l.items[0].children.single as ParagraphBlock).children, [
        const InlineText('todo'),
      ]);
    });

    test('task lists can be disabled', () {
      final doc = IncrementalMarkdownParser.parse(
        '- [x] a',
        options: const MarkdownParserOptions(taskLists: false),
      );
      expect((doc.blocks.single as ListBlock).items.single.checked, isNull);
    });

    test('tight vs loose items', () {
      final tight = parse('- a\n- b').single as ListBlock;
      expect(tight.items.map((i) => i.isLoose), [false, false]);
      final loose = parse('- a\n\n- b').single as ListBlock;
      expect(loose.items.map((i) => i.isLoose), [true, false]);
    });

    test('list items other than the last are closed while streaming', () {
      final p = IncrementalMarkdownParser()..append('- a\n- b\n- c');
      final l = p.document.blocks.single as ListBlock;
      expect(l.items.map((i) => i.isOpen), [false, false, true]);
    });

    test('markers with emphasis are not list items', () {
      expect(parse('**bold** text').single, isA<ParagraphBlock>());
      expect(parse('*emph* text').single, isA<ParagraphBlock>());
    });
  });

  group('block quotes', () {
    test('basic and nested content', () {
      final q = parse('> # h\n> text\n> - item').single as BlockQuoteBlock;
      expect(q.children.map((b) => b.runtimeType), [
        HeadingBlock,
        ParagraphBlock,
        ListBlock,
      ]);
    });

    test('lazy continuation and termination by blank line', () {
      final blocks = parse('> a\nb\n\nc');
      expect(blocks, hasLength(2));
      final q = blocks.first as BlockQuoteBlock;
      expect((q.children.single as ParagraphBlock).children, hasLength(3));
    });
  });

  group('tables', () {
    test('alignments, header and rows', () {
      final t =
          parse('|a|b|c|d|\n|:--|:-:|--:|---|\n|1|2|3|4|').single as TableBlock;
      expect(t.alignments, [
        TableAlignment.left,
        TableAlignment.center,
        TableAlignment.right,
        TableAlignment.none,
      ]);
      expect(t.header, hasLength(4));
      expect(t.rows.single, hasLength(4));
    });

    test('a table can directly follow a paragraph line', () {
      final blocks = parse('Here is a table:\n| a | b |\n|---|---|\n| 1 | 2 |');
      expect(blocks.map((b) => b.runtimeType), [ParagraphBlock, TableBlock]);
    });

    test('short rows are padded and long rows truncated', () {
      final t =
          parse('| a | b |\n|---|---|\n| 1 |\n| 1 | 2 | 3 |').single
              as TableBlock;
      expect(t.rows[0], hasLength(2));
      expect(t.rows[0][1], isEmpty);
      expect(t.rows[1], hasLength(2));
    });

    test('escaped pipes stay inside the cell', () {
      final t = parse('| a |\n|---|\n| x \\| y |').single as TableBlock;
      expect(t.rows.single.single, [const InlineText('x | y')]);
    });

    test('header/delimiter column mismatch is not a table', () {
      expect(parse('| a | b |\n|---|').single, isA<ParagraphBlock>());
    });

    test('table ends at blank line and at a pipe-less line', () {
      expect(parse('|a|\n|-|\n|1|\n\ntext').length, 2);
      expect(parse('|a|\n|-|\n|1|\ntext').length, 2);
    });

    test('tables can be disabled', () {
      final doc = IncrementalMarkdownParser.parse(
        '|a|\n|-|\n|1|',
        options: const MarkdownParserOptions(tables: false),
      );
      expect(doc.blocks.single, isA<ParagraphBlock>());
    });

    test('streaming: header alone is a paragraph, the delimiter row makes the '
        'table, a partial row has stable shape', () {
      final p = IncrementalMarkdownParser()..append('| a | b |\n');
      expect(p.document.blocks.single, isA<ParagraphBlock>());
      p.append('|---|---|\n');
      expect(p.document.blocks.single, isA<TableBlock>());
      p.append('| 1 | par');
      final t = p.document.blocks.single as TableBlock;
      expect(t.isOpen, isTrue);
      expect(t.rows.single, hasLength(2));
      expect(t.rows.single[1], [const InlineText('par')]);
    });
  });

  group('streaming previews hide ambiguous partial markers', () {
    Block tail(String md) =>
        (IncrementalMarkdownParser()..append(md)).document.blocks.last;

    test('a bare list marker on the pending line paints nothing', () {
      final p = IncrementalMarkdownParser()..append('para\n-');
      expect(p.document.blocks, hasLength(1));
      expect((p.document.blocks.single as ParagraphBlock).children, [
        const InlineText('para'),
      ]);
    });

    test('partial fence backticks are not painted as text', () {
      expect(
        (IncrementalMarkdownParser()..append('hi\n\n``')).document.blocks,
        hasLength(1),
      );
    });

    test('three backticks immediately show an (empty) code block shell', () {
      final c = tail('hi\n\n```') as CodeBlock;
      expect(c.lines, isEmpty);
      expect(c.isOpen, isTrue);
    });

    test('partial closing fence is not painted inside the code', () {
      final c = tail('```\ncode\n``') as CodeBlock;
      expect(c.lines, ['code']);
    });

    test('a growing heading line is painted as a heading', () {
      final h = tail('# Hel') as HeadingBlock;
      expect(h.children, [const InlineText('Hel')]);
      expect(h.isOpen, isTrue);
    });

    test('bare "#" is hidden', () {
      expect(
        (IncrementalMarkdownParser()..append('#')).document.blocks,
        isEmpty,
      );
    });

    test('partial delimiter row does not flash as paragraph text', () {
      final blocks = (IncrementalMarkdownParser()..append('| a | b |\n|--'))
          .document
          .blocks;
      expect(blocks.single, isA<ParagraphBlock>());
      expect((blocks.single as ParagraphBlock).children, [
        const InlineText('| a | b |'),
      ]);
    });
  });

  test('block ids are stable across snapshots and unique among siblings', () {
    final p = IncrementalMarkdownParser()..append('# a\n\npara');
    final ids1 = p.document.blocks.map((b) => b.id).toList();
    p.append(' more');
    final ids2 = p.document.blocks.map((b) => b.id).toList();
    expect(ids2, ids1);
    expect(ids1.toSet(), hasLength(ids1.length));
  });
}
