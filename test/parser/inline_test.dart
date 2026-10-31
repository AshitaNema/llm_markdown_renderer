import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown_renderer/parser.dart';

List<Inline> inl(String s, {bool streaming = false}) =>
    parseInlines(s, streaming: streaming);

const t = InlineText.new;

void main() {
  group('emphasis', () {
    test('strong, em, strike, nesting', () {
      expect(inl('**a**'), [
        InlineStrong([t('a')]),
      ]);
      expect(inl('*a*'), [
        InlineEmphasis([t('a')]),
      ]);
      expect(inl('_a_'), [
        InlineEmphasis([t('a')]),
      ]);
      expect(inl('~~a~~'), [
        InlineStrikethrough([t('a')]),
      ]);
      expect(inl('***a***'), [
        InlineEmphasis([
          InlineStrong([t('a')]),
        ]),
      ]);
      expect(inl('**a *b* c**'), [
        InlineStrong([
          t('a '),
          InlineEmphasis([t('b')]),
          t(' c'),
        ]),
      ]);
    });

    test('intraword underscores are literal, asterisks work', () {
      expect(inl('snake_case_name'), [t('snake_case_name')]);
      expect(inl('a*b*c'), [
        t('a'),
        InlineEmphasis([t('b')]),
        t('c'),
      ]);
    });

    test('spaces around delimiters prevent emphasis', () {
      expect(inl('a * b * c'), [t('a * b * c')]);
    });

    test('unclosed delimiters are literal when not streaming', () {
      expect(inl('**bold'), [t('**bold')]);
    });

    test('single tilde is literal', () {
      expect(inl('~a~'), [t('~a~')]);
    });
  });

  group('code spans', () {
    test('plain, double backtick, stripped padding', () {
      expect(inl('`a`'), [const InlineCode('a')]);
      expect(inl('`` a`b ``'), [const InlineCode('a`b')]);
    });

    test('markup inside code is literal', () {
      expect(inl('`**x**`'), [const InlineCode('**x**')]);
    });

    test('unclosed backtick is literal when not streaming', () {
      expect(inl('a ` b'), [t('a ` b')]);
    });
  });

  group('links & images', () {
    test('inline link with title and nested emphasis in label', () {
      expect(inl('[a **b**](http://x.y "T")'), [
        InlineLink(
          url: 'http://x.y',
          title: 'T',
          children: [
            t('a '),
            InlineStrong([t('b')]),
          ],
        ),
      ]);
    });

    test('parentheses in URLs', () {
      expect(inl('[a](http://x.y/(z))'), [
        InlineLink(url: 'http://x.y/(z)', children: [t('a')]),
      ]);
    });

    test('image', () {
      expect(inl('![alt *text*](a.png)'), [
        const InlineImage(url: 'a.png', alt: 'alt text'),
      ]);
    });

    test('brackets without a destination are literal', () {
      expect(inl('[x] and [y]'), [t('[x] and [y]')]);
    });

    test('autolinks: <url>, bare url with trailing punctuation', () {
      expect(inl('<https://a.b/c>'), [
        InlineLink(url: 'https://a.b/c', children: [t('https://a.b/c')]),
      ]);
      expect(inl('see https://a.b/c.'), [
        t('see '),
        InlineLink(url: 'https://a.b/c', children: [t('https://a.b/c')]),
        t('.'),
      ]);
      expect(inl('(https://a.b/c)'), [
        t('('),
        InlineLink(url: 'https://a.b/c', children: [t('https://a.b/c')]),
        t(')'),
      ]);
    });

    test('bare urls may contain underscores', () {
      final out = inl('https://a.b/x_y_z');
      expect(out.single, isA<InlineLink>());
    });

    test('autolinks can be disabled', () {
      expect(
        parseInlines(
          'https://a.b',
          options: const MarkdownParserOptions(autolinks: false),
        ),
        [t('https://a.b')],
      );
    });

    test('word ending in h before a url is not mangled', () {
      expect(inl('with http only'), [t('with http only')]);
    });
  });

  group('escapes, entities, breaks', () {
    test('backslash escapes', () {
      expect(inl(r'\*not em\* \_ \\'), [t(r'*not em* _ \')]);
    });

    test('entities', () {
      expect(inl('&amp; &lt; &#65; &#x42; &nope; &'), [t('& < A B &nope; &')]);
    });

    test('soft, hard (spaces) and hard (backslash) breaks', () {
      expect(inl('a\nb'), [t('a'), const InlineSoftBreak(), t('b')]);
      expect(inl('a  \nb'), [t('a'), const InlineLineBreak(), t('b')]);
      expect(inl('a\\\nb'), [t('a'), const InlineLineBreak(), t('b')]);
    });
  });

  group('streaming mode', () {
    test('unclosed strong/em/strike are closed speculatively', () {
      expect(inl('**bo', streaming: true), [
        InlineStrong([t('bo')]),
      ]);
      expect(inl('a *b', streaming: true), [
        t('a '),
        InlineEmphasis([t('b')]),
      ]);
      expect(inl('~~x', streaming: true), [
        InlineStrikethrough([t('x')]),
      ]);
      expect(inl('**a *b', streaming: true), [
        InlineStrong([
          t('a '),
          InlineEmphasis([t('b')]),
        ]),
      ]);
    });

    test('a delimiter with nothing after it is hidden', () {
      expect(inl('text **', streaming: true), [t('text ')]);
    });

    test('a partial closing delimiter does not flash a literal asterisk', () {
      final full = inl('**bold**', streaming: true);
      expect(inl('**bold*', streaming: true), full);
      expect(inl('**bold', streaming: true), full);
    });

    test('unclosed code span renders as code, nothing for a lone backtick', () {
      expect(inl('use `fo', streaming: true), [
        t('use '),
        const InlineCode('fo'),
      ]);
      expect(inl('use `', streaming: true), [t('use ')]);
    });

    test('incomplete links show the label only', () {
      expect(inl('see [docs](http://exa', streaming: true), [t('see docs')]);
      expect(inl('see [docs](', streaming: true), [t('see docs')]);
      expect(inl('see [docs]', streaming: true), [t('see [docs]')]);
      expect(inl('see [do', streaming: true), [t('see [do')]);
      expect(inl('see [', streaming: true), [t('see ')]);
    });

    test('incomplete images are hidden', () {
      expect(inl('x ![alt](htt', streaming: true), [t('x ')]);
    });

    test('a link becomes a link the moment its ) arrives', () {
      expect(inl('[a](http://x.y)', streaming: true), [
        InlineLink(url: 'http://x.y', children: [t('a')]),
      ]);
    });

    test('snake_case is not eaten', () {
      expect(inl('call my_func_name', streaming: true), [
        t('call my_func_name'),
      ]);
    });
  });
}
