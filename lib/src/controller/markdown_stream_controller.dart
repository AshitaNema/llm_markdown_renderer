import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../ast/document.dart';
import '../parser/block_parser.dart';
import '../parser/options.dart';

/// Accumulates streamed Markdown and exposes the incrementally parsed
/// [document] to the UI.
///
/// Feed it with [append] as tokens arrive and call [complete] when the model
/// is done. Listeners (such as `StreamingMarkdown`) are notified at most once
/// per frame no matter how many chunks arrived in between, so a provider that
/// emits hundreds of tokens per second costs one rebuild per frame.
///
/// ```dart
/// final controller = MarkdownStreamController();
/// llmTokens.listen(controller.append, onDone: controller.complete);
/// // ...
/// StreamingMarkdown(controller: controller);
/// ```
class MarkdownStreamController extends ChangeNotifier {
  /// Creates a controller, optionally pre-filled with [initialText].
  ///
  /// With [coalesceNotifications] (the default) listeners are notified once
  /// per frame; set it to `false` to notify synchronously on every change
  /// (useful in tests).
  MarkdownStreamController({
    String initialText = '',
    MarkdownParserOptions options = const MarkdownParserOptions(),
    this.coalesceNotifications = true,
  }) : _parser = IncrementalMarkdownParser(options: options) {
    if (initialText.isNotEmpty) {
      _text.write(initialText);
      _parser.append(initialText);
    }
  }

  /// Whether notifications are coalesced to one per frame.
  final bool coalesceNotifications;

  final IncrementalMarkdownParser _parser;
  final StringBuffer _text = StringBuffer();
  bool _scheduled = false;
  bool _disposed = false;

  /// The current document snapshot.
  ///
  /// Blocks that are finished keep their identity between snapshots.
  MarkdownDocument get document => _parser.document;

  /// Everything appended so far, as raw Markdown.
  String get text => _text.toString();

  /// Whether [complete] has been called.
  bool get isComplete => _parser.isComplete;

  /// How often inline content was parsed; see
  /// [IncrementalMarkdownParser.debugInlineParseCount].
  int get debugInlineParseCount => _parser.debugInlineParseCount;

  /// Appends [chunk] to the document.
  ///
  /// Parsing happens synchronously and costs time proportional to the chunk
  /// plus the one block that is still open. Throws a [StateError] after
  /// [complete]; call [reset] to start over.
  void append(String chunk) {
    if (chunk.isEmpty) return;
    _parser.append(chunk);
    _text.write(chunk);
    _notify();
  }

  /// Marks the stream as finished: open blocks are closed and unterminated
  /// code fences, tables and emphasis are finalized.
  void complete() {
    if (_parser.isComplete) return;
    _parser.complete();
    _notify();
  }

  /// Discards the content and starts over, e.g. when regenerating an answer.
  void reset([String initialText = '']) {
    _parser.reset();
    _text.clear();
    if (initialText.isNotEmpty) {
      _text.write(initialText);
      _parser.append(initialText);
    }
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    if (!coalesceNotifications) {
      notifyListeners();
      return;
    }
    if (_scheduled) return;
    SchedulerBinding? binding;
    try {
      binding = SchedulerBinding.instance;
      // The binding getter throws (FlutterError in debug, an Error from the
      // late field in release) when Flutter has not been initialised; there
      // is no public way to ask, and any failure means "notify directly".
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      binding = null;
    }
    if (binding == null) {
      notifyListeners();
      return;
    }
    _scheduled = true;
    binding.scheduleFrameCallback((_) {
      _scheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
