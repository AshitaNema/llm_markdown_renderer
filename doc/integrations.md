# Integration recipes

`StreamingMarkdown` only needs text: any source that can produce a
`Stream<String>` (or calls to `controller.append`) works. These recipes show
the common ones. They are sketches written against the public HTTP/SDK
behavior at the time of writing; check them against the version of the SDK you
use.

> **API keys.** Never ship a provider API key inside a client app. Call your own
> backend, which holds the key and forwards the stream. The recipes below show
> the provider side so you can see where the text comes from.

All recipes use the controller API, which is the one to prefer when the same
message can be shown in several places or regenerated:

```dart
final controller = MarkdownStreamController();

// ... fill it from one of the recipes below ...

StreamingMarkdown(controller: controller);
```

Call `controller.complete()` when the answer is finished and
`controller.reset()` before regenerating.

## Any `Stream<String>`

```dart
final sub = tokens.listen(
  controller.append,
  onError: (Object e) => controller.append('\n\n_Something went wrong._'),
  onDone: controller.complete,
);
// remember to cancel `sub` and dispose the controller
```

Or hand the stream to the widget:

```dart
StreamingMarkdown.fromStream(stream: tokens)
```

## Firebase AI Logic (`firebase_ai`)

```dart
final model = FirebaseAI.googleAI().generativeModel(model: 'gemini-2.5-flash');

Future<void> ask(String prompt, MarkdownStreamController controller) async {
  controller.reset();
  await for (final chunk in model.generateContentStream([Content.text(prompt)])) {
    final text = chunk.text;
    if (text != null) controller.append(text);
  }
  controller.complete();
}
```

## OpenAI-compatible servers (SSE)

Server-sent events arrive as bytes. Decode them as UTF-8 **as a stream**
(`utf8.decoder` handles multi-byte characters that are split between network
packets), split into lines, and pick the `data:` payloads:

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;

Stream<String> openAiTokens(Uri url, String apiKey, String prompt) async* {
  final client = http.Client();
  try {
    final request = http.Request('POST', url)
      ..headers.addAll({
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      })
      ..body = jsonEncode({
        'model': 'gpt-4o-mini',
        'stream': true,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
      });
    final response = await client.send(request);
    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trim();
      if (data == '[DONE]') break;
      final delta = jsonDecode(data)['choices'][0]['delta']['content'];
      if (delta is String) yield delta;
    }
  } finally {
    client.close();
  }
}
```

## Anthropic Messages API (SSE)

The text arrives in `content_block_delta` events:

```dart
Stream<String> anthropicTokens(String apiKey, String prompt) async* {
  final client = http.Client();
  try {
    final request =
        http.Request('POST', Uri.parse('https://api.anthropic.com/v1/messages'))
          ..headers.addAll({
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
            'content-type': 'application/json',
          })
          ..body = jsonEncode({
            'model': 'claude-sonnet-5-5',
            'max_tokens': 2048,
            'stream': true,
            'messages': [
              {'role': 'user', 'content': prompt},
            ],
          });
    final response = await client.send(request);
    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final event = jsonDecode(line.substring(5).trim()) as Map<String, dynamic>;
      if (event['type'] != 'content_block_delta') continue;
      final delta = event['delta'] as Map<String, dynamic>;
      if (delta['type'] == 'text_delta') yield delta['text'] as String;
    }
  } finally {
    client.close();
  }
}
```

## Other SDKs

Packages such as `flutter_ai_toolkit` and `langchain_dart` also expose streams
of text chunks. Map their chunk type to `String` and use the "Any
`Stream<String>`" pattern above. Recipes for them are welcome as pull
requests.
