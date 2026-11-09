import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown_renderer/llm_markdown_renderer.dart';

Widget host(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

/// Every span in the tree, including wrappers without text of their own.
Iterable<TextSpan> allSpans(InlineSpan root) sync* {
  if (root is TextSpan) {
    yield root;
    for (final c in root.children ?? const <InlineSpan>[]) {
      yield* allSpans(c);
    }
  }
}

void main() {
  group('thinking sections', () {
    testWidgets('expanded while thinking, collapsed when done, toggleable', (
      tester,
    ) async {
      final c = MarkdownStreamController();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        host(StreamingMarkdown(controller: c, selectable: false)),
      );
      c.append('<think>\nWeighing the options');
      await tester.pump();
      expect(find.text('Thinking…'), findsOneWidget);
      expect(find.textContaining('Weighing'), findsOneWidget);

      c.append('.\n</think>\n\nThe answer.');
      await tester.pump();
      expect(find.text('Thoughts'), findsOneWidget);
      expect(find.textContaining('Weighing'), findsNothing);
      expect(find.textContaining('The answer'), findsOneWidget);

      await tester.tap(find.text('Thoughts'));
      await tester.pump();
      expect(find.textContaining('Weighing'), findsOneWidget);

      // The user's choice sticks while the answer keeps streaming.
      c.append(' More.');
      await tester.pump();
      expect(find.textContaining('Weighing'), findsOneWidget);
    });

    testWidgets('the header is an expandable button for screen readers', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          const StreamingMarkdown.static(
            data: '<think>\nx\n</think>\n',
            selectable: false,
          ),
        ),
      );
      expect(
        tester.getSemantics(find.text('Thoughts')),
        matchesSemantics(
          label: 'Thoughts',
          isButton: true,
          hasExpandedState: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('thinkingBuilder wraps the rendered content', (tester) async {
      ThinkingBlock? seen;
      await tester.pumpWidget(
        host(
          StreamingMarkdown.static(
            data: '<think>\nInner **text**\n</think>\n',
            selectable: false,
            thinkingBuilder: (context, block, content) {
              seen = block;
              return Card(key: const Key('card'), child: content);
            },
          ),
        ),
      );
      expect(seen?.isOpen, isFalse);
      expect(
        find.descendant(
          of: find.byKey(const Key('card')),
          matching: find.textContaining('Inner text'),
        ),
        findsOneWidget,
      );
      expect(find.text('Thoughts'), findsNothing);
    });
  });

  group('citations', () {
    testWidgets('look like the original text by default', (tester) async {
      await tester.pumpWidget(
        host(
          const StreamingMarkdown.static(
            data: 'Paris [1, 2] and [^a].',
            selectable: false,
          ),
        ),
      );
      final rich = tester.widget<RichText>(find.byType(RichText).first);
      expect(rich.text.toPlainText(), 'Paris [1, 2] and [^a].');
    });

    testWidgets('onTapCitation makes each label tappable', (tester) async {
      final tapped = <String>[];
      await tester.pumpWidget(
        host(
          StreamingMarkdown.static(
            data: 'Paris [1, 2].',
            selectable: false,
            onTapCitation: tapped.add,
          ),
        ),
      );
      final rich = tester.widget<RichText>(find.byType(RichText).first);
      final labels = allSpans(
        rich.text,
      ).where((s) => s.recognizer is TapGestureRecognizer).toList();
      expect(labels.map((s) => s.text), ['1', '2']);
      for (final s in labels) {
        (s.recognizer! as TapGestureRecognizer).onTap!();
      }
      expect(tapped, ['1', '2']);
    });

    testWidgets('citationBuilder renders inline widgets', (tester) async {
      await tester.pumpWidget(
        host(
          StreamingMarkdown.static(
            data: 'Paris [1, 2] is big [3].',
            selectable: false,
            citationBuilder: (context, cite, style) =>
                Text('<${cite.labels.join('+')}>'),
          ),
        ),
      );
      expect(find.text('<1+2>'), findsOneWidget);
      expect(find.text('<3>'), findsOneWidget);
    });
  });

  testWidgets('codeBlockBuilder can return null to keep the default view', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        StreamingMarkdown.static(
          data: '```mermaid\ngraph TD\n```\n\n```dart\nvoid main() {}\n```\n',
          selectable: false,
          codeBlockBuilder: (context, block) => block.language == 'mermaid'
              ? Text('diagram: ${block.text}')
              : null,
        ),
      ),
    );
    expect(find.text('diagram: graph TD'), findsOneWidget);
    expect(find.byType(CodeBlockView), findsOneWidget);
  });
}
