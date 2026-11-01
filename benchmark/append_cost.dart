// ignore_for_file: avoid_print
// Measures what one streamed chunk costs as the document grows.
//
// Run with:  dart run benchmark/append_cost.dart
//
// For each document size it reports
//   * incremental: the average time of `append(chunk)` plus reading
//     `document`, for a chunk landing in the last paragraph (what the library
//     does per frame), and
//   * full re-parse: the time to parse the entire text from scratch, which is
//     what a renderer without incremental parsing has to do for every update.
//
// The numbers depend on the machine; compare the two columns, not the
// absolute values.
import 'package:llm_markdown_renderer/parser.dart';

String block(int i) =>
    '## Section $i\n\nSome **bold** text with `code`, a [link](https://x.y) '
    'and more words to make the paragraph realistic.\n\n- one\n- two\n\n'
    '```dart\nvoid f$i() {\n  print($i);\n}\n```\n\n';

const chunks = ['The ', 'quick ', 'brown ', 'fox ', 'jumps ', 'over ', 'it. '];

void main() {
  print('| blocks | doc size | incremental / chunk | full re-parse / chunk |');
  print('|---:|---:|---:|---:|');
  for (final n in [10, 100, 1000, 10000]) {
    final text = [for (var i = 0; i < n; i++) block(i)].join();
    final blocks = IncrementalMarkdownParser.parse(text).blocks.length;

    // Incremental: stream words into a new paragraph at the end.
    final p = IncrementalMarkdownParser()..append('$text\n');
    p.document;
    const rounds = 2000;
    var sw = Stopwatch()..start();
    for (var i = 0; i < rounds; i++) {
      p.append(chunks[i % chunks.length]);
      p.document;
    }
    sw.stop();
    final incremental = sw.elapsedMicroseconds / rounds;

    // Non-incremental baseline: parse everything again for every chunk.
    final reparses = n >= 1000 ? 5 : 50;
    sw = Stopwatch()..start();
    for (var i = 0; i < reparses; i++) {
      final q = IncrementalMarkdownParser()
        ..append(text + chunks[i % chunks.length]);
      q.document;
    }
    sw.stop();
    final full = sw.elapsedMicroseconds / reparses;

    String fmt(double us) => us >= 1000
        ? '${(us / 1000).toStringAsFixed(1)} ms'
        : '${us.toStringAsFixed(1)} µs';
    print(
      '| $blocks | ${(text.length / 1024).toStringAsFixed(0)} KB | '
      '${fmt(incremental)} | ${fmt(full)} |',
    );
  }
}
