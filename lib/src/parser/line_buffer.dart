/// Splits arbitrary chunks of text into complete lines.
///
/// Handles `\n`, `\r\n` and lone `\r` terminators even when a terminator is
/// split across two chunks, and never splits a UTF-16 surrogate pair: a
/// dangling high surrogate at the end of a chunk is held back until the next
/// chunk arrives.
final class LineBuffer {
  final StringBuffer _pending = StringBuffer();
  bool _skipLf = false;
  String? _heldHigh;

  /// The text after the last line terminator received so far.
  String get pending => _pending.toString();

  /// Adds [chunk] and returns the lines it completed.
  List<String> add(String chunk) {
    final out = <String>[];
    var s = chunk;
    if (_heldHigh != null) {
      s = _heldHigh! + s;
      _heldHigh = null;
    }
    if (s.isEmpty) return out;
    final last = s.codeUnitAt(s.length - 1);
    if (last >= 0xD800 && last <= 0xDBFF) {
      _heldHigh = s.substring(s.length - 1);
      s = s.substring(0, s.length - 1);
    }
    if (s.isEmpty) return out;

    var i = 0;
    if (_skipLf && s.codeUnitAt(0) == 0x0A) i = 1;
    _skipLf = false;
    var lineStart = i;
    for (; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c != 0x0A && c != 0x0D) continue;
      _pending.write(s.substring(lineStart, i));
      out.add(_pending.toString());
      _pending.clear();
      if (c == 0x0D) {
        if (i + 1 < s.length) {
          if (s.codeUnitAt(i + 1) == 0x0A) i++;
        } else {
          _skipLf = true;
        }
      }
      lineStart = i + 1;
    }
    if (lineStart < s.length) _pending.write(s.substring(lineStart));
    return out;
  }

  /// Returns the unterminated last line (or `null` if there is none) and
  /// empties the buffer.
  String? flush() {
    if (_heldHigh != null) {
      _pending.write(_heldHigh);
      _heldHigh = null;
    }
    final rest = _pending.toString();
    _pending.clear();
    return rest.isEmpty ? null : rest;
  }
}
