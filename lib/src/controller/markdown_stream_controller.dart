import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../ast/document.dart';
import '../parser/block_parser.dart';
import '../parser/options.dart';

/// How a [MarkdownStreamController] paces text that arrives in bursts.
///
/// Models and networks rarely deliver text evenly: a pause, then forty
/// tokens at once. With a pace, appended text goes into a small buffer and is
/// shown at a steady [charactersPerSecond], one frame at a time, so the answer
/// appears to type itself instead of jumping. When the buffer grows, the
/// speed rises so that what is shown is never more than about [maxDelay]
/// behind what has arrived.
///
/// ```dart
/// final controller = MarkdownStreamController(pace: const TypingPace());
/// ```
///
/// Text is released by frame callbacks, so it only appears while Flutter
/// produces frames. In widget tests, pump frames until
/// [MarkdownStreamController.pendingLength] is 0, or call
/// [MarkdownStreamController.flush] before the test ends (disposing the
/// controller in `addTearDown` is too late); otherwise the test fails with
/// "An animation is still running".
@immutable
final class TypingPace {
  /// Creates a pace. [charactersPerSecond] must be positive and finite; a
  /// negative [maxDelay] counts as zero.
  const TypingPace({
    this.charactersPerSecond = 250,
    this.maxDelay = const Duration(milliseconds: 400),
  }) : assert(
         charactersPerSecond > 0 && charactersPerSecond < double.infinity,
         'charactersPerSecond must be positive and finite',
       );

  /// The steady speed, in UTF-16 code units per second, when little text is
  /// waiting.
  final double charactersPerSecond;

  /// How far, at most, the shown text lags behind the received text. Each
  /// chunk is on screen at most this long after it arrives (rounded up to the
  /// next frame); a larger backlog is shown faster to keep that promise.
  final Duration maxDelay;

  @override
  bool operator ==(Object other) =>
      other is TypingPace &&
      other.charactersPerSecond == charactersPerSecond &&
      other.maxDelay == maxDelay;

  @override
  int get hashCode => Object.hash(TypingPace, charactersPerSecond, maxDelay);

  @override
  String toString() =>
      'TypingPace(charactersPerSecond: $charactersPerSecond, '
      'maxDelay: ${maxDelay.inMilliseconds} ms)';
}

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
///
/// Pass a [pace] to smooth out bursty streams; see [TypingPace].
class MarkdownStreamController extends ChangeNotifier {
  /// Creates a controller, optionally pre-filled with [initialText].
  ///
  /// With [coalesceNotifications] (the default) listeners are notified once
  /// per frame; set it to `false` to notify synchronously on every change
  /// (useful in tests).
  ///
  /// With a [pace], appended text is shown gradually instead of at once, and
  /// listeners are notified when text is shown, not when it is appended.
  /// [initialText] is always shown immediately.
  MarkdownStreamController({
    String initialText = '',
    MarkdownParserOptions options = const MarkdownParserOptions(),
    this.coalesceNotifications = true,
    this.pace,
  }) : _parser = IncrementalMarkdownParser(options: options) {
    if (initialText.isNotEmpty) {
      _text.write(initialText);
      _parser.append(initialText);
    }
  }

  /// Whether notifications are coalesced to one per frame.
  final bool coalesceNotifications;

  /// How bursty text is smoothed, or `null` to show text as soon as it is
  /// appended.
  final TypingPace? pace;

  final IncrementalMarkdownParser _parser;
  final StringBuffer _text = StringBuffer();
  bool _scheduled = false;
  bool _disposed = false;

  // Paced text that is not shown yet: the chunks from [_head] on, the first
  // of them shown up to [_offset]. A queue rather than one string, so
  // appending stays O(chunk) however much is waiting.
  final List<String> _queue = [];
  int _head = 0;
  int _offset = 0;

