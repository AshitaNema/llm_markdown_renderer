import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:llm_markdown_renderer/llm_markdown_renderer.dart';

import 'fake_llm.dart';

void main() => runApp(const ChatDemoApp());

/// Root of the demo: a Material app whose theme carries a [MarkdownTheme]
/// extension, so every Markdown view below follows light/dark mode.
class ChatDemoApp extends StatefulWidget {
  /// Creates the demo app.
  const ChatDemoApp({super.key});

  @override
  State<ChatDemoApp> createState() => _ChatDemoAppState();
}

class _ChatDemoAppState extends State<ChatDemoApp> {
  ThemeMode _mode = ThemeMode.system;

  ThemeData _theme(Brightness brightness) {
    final base = ThemeData(
      colorSchemeSeed: Colors.indigo,
      brightness: brightness,
      useMaterial3: true,
    );
    // Customise the Markdown look through a ThemeExtension.
    return base.copyWith(
      extensions: [
        MarkdownTheme.fromTheme(
          base,
        ).copyWith(codeBlockBorderRadius: 12, blockSpacing: 14),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'llm_markdown_renderer demo',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: _mode,
      home: ChatPage(
        isDark:
            Theme.of(context).brightness == Brightness.dark ||
            _mode == ThemeMode.dark,
        onToggleTheme: () => setState(() {
          final dark =
              MediaQuery.platformBrightnessOf(context) == Brightness.dark;
          _mode = switch (_mode) {
            ThemeMode.dark => ThemeMode.light,
            ThemeMode.light => ThemeMode.dark,
            ThemeMode.system => dark ? ThemeMode.light : ThemeMode.dark,
          };
        }),
      ),
    );
  }
}

/// One chat message. Assistant messages own a controller that the fake LLM
/// stream is piped into.
class _Message {
  _Message.user(this.text) : isUser = true, markdown = '', controller = null;

  _Message.assistant({required this.markdown})
    : isUser = false,
      text = '',
      controller = MarkdownStreamController();

  final bool isUser;
  final String text;
  final String markdown;
  final MarkdownStreamController? controller;
  StreamSubscription<String>? subscription;
  bool streaming = false;
  int chunks = 0;
}

/// The chat screen.
class ChatPage extends StatefulWidget {
  /// Creates the chat screen.
  const ChatPage({
    super.key,
    required this.isDark,
    required this.onToggleTheme,
  });

  /// Whether the dark theme is active (for the toggle icon).
  final bool isDark;

  /// Switches between light and dark.
  final VoidCallback onToggleTheme;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final FakeLlm _llm = FakeLlm();
  final List<_Message> _messages = [];
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final _FrameStats _stats = _FrameStats();
  double _speed = 1;

  @override
  void initState() {
    super.initState();
    _stats.start();
    _send('Show me what you can do');
  }

  @override
  void dispose() {
    _stats.stop();
    for (final m in _messages) {
      m.subscription?.cancel();
      m.controller?.dispose();
    }
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send(String prompt, {bool stress = false}) {
    if (prompt.trim().isEmpty) return;
    final reply = _Message.assistant(
      markdown: _llm.replyFor(prompt, stress: stress),
    );
    setState(() {
      _messages
        ..add(
          _Message.user(
            stress ? 'Stress test: stream a very long reply' : prompt,
          ),
        )
        ..add(reply);
    });
    _input.clear();
    _stream(reply);
  }

  void _stream(_Message m) {
    m.subscription?.cancel();
    m.chunks = 0;
    m.streaming = true;
    _llm.speed = _speed;
    m.subscription = _llm
        .stream(m.markdown)
        .listen(
          (chunk) {
            m.chunks++;
            m.controller!.append(chunk); // <- the whole integration
            _stickToBottom();
          },
          onDone: () {
            m.controller!.complete();
            if (mounted) setState(() => m.streaming = false);
          },
        );
    _stickToBottom();
  }

  void _regenerate(_Message m) {
    m.controller!.reset(); // clears the view
    setState(() {});
    _stream(m);
  }

  void _stop(_Message m) {
    m.subscription?.cancel();
    m.controller!.complete();
    setState(() => m.streaming = false);
  }

  void _stickToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final p = _scroll.position;
      if (p.maxScrollExtent - p.pixels < 160) {
        _scroll.jumpTo(p.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final last = _messages.isEmpty ? null : _messages.last;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Streaming Markdown'),
        actions: [
          ValueListenableBuilder<String>(
            valueListenable: _stats.label,
            builder: (_, label, _) => Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(label, style: const TextStyle(fontSize: 11)),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Toggle light/dark',
            icon: Icon(widget.isDark ? Icons.light_mode : Icons.dark_mode),
            onPressed: widget.onToggleTheme,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, i) => _Bubble(
                message: _messages[i],
                onRegenerate: _messages[i] == last && !_messages[i].isUser
                    ? () => _regenerate(_messages[i])
                    : null,
                onStop: _messages[i].streaming
                    ? () => _stop(_messages[i])
                    : null,
                onTapLink: (url, title) => ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Tapped link: $url'))),
              ),
            ),
          ),
          _Controls(
            speed: _speed,
            onSpeed: (v) {
              setState(() => _speed = v);
              _llm.speed = v;
            },
            onStress: () => _send('', stress: true),
          ),
          _InputBar(controller: _input, onSend: _send),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.onTapLink,
    this.onRegenerate,
    this.onStop,
  });

