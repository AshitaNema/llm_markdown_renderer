@Tags(['golden'])
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown_renderer/llm_markdown_renderer.dart';

/// Fraction of pixels allowed to differ (0.02 = 2%).
///
/// The images use the Ahem test font, so text is solid blocks and layout is
/// identical everywhere, but the software rasterizer anti-aliases rounded
/// corners and borders slightly differently on macOS, Linux and Windows. A
/// real regression (changed layout, wrong colors, missing widgets) moves far
/// more pixels than that, and a size change always fails.
const _tolerance = 0.02;

/// Flutter's documented "precision tolerance" comparator.
class _TolerantComparator extends LocalFileComparator {
  _TolerantComparator(super.testFile);

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= _tolerance) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}

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
  setUpAll(() {
    final current = goldenFileComparator;
    if (current is LocalFileComparator) {
      goldenFileComparator = _TolerantComparator(
        current.basedir.resolve('streaming_golden_test.dart'),
      );
    }
  });

  testWidgets('mid-stream snapshot, light theme', (tester) async {
    await _golden(tester, Brightness.light, 'streaming_light.png');
  });

  testWidgets('mid-stream snapshot, dark theme', (tester) async {
    await _golden(tester, Brightness.dark, 'streaming_dark.png');
  });
}