  /// Where waiting text must be shown by: one entry per frame in which
  /// chunks arrived, with the end of the last of them (counting from the
  /// start of the stream) and its deadline (set on the next frame). Chunks
  /// that arrive between two frames share an entry, so this list stays as
  /// short as the number of frames in [TypingPace.maxDelay].
  final List<_Due> _due = [];
  int _received = 0;
  int _released = 0;
  bool _completeRequested = false;
  int? _tickId;
  Duration? _lastTick;
  double _budget = 0;

  /// The current document snapshot.
  ///
  /// Blocks that are finished keep their identity between snapshots.
  MarkdownDocument get document => _parser.document;

  /// Everything appended so far, as raw Markdown, including text a [pace]
  /// has not shown yet.
  String get text => _text.toString();

  /// Whether the document is finished: [complete] has been called and, with
  /// a [pace], everything received has been shown.
  ///
  /// Paced text is shown by frame callbacks, so while the app is in the
  /// background (no frames) a completed stream stays unfinished until the
  /// app is visible again. Read [text] if you need everything received.
  bool get isComplete => _parser.isComplete;

  /// How many characters (UTF-16 code units) have been received but not
  /// shown yet. Always 0 without a [pace].
  int get pendingLength => _received - _released;

  /// How often inline content was parsed; see
  /// [IncrementalMarkdownParser.debugInlineParseCount].
  int get debugInlineParseCount => _parser.debugInlineParseCount;

  /// Appends [chunk] to the document.
  ///
  /// Parsing happens synchronously and costs time proportional to the chunk
  /// plus the one block that is still open; with a [pace] the chunk is
  /// parsed when it is shown. Throws a [StateError] after [complete]; call
  /// [reset] to start over.
  void append(String chunk) {
    if (chunk.isEmpty) return;
    if (_completeRequested) {
      throw StateError('append() called after complete(); call reset() first.');
    }
    _text.write(chunk);
    if (pace != null && _startTicking()) {
      _queue.add(chunk);
      _received += chunk.length;
      if (_due.isNotEmpty && _due.last.deadline == null) {
        _due.last.end = _received;
      } else {
        _due.add(_Due(_received));
      }
      return;
    }
    _parser.append(chunk);
    _notify();
  }

  /// Marks the stream as finished: open blocks are closed and unterminated
  /// code fences, tables and emphasis are finalized.
  ///
  /// With a [pace], the document is finished once the text still waiting has
  /// been shown; call [flush] to finish it right away.
  void complete() {
    if (_completeRequested) return;
    _completeRequested = true;
    if (pendingLength > 0) return;
    _parser.complete();
    _notify();
  }

  /// Shows all text a [pace] is still holding back, at once (and finishes
  /// the document if [complete] was called), e.g. when the user stops the
  /// answer or scrolls away.
  void flush() {
    _stopTicking();
    if (pendingLength > 0) _parser.append(_take(pendingLength));
    if (_completeRequested && !_parser.isComplete) _parser.complete();
    _notify();
  }

  /// Discards the content and starts over, e.g. when regenerating an answer.
  void reset([String initialText = '']) {
    _stopTicking();
    _queue.clear();
    _head = _offset = 0;
    _due.clear();
    _received = _released = 0;
    _completeRequested = false;
    _parser.reset();
    _text.clear();
    if (initialText.isNotEmpty) {
      _text.write(initialText);
      _parser.append(initialText);
    }
    _notify();
  }

  /// Removes and returns the next [n] waiting code units.
  String _take(int n) {
    final out = StringBuffer();
    var left = n;
    while (left > 0) {
      final head = _queue[_head];
      final available = head.length - _offset;
      if (available <= left) {
        out.write(_offset == 0 ? head : head.substring(_offset));
        _head++;
        _offset = 0;
        left -= available;
      } else {
        out.write(head.substring(_offset, _offset + left));
        _offset += left;
        left = 0;
      }
    }
    if (_head == _queue.length) {
      _queue.clear();
      _head = 0;
    } else if (_head > 64 && _head * 2 > _queue.length) {
      _queue.removeRange(0, _head);
      _head = 0;
    }
    _released += n;
    _due.removeWhere((d) => d.end <= _released);
    return out.toString();
  }