  final _Message message;
  final MarkdownLinkCallback onTapLink;
  final VoidCallback? onRegenerate;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (message.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: const BoxConstraints(maxWidth: 520),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            message.text,
            style: TextStyle(color: scheme.onPrimaryContainer),
          ),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        constraints: const BoxConstraints(maxWidth: 760),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StreamingMarkdown(
              controller: message.controller!,
              onTapLink: onTapLink,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onStop != null)
                  TextButton.icon(
                    onPressed: onStop,
                    icon: const Icon(Icons.stop_circle_outlined, size: 18),
                    label: const Text('Stop'),
                  )
                else if (onRegenerate != null)
                  TextButton.icon(
                    onPressed: onRegenerate,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Regenerate'),
                  ),
                if (message.streaming)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      '${message.chunks} chunks',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.speed,
    required this.onSpeed,
    required this.onStress,
  });

  final double speed;
  final ValueChanged<double> onSpeed;
  final VoidCallback onStress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.speed, size: 18),
          Expanded(
            child: Slider(
              value: speed,
              min: 0.25,
              max: 8,
              divisions: 31,
              label: '${speed.toStringAsFixed(2)}x',
              onChanged: onSpeed,
            ),
          ),
          Text('${speed.toStringAsFixed(1)}x'),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: onStress, child: const Text('Stress')),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({required this.controller, required this.onSend});

  final TextEditingController controller;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                onSubmitted: onSend,
                decoration: const InputDecoration(
                  hintText: 'Ask anything (the answer is canned)…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: () => onSend(controller.text),
              icon: const Icon(Icons.send),
              tooltip: 'Send',
            ),
          ],
        ),
      ),
    );
  }
}

/// Collects frame timings and exposes a one-line summary.
class _FrameStats {
  final ValueNotifier<String> label = ValueNotifier('frames: …');
  final List<double> _recent = [];

  /// The first frames pay one-off costs (fonts, shaders, first layout) and
  /// would dominate the "worst" figure for the next second, so they are not
  /// counted.
  int _warmUpFrames = 10;

  void start() => SchedulerBinding.instance.addTimingsCallback(_onTimings);

  void stop() => SchedulerBinding.instance.removeTimingsCallback(_onTimings);

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      if (_warmUpFrames > 0) {
        _warmUpFrames--;
        continue;
      }
      _recent.add(t.totalSpan.inMicroseconds / 1000);
    }
    if (_recent.isEmpty) return;
    if (_recent.length > 60) _recent.removeRange(0, _recent.length - 60);
    final avg = _recent.reduce((a, b) => a + b) / _recent.length;
    final worst = _recent.reduce((a, b) => a > b ? a : b);
    label.value =
        'frame avg ${avg.toStringAsFixed(1)} ms · worst ${worst.toStringAsFixed(1)} ms';
  }
}
