/// Markdown samples used across the test suite. They deliberately contain
/// every construct that is easy to get wrong when a chunk boundary falls in
/// the middle of it.
const Map<String, String> fixtures = {
  'mixed': '''# Title

Some **bold**, *em*, ~~gone~~ and `code` with a [link](https://example.com "t").

- item one
- item two
  - nested a
  - nested b

1. first
2. second

> quote line
> more quote

---

Setext heading
==============

Final paragraph.
''',
  'fenced':
      'Intro:\n\n```dart\nvoid main() {\n  print("```");\n}\n```\n\nAfter.\n',
  'fence-tilde-long': '~~~~python\nx = """\n~~~\n"""\n~~~~\ndone\n',
  'unclosed-fence': 'Text\n\n```js\nconst a = 1;\nconst b = 2;',
  'table':
      'Before\n| a | b | c |\n|---|:-:|--:|\n| 1 | 2 | 3 |\n| x | **y** | z |\n\nAfter table\n',
  'table-unterminated': '| h1 | h2 |\n| -- | -- |\n| a | b',
  'nested-lists':
      '1. one\n   - a\n   - b\n     1. deep\n2. two\n\n   para in item\n3. three\n- [ ] todo\n- [x] done\n',
  'crlf':
      '# Head\r\n\r\npara one\r\nline two\r\n\r\n- a\r\n- b\r\n\r\n```sh\r\necho hi\r\n```\r\n',
  'cr-only': 'a\rb\r\rc\r',
  'emoji': 'Hello 👋 **wörld 🌍** and `ço`\n\n- 🍎 apple\n- 🍌 banana\n',
  'inline-edge':
      'a * b * c and snake_case_word and **unclosed bold\n\n`unclosed code\n\n[link](http://x.y/(z)) and ![img](a.png "t") and <https://auto.link> and https://bare.url/path.\n',
  'html-entities': 'Tom &amp; Jerry &lt;3 &#128512; &bogus; done\n',
  'hard-break': 'line one  \nline two\\\nline three\n',
  'empty-and-blank': '\n\n\n   \nword\n\n\n',
  'indented-code': 'para\n\n    code line 1\n\n    code line 2\n\nafter\n',
  'quote-lazy': '> quote\nlazy continuation\n\n> second\n> - item\n> - item2\n',
  'tabs': '-\titem\n\n\tcode?\n',
  'setext-vs-table': 'Header | Two\n--- | ---\ncell | cell\n',
  'math':
      r'''Euler: $e^{i\pi}+1=0$, costs $5 and $10, \$3 fee, so $$x^2$$ and \(a\) or \[b\].
Formula:
$$
\int_0^1 x\,dx
= \tfrac12
$$

$$E=mc^2$$

\[
a^2+b^2
\]
- item $y$
- block:
  $$
  z
  $$
''',
  'math-unclosed': r'''Value $\frac{a}{b and $$
x = 1
\\
''',
};
