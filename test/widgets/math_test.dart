import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown_renderer/llm_markdown_renderer.dart';

Widget host(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

/// A stand-in for a real math typesetter: records every call and shows the
/// TeX in a recognisable widget.
class FakeMath {
  final List<(String, bool)> calls = [];

  final List<TextStyle> styles = [];

  Widget build(BuildContext context, InlineMath math, TextStyle style) {
    calls.add((math.tex, math.display));
    styles.add(style);
    return Text('[${math.display ? 'D' : 'I'}:${math.tex}]');
  }
}

void main() {
  testWidgets('without a builder, the TeX source is shown in code style', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const StreamingMarkdown.static(
          data: 'Area: \$\\pi r^2\$.\n\n\$\$\nE = mc^2\n\$\$\n',
          selectable: false,
        ),
      ),
    );
    final rich = tester.widget<RichText>(find.byType(RichText).first);
    expect(rich.text.toPlainText(), 'Area: \\pi r^2.');
    expect(find.text('E = mc^2'), findsOneWidget);
  });

  testWidgets('the builder typesets inline and display math', (tester) async {
    final math = FakeMath();
    await tester.pumpWidget(
      host(
        StreamingMarkdown.static(
          data: 'Inline \$x^2\$ and \$\$y\$\$.\n\n\$\$\nz\n\$\$\n',
          mathBuilder: math.build,
          selectable: false,
        ),
      ),
    );
    expect(math.calls, containsAll([('x^2', false), ('y', true), ('z', true)]));
    expect(find.text('[D:z]'), findsOneWidget);
  });

  testWidgets('open math is shown as source and typeset once closed', (
    tester,
  ) async {
    final math = FakeMath();
    final c = MarkdownStreamController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      host(
        StreamingMarkdown(
          controller: c,
          mathBuilder: math.build,
          selectable: false,
        ),
      ),
    );
    c.append('Value \$\\frac{a}{');
    await tester.pump();
    expect(math.calls, isEmpty, reason: 'never sees half-written TeX');
    c.append('b}\$ done.\n\n\$\$\n\\int_0^1');
    await tester.pump();
    expect(math.calls, [(r'\frac{a}{b}', false)]);
    expect(find.text(r'\int_0^1'), findsOneWidget);
    c.append(' x\\,dx\n\$\$\n');
    await tester.pump();
    expect(math.calls.last, (r'\int_0^1 x\,dx', true));
    expect(find.text(r'[D:\int_0^1 x\,dx]'), findsOneWidget);
  });

  testWidgets('finished math is not rebuilt while later text streams', (
    tester,
  ) async {
    final math = FakeMath();
    final c = MarkdownStreamController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      host(
        StreamingMarkdown(
          controller: c,
          mathBuilder: math.build,
          selectable: false,
        ),
      ),
    );
    c.append('\$\$\nz\n\$\$\n\nafter');
    await tester.pump();
    final count = math.calls.length;
    for (final chunk in [' more', ' text', ' here']) {
      c.append(chunk);
      await tester.pump();
    }
    expect(math.calls.length, count);
  });

  testWidgets('wide display math scrolls instead of overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      host(
        StreamingMarkdown.static(
          data: '\$\$\n${'x + ' * 200}y\n\$\$\n',
          mathBuilder: (context, math, style) =>
              SizedBox(width: 2000, height: 20, child: Text(math.tex)),
          selectable: false,
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsNWidgets(2));
  });

  testWidgets('math source stays left-to-right in a right-to-left app', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: StreamingMarkdown.static(
              data: '\$\$\na - b\n\$\$\n',
              selectable: false,
            ),
          ),
        ),
      ),
    );
    final text = find.text('a - b');
    expect(Directionality.of(tester.element(text)), TextDirection.ltr);
  });

  testWidgets('the builder gets the surrounding text style', (tester) async {
    final math = FakeMath();
    await tester.pumpWidget(
      host(
        StreamingMarkdown.static(
          data: '# Area \$\\pi r^2\$\n\nBody **\$x\$**\n',
          mathBuilder: math.build,
          selectable: false,
        ),
      ),
    );
    final theme = MarkdownTheme.of(tester.element(find.byType(Scaffold)));
    expect(math.calls, [(r'\pi r^2', false), ('x', false)]);
    expect(math.styles[0].fontSize, theme.headingStyle(1).fontSize);
    expect(math.styles[1].fontSize, theme.bodyStyle.fontSize);
    expect(math.styles[1].fontWeight, FontWeight.bold);
  });
}
