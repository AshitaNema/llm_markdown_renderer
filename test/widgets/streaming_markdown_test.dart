import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown_renderer/llm_markdown_renderer.dart';
import 'package:llm_markdown_renderer/src/widgets/inline_renderer.dart'
    show isSafeLinkUrl;

Widget host(Widget child, {ThemeData? theme}) => MaterialApp(
  theme: theme,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

/// Every span in the tree, including wrappers that carry no text of their
/// own (`visitChildren` skips those).
Iterable<TextSpan> allSpans(InlineSpan root) sync* {
  if (root is TextSpan) {
    yield root;
    for (final c in root.children ?? const <InlineSpan>[]) {
      yield* allSpans(c);
    }
  }
}

/// The span carrying the Markdown theme's style (the child of the wrapper
/// span that `Text.rich` adds).
TextSpan contentSpan(RichText r) =>
    (r.text as TextSpan).children!.single as TextSpan;

void main() {
  group('controller API', () {
    testWidgets('renders streamed content and updates as chunks arrive', (
      tester,
    ) async {
      final c = MarkdownStreamController();
      addTearDown(c.dispose);
      await tester.pumpWidget(host(StreamingMarkdown(controller: c)));
      c.append('# Hello\n\nfirst par');
      await tester.pump();
      expect(find.textContaining('Hello'), findsOneWidget);
      expect(find.textContaining('first par'), findsOneWidget);
      c.append('agraph **bold**');
      await tester.pump();
      expect(find.textContaining('first paragraph bold'), findsOneWidget);
    });

    testWidgets('inline styles are applied', (tester) async {
      await tester.pumpWidget(
        host(
          const StreamingMarkdown.static(
            data: 'a **b** *c* ~~d~~ `e` [f](https://x.y)',
            selectable: false,
          ),
        ),
      );
      final rich = tester.widget<RichText>(find.byType(RichText).first);
      expect(rich.text.toPlainText(), 'a b c d e f');
      final spans = allSpans(rich.text).toList();
      expect(spans.any((s) => s.style?.fontWeight == FontWeight.bold), isTrue);
      expect(spans.any((s) => s.style?.fontStyle == FontStyle.italic), isTrue);
      expect(
        spans.any((s) => s.style?.decoration == TextDecoration.lineThrough),
        isTrue,
      );
      expect(
        spans.any((s) => s.style?.decoration == TextDecoration.underline),
        isTrue,
      );
      expect(
        spans.any((s) => s.text == 'e' && s.style?.fontFamily == 'monospace'),
        isTrue,
      );
    });

    testWidgets('unclosed code fence renders a code block while streaming', (
      tester,
    ) async {
      final c = MarkdownStreamController();
      addTearDown(c.dispose);
      await tester.pumpWidget(host(StreamingMarkdown(controller: c)));
      c.append('Here:\n\n```dart\nvoid main() {');
      await tester.pump();
      expect(find.byType(CodeBlockView), findsOneWidget);
      expect(find.byIcon(Icons.content_copy_outlined), findsOneWidget);
      expect(find.text('dart'), findsOneWidget);
      expect(find.textContaining('void main() {'), findsOneWidget);
      c.append('}\n```\nDone');
      await tester.pump();
      expect(find.byType(CodeBlockView), findsOneWidget);
      expect(find.textContaining('Done'), findsOneWidget);
    });

    testWidgets('only the open block is rebuilt; finished blocks are reused', (
      tester,
    ) async {
      final c = MarkdownStreamController();
      addTearDown(c.dispose);
      var codeBuilds = 0;
      await tester.pumpWidget(
        host(
          StreamingMarkdown(
            controller: c,
            codeBlockBuilder: (context, block) {
              codeBuilds++;
              return const SizedBox(height: 10, child: Text('CODE'));
            },
          ),
        ),
      );
      c.append('Intro\n\n```\ncode\n```\n\nTail ');
      await tester.pump();
      expect(codeBuilds, 1);
      for (final tok in ['one ', 'two ', 'three ', 'four']) {
        c.append(tok);
        await tester.pump();
      }
      expect(find.textContaining('Tail one two three four'), findsOneWidget);
      expect(codeBuilds, 1, reason: 'finished code block must not rebuild');
    });

    testWidgets('lists, quotes, rules, tasks render', (tester) async {
      await tester.pumpWidget(
        host(
          const StreamingMarkdown.static(
            data: '- a\n- [x] b\n\n1. one\n2. two\n\n> quoted\n\n---\n\nend',
            selectable: false,
          ),
        ),
      );
      expect(find.text('•'), findsOneWidget);
      expect(find.byIcon(Icons.check_box), findsOneWidget);
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
      expect(find.textContaining('quoted'), findsOneWidget);
      expect(find.textContaining('end'), findsOneWidget);
    });

    testWidgets('link taps are reported, unsafe schemes are inert', (
      tester,
    ) async {
      final taps = <String>[];
      await tester.pumpWidget(
        host(
          StreamingMarkdown.static(
            data: '[safe](https://ok.dev) and [bad](javascript:alert(1))',
            selectable: false,
            onTapLink: (url, title) => taps.add(url),
          ),
        ),
      );
      final rich = tester.widget<RichText>(find.byType(RichText).first);
      final links = allSpans(
        rich.text,
      ).where((s) => s.recognizer != null).toList();
      expect(links, hasLength(1));
      (links.single.recognizer! as TapGestureRecognizer).onTap!();
      expect(taps, ['https://ok.dev']);
      expect(isSafeLinkUrl('javascript:alert(1)'), isFalse);
      expect(isSafeLinkUrl('data:text/html,x'), isFalse);
      expect(isSafeLinkUrl('https://a.b'), isTrue);
      expect(isSafeLinkUrl('mailto:a@b.c'), isTrue);
      expect(isSafeLinkUrl('/relative'), isTrue);
    });

    testWidgets('links are inert without onTapLink', (tester) async {
      await tester.pumpWidget(
        host(
          const StreamingMarkdown.static(
            data: '[x](https://ok.dev)',
            selectable: false,
          ),
        ),
      );
      final rich = tester.widget<RichText>(find.byType(RichText).first);
      expect(allSpans(rich.text).where((s) => s.recognizer != null), isEmpty);
    });

    testWidgets('images are placeholders unless a builder is supplied', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const StreamingMarkdown.static(
            data: '![a cat](https://x/cat.png)',
            selectable: false,
          ),
        ),
      );
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
      expect(find.textContaining('a cat'), findsOneWidget);

      await tester.pumpWidget(
        host(
          StreamingMarkdown.static(
            data: '![a cat](https://x/cat.png)',
            selectable: false,
            imageBuilder: (c, image, style) =>
                Text('IMG[${image.url}|${image.alt}]'),
          ),
        ),
      );
      expect(find.text('IMG[https://x/cat.png|a cat]'), findsOneWidget);
    });

    testWidgets('selectable wraps content in a SelectionArea', (tester) async {
      await tester.pumpWidget(host(const StreamingMarkdown.static(data: 'x')));
      expect(find.byType(SelectionArea), findsOneWidget);
      await tester.pumpWidget(
        host(const StreamingMarkdown.static(data: 'x', selectable: false)),
      );
      expect(find.byType(SelectionArea), findsNothing);
    });

    testWidgets('swapping the controller re-renders', (tester) async {
      final a = MarkdownStreamController(initialText: 'from A');
      final b = MarkdownStreamController(initialText: 'from B');
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      await tester.pumpWidget(host(StreamingMarkdown(controller: a)));
      expect(find.textContaining('from A'), findsOneWidget);
      await tester.pumpWidget(host(StreamingMarkdown(controller: b)));
      expect(find.textContaining('from B'), findsOneWidget);
      // The old controller no longer drives the view
      a.append('!');
      await tester.pump();
      expect(find.textContaining('from A'), findsNothing);
    });

    testWidgets('reset ("regenerate") clears the view', (tester) async {
      final c = MarkdownStreamController(initialText: 'old answer');
      addTearDown(c.dispose);
      await tester.pumpWidget(host(StreamingMarkdown(controller: c)));
      c.reset();
      await tester.pump();
      expect(find.textContaining('old answer'), findsNothing);
      c.append('new');
      await tester.pump();
      expect(find.textContaining('new'), findsOneWidget);
    });
  });

  group('Stream<String> API', () {
    testWidgets('renders tokens as they arrive and completes on done', (
      tester,
    ) async {
      final s = StreamController<String>();
      addTearDown(() => unawaited(s.close()));
      await tester.pumpWidget(
        host(StreamingMarkdown.fromStream(stream: s.stream)),
      );
      s.add('Hello ');
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Hello'), findsOneWidget);
      s.add('\n\n```py\nprint(1)');
      await tester.pump();
      await tester.pump();
      expect(find.byType(CodeBlockView), findsOneWidget);
      unawaited(s.close());
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('print(1)'), findsOneWidget);
    });

    testWidgets('stream errors complete rendering and reach the handler', (
      tester,
    ) async {
      final s = StreamController<String>();
      addTearDown(() => unawaited(s.close()));
      Object? seen;
      await tester.pumpWidget(
        host(
          StreamingMarkdown.fromStream(
            stream: s.stream,
            onStreamError: (e, st) => seen = e,
          ),
        ),
      );
      s.add('partial');
      s.addError(StateError('boom'));
      await tester.pump();
      await tester.pump();
      expect(seen, isA<StateError>());
      expect(find.textContaining('partial'), findsOneWidget);
      // Data after the error is ignored instead of appending to a completed
      // document (which would throw).
      s.add(' more');
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('more'), findsNothing);
    });

    testWidgets('unhandled stream errors are reported to FlutterError', (
      tester,
    ) async {
      final s = StreamController<String>();
      addTearDown(() => unawaited(s.close()));
      await tester.pumpWidget(
        host(StreamingMarkdown.fromStream(stream: s.stream)),
      );
      s.addError(StateError('boom'));
      await tester.pump();
      final e = tester.takeException();
      expect(e, isA<StateError>());
    });

    testWidgets('a new stream restarts rendering; disposing cancels', (
      tester,
    ) async {
      final s1 = StreamController<String>();
      final s2 = StreamController<String>();
      addTearDown(() => unawaited(s1.close()));
      addTearDown(() => unawaited(s2.close()));
      await tester.pumpWidget(
        host(StreamingMarkdown.fromStream(stream: s1.stream)),
      );
      s1.add('first');
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('first'), findsOneWidget);
      await tester.pumpWidget(
        host(StreamingMarkdown.fromStream(stream: s2.stream)),
      );
      expect(s1.hasListener, isFalse);
      s2.add('second');
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('first'), findsNothing);
      expect(find.textContaining('second'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(s2.hasListener, isFalse);
    });
  });

  group('theming', () {
    testWidgets('a MarkdownTheme extension on ThemeData is honoured', (
      tester,
    ) async {
      final base = ThemeData();
      final custom = MarkdownTheme.fromTheme(base).copyWith(
        bodyStyle: const TextStyle(color: Color(0xFF123456), fontSize: 21),
      );
      await tester.pumpWidget(
        host(
          const StreamingMarkdown.static(data: 'hello', selectable: false),
          theme: base.copyWith(extensions: [custom]),
        ),
      );
      final rich = tester.widget<RichText>(find.byType(RichText).first);
      expect(contentSpan(rich).style?.color, const Color(0xFF123456));
      expect(contentSpan(rich).style?.fontSize, 21);
    });

    testWidgets('the theme argument beats the extension', (tester) async {
      final base = ThemeData();
      await tester.pumpWidget(
        host(
          StreamingMarkdown.static(
            data: 'hello',
            selectable: false,
            theme: MarkdownTheme.fromTheme(
              base,
            ).copyWith(bodyStyle: const TextStyle(fontSize: 33)),
          ),
          theme: base.copyWith(
            extensions: [
              MarkdownTheme.fromTheme(
                base,
              ).copyWith(bodyStyle: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      );
      final rich = tester.widget<RichText>(find.byType(RichText).first);
      expect(contentSpan(rich).style?.fontSize, 33);
    });

    testWidgets('light and dark themes derive different code colours', (
      tester,
    ) async {
      final light = MarkdownTheme.fromTheme(ThemeData.light());
      final dark = MarkdownTheme.fromTheme(ThemeData.dark());
      expect(light.codeBlockBackground, isNot(dark.codeBlockBackground));
      expect(light.syntaxTheme, isNot(dark.syntaxTheme));
    });

    test('copyWith, lerp and equality', () {
      final a = MarkdownTheme.fromTheme(ThemeData.light());
      final b = a.copyWith(blockSpacing: 40, listIndent: 50);
      expect(a, a.copyWith());
      expect(a.hashCode, a.copyWith().hashCode);
      expect(a, isNot(b));
      final mid = a.lerp(b, 0.5);
      expect(mid.blockSpacing, closeTo((a.blockSpacing + 40) / 2, 1e-9));
      expect(mid.listIndent, closeTo((a.listIndent + 50) / 2, 1e-9));
      expect(a.lerp(null, 0.5), a);
      expect(a.headingStyle(1), a.headingStyles[0]);
      expect(a.headingStyle(99), a.headingStyles[5]);
    });

    test('SyntaxTheme merge and lerp', () {
      final s = SyntaxTheme.light().copyWith(
        styles: {TokenKind.keyword: const TextStyle(color: Color(0xFF000000))},
      );
      expect(s.styleFor(TokenKind.keyword).color, const Color(0xFF000000));
      expect(
        s.styleFor(TokenKind.string),
        SyntaxTheme.light().styleFor(TokenKind.string),
      );
      final l = SyntaxTheme.lerp(SyntaxTheme.light(), SyntaxTheme.dark(), 0.5);
      expect(l.styleFor(TokenKind.keyword).color, isNotNull);
    });
  });

  group('tables', () {
    testWidgets('column widths never shrink while streaming', (tester) async {
      final c = MarkdownStreamController();
      addTearDown(c.dispose);
      await tester.pumpWidget(host(StreamingMarkdown(controller: c)));
      c.append('| name | note |\n|---|---|\n');
      await tester.pump();
      var last = 0.0;
      for (final row in [
        '| a | short |\n',
        '| a-much-longer-name | x |\n',
        '| b | y |\n',
        '| c | z |\n',
      ]) {
        c.append(row);
        await tester.pump();
        final w = tester.getSize(find.byType(Table)).width;
        expect(w, greaterThanOrEqualTo(last), reason: 'after $row');
        last = w;
      }
      expect(find.byType(Table), findsOneWidget);
      expect(find.text('a-much-longer-name'), findsOneWidget);
    });

    testWidgets('cells are exactly as wide as their text (no mid-word wraps)', (
      tester,
    ) async {
      // The default test font is perfectly regular and hides measuring
      // errors, so use the real proportional Roboto shipped with Flutter.
      final root = Platform.environment['FLUTTER_ROOT'];
      final fonts = '$root/bin/cache/artifacts/material_fonts';
      if (root == null || !File('$fonts/Roboto-Regular.ttf').existsSync()) {
        markTestSkipped('Roboto not found in the Flutter SDK');
        return;
      }
      final loader = FontLoader('Roboto');
      for (final f in ['Regular', 'Bold', 'Italic', 'Medium']) {
        loader.addFont(
          Future.value(
            ByteData.sublistView(
              File('$fonts/Roboto-$f.ttf').readAsBytesSync(),
            ),
          ),
        );
      }
      await loader.load();
      tester.view.devicePixelRatio = 1.5;
      addTearDown(tester.view.reset);
      const md =
          '| Package | Streaming | Highlighting | Notes |\n'
          '|---|:-:|:-:|---|\n'
          '| llm_markdown_renderer | yes | yes | incremental parser |\n'
          '| naive re-parse | no | maybe | O(n) per token |\n';
      final c = MarkdownStreamController();
      addTearDown(c.dispose);
      // The documented pattern: build the extension from a ThemeData created
      // outside MaterialApp. Its styles are unresolved (inherit: true) and get
      // letter spacing etc. from DefaultTextStyle only at render time.
      final base = ThemeData(fontFamily: 'Roboto');
      await tester.pumpWidget(
        host(
          StreamingMarkdown(controller: c, selectable: false),
          theme: base.copyWith(extensions: [MarkdownTheme.fromTheme(base)]),
        ),
      );
      for (var i = 0; i < md.length; i += 5) {
        c.append(md.substring(i, i + 5 > md.length ? md.length : i + 5));
        await tester.pump();
      }
      c.complete();
      await tester.pump();
      final heights = <String, double>{};
      for (final w in tester.widgetList<RichText>(
        find.descendant(
          of: find.byType(Table),
          matching: find.byType(RichText),
        ),
      )) {
        heights[w.text.toPlainText()] = tester.getSize(find.byWidget(w)).height;
      }
      expect(heights, isNotEmpty);
      final oneLine = heights.values.reduce((a, b) => a < b ? a : b);
      heights.forEach((text, h) {
        expect(h, oneLine, reason: '"$text" wrapped onto several lines');
      });
    });

    testWidgets('a half-streamed row keeps the table rectangular', (
      tester,
    ) async {
      final c = MarkdownStreamController(
        initialText: '| a | b | c |\n|---|---|---|\n| 1 | 2',
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(host(StreamingMarkdown(controller: c)));
      expect(tester.takeException(), isNull);
      expect(find.byType(Table), findsOneWidget);
    });
  });

  group('robustness', () {
    testWidgets('streams a large, varied document in tiny chunks', (
      tester,
    ) async {
      final c = MarkdownStreamController();
      addTearDown(c.dispose);
      await tester.pumpWidget(host(StreamingMarkdown(controller: c)));
      const doc =
          '# T\n\nSome **bold** text.\n\n- a\n  - b\n- c\n\n'
          '```dart\nvoid main() {\n  print("hi");\n}\n```\n\n'
          '| a | b |\n|---|---|\n| 1 | 2 |\n\n> quote\n\n---\n\nEnd.\n';
      for (var i = 0; i < doc.length; i += 4) {
        c.append(doc.substring(i, i + 4 > doc.length ? doc.length : i + 4));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'at offset $i');
      }
      c.complete();
      await tester.pump();
      expect(find.textContaining('End.'), findsOneWidget);
    });
  });
}
