import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown_renderer/parser.dart';

void main() {
  test('splits on LF, CRLF and CR', () {
    final b = LineBuffer();
    expect(b.add('a\nb\r\nc\rd'), ['a', 'b', 'c']);
    expect(b.pending, 'd');
  });

  test('keeps the partial line pending across chunks', () {
    final b = LineBuffer();
    expect(b.add('hel'), isEmpty);
    expect(b.add('lo'), isEmpty);
    expect(b.pending, 'hello');
    expect(b.add(' world\nnext'), ['hello world']);
    expect(b.pending, 'next');
  });

  test('CR at chunk end swallows an LF at the next chunk start', () {
    final b = LineBuffer();
    expect(b.add('a\r'), ['a']);
    expect(b.add('\nb\n'), ['b']);
  });

  test('CR at chunk end followed by other text does not swallow it', () {
    final b = LineBuffer();
    expect(b.add('a\r'), ['a']);
    expect(b.add('b\n'), ['b']);
  });

  test('blank lines are emitted as empty strings', () {
    expect(LineBuffer().add('\n\n\n'), ['', '', '']);
    expect(LineBuffer().add('\r\n\r\n'), ['', '']);
  });

  test('a high surrogate at the end of a chunk is held back', () {
    final b = LineBuffer();
    const crab = '🦀';
    expect(b.add('x${crab[0]}'), isEmpty);
    expect(b.pending, 'x');
    expect(b.add('${crab[1]}\n'), ['x$crab']);
  });

  test('flush returns the unterminated line, including a held surrogate', () {
    final b = LineBuffer();
    b.add('ab\ncd');
    expect(b.flush(), 'cd');
    expect(b.flush(), isNull);
    b.add('\u{1F600}'.substring(0, 1));
    expect(b.flush(), '\u{1F600}'.substring(0, 1));
  });

  test('empty chunk is a no-op', () {
    final b = LineBuffer();
    expect(b.add(''), isEmpty);
    expect(b.pending, '');
  });
}
