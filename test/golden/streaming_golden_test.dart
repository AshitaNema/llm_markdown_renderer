@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown_renderer/llm_markdown_renderer.dart';

/// A reply that is cut off mid-way: a finished heading, list and table, and a
/// code fence that is still open with a half-written last line.
const _snapshot =
    '# Streaming\n\n'
    'Some **bold**, *italic* and `code`, plus a [link](https://x.y).\n\n'
    '- first\n- [x] done task\n  - nested\n\n'
    '| a | b |\n|---|--:|\n| 1 | 22 |\n\n'
    '```dart\nvoid main() {\n  print(1);\n  final x = ';

Future<void> _golden(
  WidgetTester tester,
  Brightness brightness,
  String file,
) async {
  tester.view.physicalSize = const Size(420, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final c = MarkdownStreamController(initialText: _snapshot);
  addTearDown(c.dispose);
  final base = ThemeData(brightness: brightness);
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('shot'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: base.copyWith(extensions: [MarkdownTheme.fromTheme(base)]),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: StreamingMarkdown(controller: c, selectable: false),
          ),
        ),
      ),
    ),
  );
  await expectLater(
    find.byKey(const ValueKey('shot')),
    matchesGoldenFile('goldens/$file'),
  );
}

void main() {
  testWidgets('mid-stream snapshot, light theme', (tester) async {
    await _golden(tester, Brightness.light, 'streaming_light.png');
  });

  testWidgets('mid-stream snapshot, dark theme', (tester) async {
    await _golden(tester, Brightness.dark, 'streaming_dark.png');
  });
}
