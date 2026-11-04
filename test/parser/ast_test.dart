import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown_renderer/parser.dart';

const _text = [InlineText('a')];
const _other = [InlineText('b')];
const _para = [ParagraphBlock(id: 1, isOpen: false, children: _text)];
const _otherPara = [ParagraphBlock(id: 1, isOpen: false, children: _other)];

/// [same] equals [value] and [different] does not; [printed] is its
/// `toString`.
class _Case {
  const _Case(this.value, this.same, this.different, this.printed);
  final Object value;
  final Object same;
  final Object different;
  final String printed;
}

const _cases = <String, _Case>{
  'InlineText': _Case(
    InlineText('a'),
    InlineText('a'),
    InlineText('b'),
    'Text(a)',
  ),
  'InlineEmphasis': _Case(
    InlineEmphasis(_text),
    InlineEmphasis(_text),
    InlineEmphasis(_other),
    'Em([Text(a)])',
  ),
  'InlineStrong': _Case(
    InlineStrong(_text),
    InlineStrong(_text),
    InlineStrong(_other),
    'Strong([Text(a)])',
  ),
  'InlineStrikethrough': _Case(
    InlineStrikethrough(_text),
    InlineStrikethrough(_text),
    InlineStrikethrough(_other),
    'Strike([Text(a)])',
  ),
  'InlineCode': _Case(
    InlineCode('a'),
    InlineCode('a'),
    InlineCode('b'),
    'Code(a)',
  ),
  'InlineMath': _Case(
    InlineMath('x'),
    InlineMath('x'),
    InlineMath('x', isOpen: true),
    'Math(x)',
  ),
  'InlineMath display': _Case(
    InlineMath('x', display: true),
    InlineMath('x', display: true),
    InlineMath('x'),
    'DisplayMath(x)',
  ),
  'InlineCitation': _Case(
    InlineCitation(['1', '2']),
    InlineCitation(['1', '2'], source: '[1, 2]'),
    InlineCitation(['1', '2'], source: '[1,2]'),
    'Cite(1,2)',
  ),
  'InlineLink': _Case(
    InlineLink(url: 'u', title: 't', children: _text),
    InlineLink(url: 'u', title: 't', children: _text),
    InlineLink(url: 'v', title: 't', children: _text),
    'Link(u, [Text(a)])',
  ),
  'InlineImage': _Case(
    InlineImage(url: 'u', alt: 'a'),
    InlineImage(url: 'u', alt: 'a'),
    InlineImage(url: 'u', alt: 'b'),
    'Image(u, a)',
  ),
  'InlineLineBreak': _Case(
    InlineLineBreak(),
    InlineLineBreak(),
    InlineSoftBreak(),
    'LineBreak',
  ),
  'InlineSoftBreak': _Case(
    InlineSoftBreak(),
    InlineSoftBreak(),
    InlineLineBreak(),
    'SoftBreak',
  ),
  'ParagraphBlock': _Case(
    ParagraphBlock(id: 1, isOpen: false, children: _text),
    ParagraphBlock(id: 2, isOpen: false, children: _text),
    ParagraphBlock(id: 1, isOpen: true, children: _text),
    'Paragraph([Text(a)])',
  ),
  'HeadingBlock': _Case(
    HeadingBlock(id: 1, isOpen: false, level: 2, children: _text),
    HeadingBlock(id: 2, isOpen: false, level: 2, children: _text),
    HeadingBlock(id: 1, isOpen: false, level: 3, children: _text),
    'Heading2([Text(a)])',
  ),
  'CodeBlock': _Case(
    CodeBlock(
      id: 1,
      isOpen: false,
      lines: ['x'],
      info: 'dart',
      language: 'dart',
    ),
    CodeBlock(
      id: 2,
      isOpen: false,
      lines: ['x'],
      info: 'dart',
      language: 'dart',
    ),
    CodeBlock(
      id: 1,
      isOpen: false,
      lines: ['y'],
      info: 'dart',
      language: 'dart',
    ),
    'Code(dart, 1 lines)',
  ),
  'MathBlock': _Case(
    MathBlock(id: 1, isOpen: false, tex: 'a\nb'),
    MathBlock(id: 2, isOpen: false, tex: 'a\nb'),
    MathBlock(id: 1, isOpen: false, tex: 'c'),
    r'MathBlock(a\nb)',
  ),
  'ThinkingBlock': _Case(
    ThinkingBlock(id: 1, isOpen: false, children: _para),
    ThinkingBlock(id: 2, isOpen: false, children: _para),
    ThinkingBlock(id: 1, isOpen: false, children: _otherPara),
    'Thinking([Paragraph([Text(a)])])',
  ),
  'BlockQuoteBlock': _Case(
    BlockQuoteBlock(id: 1, isOpen: false, children: _para),
    BlockQuoteBlock(id: 2, isOpen: false, children: _para),
    BlockQuoteBlock(id: 1, isOpen: false, children: _otherPara),
    'Quote([Paragraph([Text(a)])])',
  ),
  'ListItem': _Case(
    ListItem(id: 1, isOpen: false, children: _para),
    ListItem(id: 2, isOpen: false, children: _para),
    ListItem(id: 1, isOpen: false, checked: true, children: _para),
    'Item([Paragraph([Text(a)])])',
  ),
  'ListBlock': _Case(
    ListBlock(id: 1, isOpen: false, ordered: true, start: 1, items: []),
    ListBlock(id: 2, isOpen: false, ordered: true, start: 1, items: []),
    ListBlock(id: 1, isOpen: false, ordered: false, start: 1, items: []),
    'List(ol, [])',
  ),
  'TableBlock': _Case(
    TableBlock(
      id: 1,
      isOpen: false,
      alignments: [TableAlignment.left],
      header: [_text],
      rows: [
        [_text],
      ],
    ),
    TableBlock(
      id: 2,
      isOpen: false,
      alignments: [TableAlignment.left],
      header: [_text],
      rows: [
        [_text],
      ],
    ),
    TableBlock(
      id: 1,
      isOpen: false,
      alignments: [TableAlignment.left],
      header: [_text],
      rows: [
        [_other],
      ],
    ),
    'Table(1 cols, 1 rows)',
  ),
  'ThematicBreakBlock': _Case(
    ThematicBreakBlock(id: 1),
    ThematicBreakBlock(id: 2),
    MathBlock(id: 1, isOpen: false, tex: 'x'),
    'Rule',
  ),
};

void main() {
  test('MarkdownDocument compares its blocks and completeness', () {
    final doc = MarkdownDocument(_para, isComplete: true);
    final same = MarkdownDocument(List.of(_para), isComplete: true);
    expect(doc, same);
    expect(doc.hashCode, same.hashCode);
    expect(doc, isNot(MarkdownDocument(_para, isComplete: false)));
    expect(doc.toString(), contains('Paragraph'));
  });

  group('value semantics', () {
    for (final MapEntry(key: name, value: c) in _cases.entries) {
      test('$name: equality, hashCode and toString', () {
        expect(c.value, c.same);
        expect(c.value.hashCode, c.same.hashCode);
        expect(c.value, isNot(c.different));
        expect(c.value.toString(), c.printed);
      });
    }
  });
}
