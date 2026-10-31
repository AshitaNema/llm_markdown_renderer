import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown_renderer/parser.dart';

const hl = CodeHighlighter.defaults();

/// Highlights [code] line by line (carrying state) and returns, per line, the
/// `kind:text` pairs of non-plain tokens.
List<List<String>> lex(String lang, String code, {bool all = false}) {
  Object? state;
  final out = <List<String>>[];
  for (final line in code.split('\n')) {
    final r = hl.highlightLine(lang, line, state);
    state = r.endState;
    out.add([
      for (final t in r.tokens)
        if (t.kind != TokenKind.plain &&
            (all ||
                (t.kind != TokenKind.operator &&
                    t.kind != TokenKind.punctuation)))
          '${t.kind.name}:${line.substring(t.start, t.end)}',
    ]);
  }
  return out;
}

void main() {
  test('tokens are ordered, in range and non-overlapping for every language', () {
    const samples = {
      'dart':
          "import 'a.dart';\n/// doc\nclass A<T> { final int x = 0x1F; String s = 'a\${b}'; }",
      'js': 'const f = (a) => `t\${a}`; // c\nlet x = /* c */ 1;',
      'python':
          '@dec\ndef f(x):\n    """doc\n    more"""\n    return f"{x}" # c',
      'json': '{"a": [1, 2.5e3, true, null], "b": "s"}',
      'bash': 'if [ -f "\$HOME/x" ]; then echo --flag \$1 # c\nfi',
      'yaml': 'key: value\nlist:\n  - a: 1\n  - "q": true # c',
      'sql': "SELECT a, count(*) FROM t WHERE x = 'y' -- c\nORDER BY a;",
      'html': '<!-- c -->\n<div class="a" id=b>text &amp; more</div>',
      'css': 'a.b #c { color: #fff; margin: 0 auto; } /* c */',
      'diff': '--- a\n+++ b\n@@ -1 +1 @@\n-old\n+new\n same',
      'c': '#include <x.h>\nint main(void) { return 0; }',
      'cpp':
          'template<class T> class A { public: virtual void f() override; };',
      'java': '@Override public static void main(String[] a) {}',
      'kotlin': 'fun main() { val x: Int = 1 }',
      'swift': 'func f() -> Int { guard let x = y else { return 0 } }',
      'go': 'func main() { x := `raw` ; fmt.Println("hi") }',
      'rust': "fn main<'a>(x: &'a str) { let y: u8 = 1; }",
      'csharp': 'public async Task<int> F() { await Task.Delay(1); }',
    };
    for (final e in samples.entries) {
      Object? state;
      for (final line in e.value.split('\n')) {
        final r = hl.highlightLine(e.key, line, state);
        state = r.endState;
        var pos = 0;
        for (final t in r.tokens) {
          expect(t.start, greaterThanOrEqualTo(pos), reason: '${e.key}: $line');
          expect(t.end, greaterThan(t.start), reason: '${e.key}: $line');
          expect(
            t.end,
            lessThanOrEqualTo(line.length),
            reason: '${e.key}: $line',
          );
          pos = t.end;
        }
      }
    }
  });

  test('unknown or null language yields no tokens and keeps state', () {
    expect(hl.highlightLine('klingon', 'qapla', null).tokens, isEmpty);
    expect(hl.highlightLine(null, 'x', 'S').endState, 'S');
  });

  test('aliases and case-insensitive language names', () {
    for (final name in ['js', 'JS', 'JavaScript', 'ts', 'tsx']) {
      expect(
        lex(name, 'const a = 1;').single,
        contains('keyword:const'),
        reason: name,
      );
    }
    expect(lex('py', 'def f(): pass').single, contains('keyword:def'));
    expect(lex('sh', 'echo hi').single, contains('function:echo'));
    expect(lex('yml', 'a: 1').single, contains('property:a'));
  });

  group('dart', () {
    test('keywords, strings, numbers, types, comments', () {
      expect(lex('dart', "final String s = 'x'; // note\nint n = 42;"), [
        ['keyword:final', 'type:String', "string:'x'", 'comment:// note'],
        ['type:int', 'number:42'],
      ]);
    });

    test('block comment state carries over lines', () {
      final lines = lex('dart', 'a /* start\nmiddle\nend */ b');
      expect(lines[0], ['comment:/* start']);
      expect(lines[1], ['comment:middle']);
      expect(lines[2], contains('comment:end */'));
      // ...and returns to normal afterwards
      expect(hl.highlightLine('dart', 'x', null).endState, isNull);
      expect(hl.highlightLine('dart', '/* open', null).endState, isNotNull);
      expect(
        hl
            .highlightLine(
              'dart',
              'end */',
              hl.highlightLine('dart', '/* open', null).endState,
            )
            .endState,
        isNull,
      );
    });

    test('triple-quoted strings span lines', () {
      final lines = lex('dart', "var s = '''a\nb\nc''';");
      expect(lines[1], ['string:b']);
    });
  });

  group('python', () {
    test('triple quotes carry state, hash comments', () {
      final lines = lex('python', 'x = """doc\nstill doc\n""" # c');
      expect(lines[0], contains('string:"""doc'));
      expect(lines[1], ['string:still doc']);
      expect(lines[2], contains('comment:# c'));
    });
  });

  group('json', () {
    test('keys are properties, values are strings', () {
      expect(lex('json', '{"k": "v", "n": 1, "b": true}').single, [
        'property:"k"',
        'string:"v"',
        'property:"n"',
        'number:1',
        'property:"b"',
        'constant:true',
      ]);
    });
  });

  group('html', () {
    test('tags, attributes and multi-line tags', () {
      final lines = lex('html', '<div class="a"\n     id="b">x</div>');
      expect(
        lines[0],
        containsAll(['tag:<div', 'attribute:class', 'string:"a"']),
      );
      expect(
        lines[1],
        containsAll(['attribute:id', 'string:"b"', 'tag:>', 'tag:</div>']),
      );
    });
  });

  group('diff', () {
    test('added, removed and header lines', () {
      final lines = lex(
        'diff',
        '--- a/x\n+++ b/x\n@@ -1 +1 @@\n-gone\n+new\n ctx',
      );
      expect(lines[0].single, startsWith('meta:'));
      expect(lines[2].single, startsWith('meta:'));
      expect(lines[3].single, 'deletion:-gone');
      expect(lines[4].single, 'addition:+new');
      expect(lines[5], isEmpty);
    });
  });

  group('sql', () {
    test('keywords are case-insensitive', () {
      expect(
        lex('sql', 'select * FROM t').single,
        containsAll(['keyword:select', 'keyword:FROM']),
      );
    });
  });

  test('incremental highlighting equals one-shot highlighting', () {
    const code = "/* a\nb */\nvoid f() {\n  // c\n  var s = 'x';\n}\n";
    final lines = code.split('\n');
    Object? state;
    final full = <List<Token>>[];
    for (final l in lines) {
      final r = hl.highlightLine('dart', l, state);
      full.add(r.tokens);
      state = r.endState;
    }
    // "Streaming": re-highlight only from a saved state
    Object? saved;
    final incr = <List<Token>>[];
    for (var i = 0; i < lines.length; i++) {
      final r = hl.highlightLine('dart', lines[i], saved);
      saved = r.endState;
      incr.add(r.tokens);
    }
    expect(incr, full);
  });

  test('custom languages can be added and override built-ins', () {
    final custom = RuleBasedHighlighter(
      extraLanguages: [
        LanguageDefinition(
          name: 'toy',
          aliases: const ['t'],
          states: {
            'root': [LexRule(r'\bgo\b', TokenKind.keyword)],
          },
        ),
        LanguageDefinition(
          name: 'dart',
          states: {
            'root': [LexRule(r'zzz', TokenKind.constant)],
          },
        ),
      ],
    );
    expect(
      custom
          .highlightLine('t', 'go go', null)
          .tokens
          .where((t) => t.kind == TokenKind.keyword),
      hasLength(2),
    );
    expect(
      custom.highlightLine('dart', 'zzz', null).tokens.single.kind,
      TokenKind.constant,
    );
  });

  test('pathological input does not hang', () {
    final sw = Stopwatch()..start();
    hl.highlightLine('dart', '"' * 20000, null);
    hl.highlightLine('javascript', 'a' * 50000, null);
    hl.highlightLine('html', '<' * 5000, null);
    expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
  });
}
