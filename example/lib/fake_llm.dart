import 'dart:async';
import 'dart:math';

/// A pretend LLM: replays canned Markdown as a stream of small, irregular
/// chunks, like tokens arriving over the network.
///
/// Chunk sizes are deliberately awkward (1–12 characters) so boundaries fall
/// in the middle of code fences, table rows, links and emphasis markers.
class FakeLlm {
  /// Creates the fake model. [seed] makes chunking reproducible.
  FakeLlm({int? seed}) : _random = Random(seed);

  final Random _random;

  /// Average delay between chunks is divided by this factor.
  double speed = 1;

  int _next = 0;

  /// Picks the next canned reply (cycling), or a very long one for stress.
  String replyFor(String prompt, {bool stress = false}) {
    if (stress) {
      return List.generate(
        25,
        (i) => '## Section ${i + 1}\n\n$_stressUnit',
      ).join('\n');
    }
    final reply = _replies[_next % _replies.length];
    _next++;
    return reply;
  }

  /// Streams [markdown] in random chunks.
  Stream<String> stream(String markdown) async* {
    var i = 0;
    while (i < markdown.length) {
      final n = min(markdown.length - i, 1 + _random.nextInt(12));
      yield markdown.substring(i, i + n);
      i += n;
      final ms = (10 + _random.nextInt(30)) / speed;
      await Future<void>.delayed(Duration(microseconds: (ms * 1000).round()));
    }
  }
}

const _stressUnit =
    '''Some **bold**, *italic* and `inline code` text with a [link](https://flutter.dev).

- point one
- point two
  - nested point

```dart
void main() {
  for (var i = 0; i < 3; i++) {
    print('line \$i'); // comment
  }
}
```

| key | value |
|-----|------:|
| a   | 1     |
| b   | 22    |
''';

const _replies = [
  r'''# Streaming Markdown

Here is a quick tour of what **llm_markdown_renderer** handles *while the text is still arriving*.

## Inline styles

You get **bold**, *italic*, ~~strikethrough~~, `inline code` and [links](https://pub.dev). Bare URLs such as https://flutter.dev become links too. While it streams, half-typed syntax such as **this bold phrase never flickers into asterisks** as it arrives.

## A code block

```dart
import 'dart:async';

/// Counts down from [from] to zero.
Stream<int> countdown(int from) async* {
  for (var i = from; i >= 0; i--) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    yield i; // emit the value
  }
}
```

The block above had its **header and copy button** from the moment the opening fence arrived.

## Lists

1. First step
2. Second step
   - nested bullet
   - another nested bullet
3. Third step

- [x] Parse incrementally
- [x] Highlight code
- [ ] Take over the world

> Block quotes work too, and can contain **formatting**
> over several lines.
''',
  r'''## Comparing options

Here is a table that grows row by row, without the columns jumping around:

| Package | Streaming | Highlighting | Notes |
|---------|:---------:|:------------:|-------|
| llm_markdown_renderer | yes | yes | incremental parser |
| naive re-parse | no | maybe | O(n) per token |
| plain `Text` | yes | no | no formatting at all |

And some Python and shell for good measure:

```python
def fib(n: int) -> int:
    """Return the n-th Fibonacci number."""
    a, b = 0, 1
    for _ in range(n):
        a, b = b, a + b
    return a

print([fib(i) for i in range(10)])  # [0, 1, 1, 2, 3, ...]
```

```bash
# build and run
flutter pub get && flutter run -d chrome --release
echo "done: $?"
```

```json
{
  "name": "demo",
  "tags": ["markdown", "llm"],
  "stream": true,
  "chunks": 1234
}
```
''',
  r'''### A diff and some prose

Models love to explain changes. Here is one:

```diff
--- a/lib/main.dart
+++ b/lib/main.dart
@@ -1,4 +1,4 @@
-final text = Text(markdown);
+final text = StreamingMarkdown(controller: controller);
 void main() => runApp(const App());
```

Mixed content: an ordered list with code inside.

1. Create a controller:

   ```dart
   final controller = MarkdownStreamController();
   ```

2. Feed it with tokens:

   ```dart
   tokens.listen(controller.append, onDone: controller.complete);
   ```

3. Show it with `StreamingMarkdown(controller: controller)`.

---

That's all! Ask me again for a different example.
''',
];
