import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown_renderer/llm_markdown_renderer.dart';

Widget host(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

CodeBlock block(
  List<String> lines, {
  String? lang = 'dart',
  bool open = false,
}) => CodeBlock(
  id: 1,
  isOpen: open,
  lines: lines,
  language: lang,
  info: lang ?? '',
);

/// Collects every `Clipboard.setData` payload.
List<String> mockClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}

void main() {
  testWidgets('copy button copies the raw code and shows feedback', (
    tester,
  ) async {
    final copied = mockClipboard(tester);
    await tester.pumpWidget(
      host(CodeBlockView(block: block(['void main() {', '  print(1);', '}']))),
    );
    expect(find.byIcon(Icons.content_copy_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.content_copy_outlined));
    await tester.pump();
    expect(copied, ['void main() {\n  print(1);\n}']);
    expect(find.byIcon(Icons.check), findsOneWidget);
    // feedback resets itself
    await tester.pump(const Duration(seconds: 3));
    expect(find.byIcon(Icons.content_copy_outlined), findsOneWidget);
  });

  testWidgets('copying while the block is still streaming copies what exists', (
    tester,
  ) async {
    final copied = mockClipboard(tester);
    await tester.pumpWidget(
      host(CodeBlockView(block: block(['a = 1', 'b ='], open: true))),
    );
    await tester.tap(find.byIcon(Icons.content_copy_outlined));
    await tester.pump();
    expect(copied.single, 'a = 1\nb =');
  });

  testWidgets('disposing during the feedback timer is safe', (tester) async {
    mockClipboard(tester);
    await tester.pumpWidget(host(CodeBlockView(block: block(['x']))));
    await tester.tap(find.byIcon(Icons.content_copy_outlined));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('syntax colours come from the theme', (tester) async {
    final theme = MarkdownTheme.fromTheme(ThemeData.light()).copyWith(
      syntaxTheme: const SyntaxTheme(
        styles: {TokenKind.keyword: TextStyle(color: Color(0xFFFF0000))},
      ),
    );
    await tester.pumpWidget(
      host(CodeBlockView(block: block(['final x = 1;']), theme: theme)),
    );
    final rich = tester
        .widgetList<RichText>(find.byType(RichText))
        .firstWhere((r) => r.text.toPlainText().contains('final x'));
    Color? finalColor;
    rich.text.visitChildren((s) {
      if (s is TextSpan && s.text == 'final') finalColor = s.style?.color;
      return true;
    });
    expect(finalColor, const Color(0xFFFF0000));
  });

  testWidgets('unknown language renders plain text and labels the header', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(CodeBlockView(block: block(['whatever'], lang: 'klingon'))),
    );
    expect(find.text('klingon'), findsOneWidget);
    expect(find.textContaining('whatever'), findsOneWidget);
  });

  testWidgets('no language shows a generic label; empty block does not crash', (
    tester,
  ) async {
    await tester.pumpWidget(host(CodeBlockView(block: block([], lang: null))));
    expect(find.text('code'), findsOneWidget);
  });

  testWidgets('grows line by line and across many 32-line chunks', (
    tester,
  ) async {
    final lines = <String>[];
    for (var i = 0; i < 200; i++) {
      lines.add('var v$i = $i; // c');
      await tester.pumpWidget(
        host(CodeBlockView(block: block(List.of(lines), open: true))),
      );
    }
    expect(find.textContaining('var v199 = 199'), findsOneWidget);
    expect(find.textContaining('var v0 = 0'), findsOneWidget);
    // multiple chunk Text widgets exist, but the content is complete
    expect(
      tester
          .widgetList<RichText>(find.byType(RichText))
          .where((r) => r.text.toPlainText().contains('var v'))
          .length,
      greaterThan(1),
    );
  });

  testWidgets('multi-line comment highlighting continues across lines', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        CodeBlockView(block: block(['/* start', 'middle', 'end */ int x;'])),
      ),
    );
    final theme = MarkdownTheme.fromTheme(ThemeData.light());
    final commentColor = theme.syntaxTheme.styleFor(TokenKind.comment).color;
    final rich = tester
        .widgetList<RichText>(find.byType(RichText))
        .firstWhere((r) => r.text.toPlainText().contains('middle'));
    Color? middle;
    rich.text.visitChildren((s) {
      if (s is TextSpan && s.text == 'middle') middle = s.style?.color;
      return true;
    });
    expect(middle, commentColor);
  });

  testWidgets('changing the language re-highlights', (tester) async {
    await tester.pumpWidget(
      host(CodeBlockView(block: block(['def f(): pass'], lang: 'zzz'))),
    );
    await tester.pumpWidget(
      host(CodeBlockView(block: block(['def f(): pass'], lang: 'python'))),
    );
    final rich = tester
        .widgetList<RichText>(find.byType(RichText))
        .firstWhere((r) => r.text.toPlainText().contains('def f'));
    var coloured = false;
    rich.text.visitChildren((s) {
      if (s is TextSpan && s.text == 'def' && s.style?.color != null) {
        coloured = true;
      }
      return true;
    });
    expect(coloured, isTrue);
  });

  testWidgets('custom CodeBlockBuilder replaces the default', (tester) async {
    await tester.pumpWidget(
      host(
        StreamingMarkdown.static(
          data: '```dart\nx\n```',
          selectable: false,
          codeBlockBuilder: (c, b) => Text('custom ${b.language}'),
        ),
      ),
    );
    expect(find.text('custom dart'), findsOneWidget);
    expect(find.byType(CodeBlockView), findsNothing);
  });
}
