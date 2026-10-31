import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown_renderer/llm_markdown_renderer.dart';

void main() {
  test('append parses immediately and accumulates the raw text', () {
    final c = MarkdownStreamController(coalesceNotifications: false);
    c.append('# Hi\n\npar');
    c.append('a');
    expect(c.text, '# Hi\n\npara');
    expect(c.document.blocks, hasLength(2));
    expect(c.isComplete, isFalse);
    c.dispose();
  });

  test('initialText is parsed', () {
    final c = MarkdownStreamController(initialText: '# x');
    expect(c.document.blocks.single, isA<HeadingBlock>());
    c.dispose();
  });

  test('uncoalesced controller notifies on every change', () {
    final c = MarkdownStreamController(coalesceNotifications: false);
    var n = 0;
    c.addListener(() => n++);
    c.append('a');
    c.append('');
    c.append('b');
    c.complete();
    c.complete(); // idempotent
    expect(n, 3);
    expect(c.isComplete, isTrue);
    c.dispose();
  });

  test('reset clears everything, optionally with new text', () {
    final c = MarkdownStreamController(coalesceNotifications: false)
      ..append('old')
      ..complete();
    c.reset('new');
    expect(c.isComplete, isFalse);
    expect(c.text, 'new');
    c.append('er');
    expect((c.document.blocks.single as ParagraphBlock).children, [
      const InlineText('newer'),
    ]);
    c.dispose();
  });

  test('append after complete throws', () {
    final c = MarkdownStreamController(coalesceNotifications: false)
      ..complete();
    expect(() => c.append('x'), throwsStateError);
    c.dispose();
  });

  testWidgets('notifications are coalesced to one per frame', (tester) async {
    final c = MarkdownStreamController();
    var n = 0;
    c.addListener(() => n++);
    for (var i = 0; i < 200; i++) {
      c.append('tok$i ');
    }
    expect(n, 0, reason: 'nothing is notified synchronously');
    // The document itself is nevertheless always current.
    expect(c.document.blocks, hasLength(1));
    await tester.pump();
    expect(n, 1);
    c.append('more');
    await tester.pump();
    expect(n, 2);
    c.dispose();
  });

  testWidgets('disposing with a pending notification is safe', (tester) async {
    final c = MarkdownStreamController();
    c.append('x');
    c.dispose();
    await tester.pump();
  });
}