  /// The waiting code unit at [index] (0 is the next one to be shown).
  int _pendingCodeUnitAt(int index) {
    var i = index + _offset;
    for (var k = _head; k < _queue.length; k++) {
      final chunk = _queue[k];
      if (i < chunk.length) return chunk.codeUnitAt(i);
      i -= chunk.length;
    }
    throw RangeError.index(index, this, 'index', null, pendingLength);
  }

  SchedulerBinding? get _binding {
    try {
      return SchedulerBinding.instance;
      // The binding getter throws (FlutterError in debug, an Error from the
      // late field in release) when Flutter has not been initialised; there
      // is no public way to ask, and any failure means "no frames".
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return null;
    }
  }

  /// Makes sure a frame callback will release pending text. Returns `false`
  /// when there are no frames (Flutter is not initialised), in which case
  /// text is shown immediately.
  bool _startTicking() {
    if (_tickId != null) return true;
    final binding = _binding;
    if (binding == null) return false;
    _tickId = binding.scheduleFrameCallback(_tick);
    return true;
  }

  void _stopTicking() {
    final id = _tickId;
    if (id != null) _binding?.cancelFrameCallbackWithId(id);
    _tickId = null;
    _lastTick = null;
    _budget = 0;
  }

  void _tick(Duration now) {
    _tickId = null;
    if (_disposed) return;
    final p = pace!;
    final delay = p.maxDelay.isNegative ? Duration.zero : p.maxDelay;
    for (final d in _due) {
      d.deadline ??= now + delay;
    }
    // After a quiet spell there is no previous frame; count one frame, so a
    // slow stream shows its text on the frame after it arrives instead of
    // waiting a frame for the clock to start.
    final last = _lastTick ?? now - _frame;
    _lastTick = now;
    if (pendingLength > 0) {
      final dt = (now - last).inMicroseconds / 1e6;
      // The speed that shows every waiting chunk by its deadline, and what
      // is already overdue (after a long gap, e.g. the app was paused).
      var rate = p.charactersPerSecond;
      var overdue = 0;
      for (final d in _due) {
        final left = d.end - _released;
        final secondsLeft = (d.deadline! - now).inMicroseconds / 1e6;
        if (secondsLeft <= 0) {
          overdue = left;
        } else if (left / secondsLeft > rate) {
          rate = left / secondsLeft;
        }
      }
      _budget += dt * rate;
      var n = _budget.floor();
      if (n < overdue) n = overdue;
      if (n > 0) {
        _budget = n > _budget ? 0 : _budget - n;
        if (n > pendingLength) n = pendingLength;
        // Never split a surrogate pair (an emoji) across frames.
        if (n < pendingLength) {
          final c = _pendingCodeUnitAt(n - 1);
          if (c >= 0xD800 && c <= 0xDBFF) n++;
        }
        _parser.append(_take(n));
        if (pendingLength == 0 && _completeRequested) _parser.complete();
        // Already inside a frame: notify now so this frame shows the text.
        notifyListeners();
      }
    }
    if (_disposed) return;
    if (pendingLength > 0) {
      // A listener may already have scheduled the next tick (by appending).
      _startTicking();
    } else if (_tickId == null) {
      _lastTick = null;
      _budget = 0;
    }
  }

  static const Duration _frame = Duration(microseconds: 16667);

  void _notify() {
    if (_disposed) return;
    if (!coalesceNotifications) {
      notifyListeners();
      return;
    }
    if (_scheduled) return;
    final binding = _binding;
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
    _stopTicking();
    _disposed = true;
    super.dispose();
  }
}

/// Where some paced text ends and by when it must be shown.
class _Due {
  _Due(this.end);
  int end;
  Duration? deadline;
}
