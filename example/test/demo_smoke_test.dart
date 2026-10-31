import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown_example/main.dart';

void main() {
  testWidgets('demo streams a whole reply without errors', (tester) async {
    await tester.pumpWidget(const ChatDemoApp());
    for (var i = 0; i < 400; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull, reason: 'frame $i');
    }
    expect(find.textContaining('Streaming Markdown'), findsWidgets);
    expect(find.textContaining('That\'s all'), findsNothing);
  });
}
