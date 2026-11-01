import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown_renderer/llm_markdown_renderer.dart';

Widget host(Widget child, {TextDirection? direction, double? textScale}) {
  Widget body = SingleChildScrollView(child: child);
  if (direction != null) {
    body = Directionality(textDirection: direction, child: body);
  }
  return MaterialApp(
    builder: textScale == null
        ? null
        : (context, w) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: w!,
          ),
    home: Scaffold(body: body),
  );
}

/// The direction the first text containing [containing] is laid out in.
TextDirection directionOf(WidgetTester tester, String containing) {
  final finder = find.byWidgetPredicate(
    (w) => w is RichText && w.text.toPlainText().contains(containing),
  );
  return Directionality.of(tester.element(finder.first));
}

/// The role of every semantics node under the rendered Markdown.
Set<ui.SemanticsRole> rolesIn(WidgetTester tester) {
  final roles = <ui.SemanticsRole>{};
  void visit(SemanticsNode node) {
    roles.add(node.getSemanticsData().role);
    node.visitChildren((c) {
      visit(c);
      return true;
    });
  }

  visit(tester.getSemantics(find.byType(StreamingMarkdown)));
  return roles;
}

void main() {
  group('semantics', () {
    testWidgets('headings are marked as headers', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          const StreamingMarkdown.static(
            data: '# Title\n\nbody',
            selectable: false,
          ),
        ),
      );
      final data = tester.getSemantics(find.text('Title')).getSemanticsData();
      expect(data.flagsCollection.isHeader, isTrue);
      final body = tester.getSemantics(find.text('body')).getSemanticsData();
      expect(body.flagsCollection.isHeader, isFalse);
      handle.dispose();
    });

    testWidgets('lists expose list and list-item roles', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          const StreamingMarkdown.static(
            data: '- one\n- two',
            selectable: false,
          ),
        ),
      );
      final roles = rolesIn(tester);
      expect(roles, contains(ui.SemanticsRole.list));
      expect(roles, contains(ui.SemanticsRole.listItem));
      handle.dispose();
    });

    testWidgets('code blocks are labelled with their language', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          const StreamingMarkdown.static(
            data: '```dart\nvar a;\n```',
            selectable: false,
          ),
        ),
      );
      expect(find.bySemanticsLabel(RegExp('Code block, dart')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the copy button has a tooltip', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          const StreamingMarkdown.static(
            data: '```\nx\n```',
            selectable: false,
          ),
        ),
      );
      expect(find.byTooltip('Copy code'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('streaming with semantics enabled does not assert', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final c = MarkdownStreamController();
      addTearDown(c.dispose);
      await tester.pumpWidget(host(StreamingMarkdown(controller: c)));
      const doc =
          '# T\n\n- a\n  - b\n\n```dart\nvar x;\n```\n\n| a | b |\n|---|---|\n| 1 | 2 |\n';
      for (var i = 0; i < doc.length; i += 3) {
        c.append(doc.substring(i, i + 3 > doc.length ? doc.length : i + 3));
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
      handle.dispose();
    });
  });

  group('right-to-left text', () {
    testWidgets('an Arabic paragraph is laid out RTL inside an LTR app', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const StreamingMarkdown.static(
            data: 'مرحبا بالعالم\n\nHello world',
            selectable: false,
          ),
        ),
      );
      expect(directionOf(tester, 'مرحبا'), TextDirection.rtl);
      expect(directionOf(tester, 'Hello'), TextDirection.ltr);
    });

    testWidgets('Hebrew headings and list items follow their own direction', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const StreamingMarkdown.static(
            data: '# שלום\n\n- פריט ראשון\n- item',
            selectable: false,
          ),
        ),
      );
      expect(directionOf(tester, 'שלום'), TextDirection.rtl);
      expect(directionOf(tester, 'פריט'), TextDirection.rtl);
      expect(directionOf(tester, 'item'), TextDirection.ltr);
    });

    testWidgets('direction follows the first strong letter, not digits', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const StreamingMarkdown.static(
            data: '123 — مرحبا\n\n`code` then English',
            selectable: false,
          ),
        ),
      );
      expect(directionOf(tester, '123'), TextDirection.rtl);
    });

    testWidgets('an RTL app mirrors list markers and block quote bars', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const StreamingMarkdown.static(
            data: '- item one\n\n> quoted text',
            selectable: false,
          ),
          direction: TextDirection.rtl,
        ),
      );
      final screenWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      // The bullet sits on the right-hand side of its text.
      expect(
        tester.getCenter(find.text('•')).dx,
        greaterThan(tester.getCenter(find.textContaining('item one')).dx),
      );
      // The quote bar hugs the right edge: text is left of the bar.
      expect(
        tester.getCenter(find.textContaining('quoted text')).dx,
        lessThan(screenWidth / 2 + 1),
      );
      final bar = tester
          .widgetList<Container>(find.byType(Container))
          .where(
            (c) =>
                c.decoration is BoxDecoration &&
                (c.decoration! as BoxDecoration).border is BorderDirectional,
          )
          .single;
      expect(
        (bar.decoration! as BoxDecoration).border,
        isA<BorderDirectional>(),
      );
    });

    testWidgets('code stays left-to-right in an RTL app', (tester) async {
      await tester.pumpWidget(
        host(
          const StreamingMarkdown.static(
            data: '```dart\nvoid main() {}\n```',
            selectable: false,
          ),
          direction: TextDirection.rtl,
        ),
      );
      expect(directionOf(tester, 'void main'), TextDirection.ltr);
    });

    testWidgets('streams RTL text without errors', (tester) async {
      final c = MarkdownStreamController();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        host(StreamingMarkdown(controller: c), direction: TextDirection.rtl),
      );
      const doc =
          '## عنوان\n\nنص **غامق** و`كود`.\n\n| أ | ب |\n|---|---|\n| ١ | ٢ |\n\n```py\nprint(1)\n```\n';
      for (var i = 0; i < doc.length; i += 2) {
        c.append(doc.substring(i, i + 2 > doc.length ? doc.length : i + 2));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'offset $i');
      }
    });
  });

  group('large accessibility text sizes', () {
    for (final scale in [1.5, 2.5, 3.5]) {
      testWidgets('a full document lays out without overflow at ${scale}x', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360 * 2, 800 * 2);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          host(
            const StreamingMarkdown.static(
              data:
                  '# Heading with a fairly long title\n\n'
                  'Paragraph with `inline code` and a [link](https://x.y).\n\n'
                  '1. first item with quite a lot of text to wrap around\n'
                  '   - nested item\n\n'
                  '> quoted words that also wrap onto several lines\n\n'
                  '```dart\nfinal veryLongVariableName = someFunction(argument);\n```\n\n'
                  '| Name | Description |\n|---|---|\n| a-long-cell-value | another long cell value |\n',
            ),
            textScale: scale,
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(CodeBlockView), findsOneWidget);
        expect(find.byType(Table), findsOneWidget);
      });
    }
  });
}
