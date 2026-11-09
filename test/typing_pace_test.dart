import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown_renderer/llm_markdown_renderer.dart';

const frame = Duration(milliseconds: 16);

/// The plain text of the document's first paragraph, or '' if none.
String shown(MarkdownStreamController c) {
  final blocks = c.document.blocks;
  if (blocks.isEmpty) return '';
  final p = blocks.first as ParagraphBlock;
  return p.children.whereType<InlineText>().map((t) => t.text).join();
}

void main() {
  testWidgets('a burst is shown gradually at the steady speed', (tester) async {
    final c = MarkdownStreamController(
      pace: const TypingPace(
        charactersPerSecond: 100,
        maxDelay: Duration(seconds: 10),
      ),
    );
    addTearDown(c.dispose);
    c.append('a' * 50);
    expect(c.pendingLength, 50);
    expect(c.text, 'a' * 50, reason: 'text holds everything received');
    expect(shown(c), '');

    await tester.pump(); // the first frame counts as one 1/60 s frame
    expect(shown(c).length, 1);
    await tester.pump(const Duration(milliseconds: 100));
    expect(shown(c).length, 11, reason: '100 chars/s for 1/60 s + 0.1 s');

    await tester.pump(const Duration(milliseconds: 400));
    expect(shown(c).length, 50);
    expect(c.pendingLength, 0);
  });

  testWidgets('a large backlog drains within maxDelay', (tester) async {
    final c = MarkdownStreamController(
      pace: const TypingPace(
        charactersPerSecond: 10,
        maxDelay: Duration(milliseconds: 300),
      ),
    );
    addTearDown(c.dispose);
    c.append('b' * 3000);
    await tester.pump();
    var elapsed = Duration.zero;
    while (c.pendingLength > 0 && elapsed < const Duration(seconds: 2)) {
      await tester.pump(frame);
      elapsed += frame;
    }
    expect(c.pendingLength, 0);
    // Without catching up, 10 chars/s would take 300 s. The first frame
    // only sets the deadline, so allow it and one rounding frame on top.
    expect(
      elapsed,
      lessThanOrEqualTo(const Duration(milliseconds: 300) + frame * 2),
    );
  });

  testWidgets('complete() finishes the document once the text is shown', (
    tester,
  ) async {
    final c = MarkdownStreamController(pace: const TypingPace());
    addTearDown(c.dispose);
    c
      ..append('**bold')
      ..complete();
    expect(c.isComplete, isFalse);
    expect(() => c.append('x'), throwsStateError);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(c.isComplete, isTrue);
    expect(c.document.blocks.single, isA<ParagraphBlock>());
  });

  testWidgets('flush() shows everything at once and finishes', (tester) async {
    final c = MarkdownStreamController(pace: const TypingPace());
    addTearDown(c.dispose);
    var notified = 0;
    c.addListener(() => notified++);
    c
      ..append('Hello there')
      ..complete()
      ..flush();
    expect(c.pendingLength, 0);
    expect(c.isComplete, isTrue);
    await tester.pump();
    expect(shown(c), 'Hello there');
    expect(notified, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(notified, 1, reason: 'nothing left to type');
  });

  testWidgets('reset() drops text that was still waiting', (tester) async {
    final c = MarkdownStreamController(pace: const TypingPace());
    addTearDown(c.dispose);
    c.append('old text');
    c.reset('new');
    expect(c.pendingLength, 0);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(shown(c), 'new');
  });

  testWidgets('an emoji is never split across frames', (tester) async {
    final c = MarkdownStreamController(
      pace: const TypingPace(
        charactersPerSecond: 60,
        maxDelay: Duration(seconds: 10),
      ),
    );
    addTearDown(c.dispose);
    c.append('👋' * 10);
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      await tester.pump(frame);
      final s = shown(c);
      expect(s.length.isEven, isTrue, reason: 'shown: ${s.runes.length}');
    }
  });

  testWidgets('disposing while text is waiting is safe', (tester) async {
    final c = MarkdownStreamController(pace: const TypingPace())
      ..append('some text');
    await tester.pump();
    c.dispose();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('slow text appears on the next frame, as without a pace', (
    tester,
  ) async {
    final c = MarkdownStreamController(pace: const TypingPace());
    addTearDown(c.dispose);
    for (var k = 0; k < 5; k++) {
      c.append('abc ');
      await tester.pump(); // one frame after arrival
      expect(c.pendingLength, 0, reason: 'token $k');
      await tester.pump(const Duration(milliseconds: 100)); // idle
    }
    expect(shown(c), 'abc abc abc abc abc');
  });

  testWidgets('appending from a listener does not schedule a second tick', (
    tester,
  ) async {
    final c = MarkdownStreamController(
      pace: const TypingPace(
        charactersPerSecond: 60,
        maxDelay: Duration(seconds: 10),
      ),
    );
    var extra = 3;
    c.addListener(() {
      if (extra-- > 0) c.append('y');
    });
    c.append('x' * 20);
    for (var i = 0; i < 10; i++) {
      await tester.pump(frame);
      expect(
        tester.binding.transientCallbackCount,
        lessThanOrEqualTo(1),
        reason: 'frame $i',
      );
    }
    c.flush();
    c.dispose();
  });

  testWidgets('appending many chunks while no frames run stays cheap', (
    tester,
  ) async {
    final c = MarkdownStreamController(pace: const TypingPace());
    final sw = Stopwatch()..start();
    for (var i = 0; i < 100000; i++) {
      c.append('tok ');
    }
    expect(c.pendingLength, 400000);
    c.flush();
    expect(c.pendingLength, 0);
    expect(sw.elapsedMilliseconds, lessThan(1000));
    c.dispose();
  });

  testWidgets('many small chunks come out complete and in order', (
    tester,
  ) async {
    final c = MarkdownStreamController(
      pace: const TypingPace(
        charactersPerSecond: 1000,
        maxDelay: Duration(seconds: 10),
      ),
    );
    addTearDown(c.dispose);
    // 100 one-letter chunks, with emoji (two code units) among them, so
    // releases end inside later chunks and the queue gets compacted.
    final chunks = [
      for (var i = 0; i < 100; i++) i % 7 == 3 ? '👋' : 'abcdefghij'[i % 10],
    ];
    chunks.forEach(c.append);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    final partial = shown(c);
    expect(partial.length, inInclusiveRange(70, 120));
    expect(
      partial.codeUnitAt(partial.length - 1),
      isNot(inInclusiveRange(0xD800, 0xDBFF)),
      reason: 'an emoji is never cut in half',
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(c.pendingLength, 0);
    expect(shown(c), chunks.join());
  });

  test('TypingPace rejects an infinite speed and prints its values', () {
    expect(
      () => TypingPace(charactersPerSecond: double.infinity),
      throwsAssertionError,
    );
    expect(
      const TypingPace().toString(),
      'TypingPace(charactersPerSecond: 250.0, maxDelay: 400 ms)',
    );
  });

  test('TypingPace has value equality', () {
    expect(const TypingPace(), const TypingPace());
    expect(const TypingPace().hashCode, const TypingPace().hashCode);
    expect(
      const TypingPace(),
      isNot(const TypingPace(charactersPerSecond: 99)),
    );
  });

  testWidgets('StreamingMarkdown.fromStream types a burst with a pace', (
    tester,
  ) async {
    final source = StreamController<String>();
    addTearDown(source.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdown.fromStream(
            stream: source.stream,
            selectable: false,
            pace: const TypingPace(
              charactersPerSecond: 100,
              maxDelay: Duration(seconds: 10),
            ),
          ),
        ),
      ),
    );
    source.add('x' * 40);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final partial = tester.widget<RichText>(find.byType(RichText).first);
    expect(partial.text.toPlainText().length, lessThan(40));
    await tester.pump(const Duration(seconds: 1));
    final done = tester.widget<RichText>(find.byType(RichText).first);
    expect(done.text.toPlainText(), 'x' * 40);
  });
}
