import '../ast/inline.dart';
import 'options.dart';

/// Parses the inline content of a single block.
///
/// With [streaming] set, the text is treated as the still-growing end of a
/// document: unclosed emphasis and code spans are closed speculatively, and
/// incomplete link syntax is hidden instead of being shown as literal
/// punctuation, so the output does not flicker as more text arrives.
List<Inline> parseInlines(
  String source, {
  bool streaming = false,
  MarkdownParserOptions options = const MarkdownParserOptions(),
}) => _InlineParser(source, streaming, options).parse();

final RegExp _wsRe = RegExp(r'\s');
final RegExp _punctRe = RegExp(r'[\p{P}\p{S}]', unicode: true);
final RegExp _entityRe = RegExp(
  r'&(#[xX][0-9a-fA-F]{1,6}|#[0-9]{1,7}|[A-Za-z]{2,8});',
);
final RegExp _angleAutolinkRe = RegExp(
  r'<([A-Za-z][A-Za-z0-9+.\-]{1,31}:[^\s<>]*)>',
);

const Map<String, String> _entities = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': '\u00A0',
  'copy': '\u00A9',
  'reg': '\u00AE',
  'hellip': '\u2026',
  'mdash': '\u2014',
  'ndash': '\u2013',
  'rarr': '\u2192',
  'larr': '\u2190',
  'times': '\u00D7',
};

bool _isWs(String ch) => _wsRe.hasMatch(ch);
bool _isPunct(String ch) => _punctRe.hasMatch(ch);
bool _isAsciiPunct(String ch) {
  final c = ch.codeUnitAt(0);
  return (c >= 0x21 && c <= 0x2F) ||
      (c >= 0x3A && c <= 0x40) ||
      (c >= 0x5B && c <= 0x60) ||
      (c >= 0x7B && c <= 0x7E);
}

bool _isAlnum(String ch) {
  final c = ch.codeUnitAt(0);
  return (c >= 0x30 && c <= 0x39) ||
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A);
}

/// A run of `*`, `_` or `~` that may open and/or close emphasis.
class _Delim {
  _Delim(this.char, this.count, this.canOpen, this.canClose) : orig = count;

  final String char;
  int count;
  final int orig;
  final bool canOpen;
  final bool canClose;
}

class _Tail {
  _Tail.complete(this.url, this.title, this.end) : incomplete = false;
  _Tail.incomplete() : url = '', title = null, end = 0, incomplete = true;

  final String url;
  final String? title;
  final int end;
  final bool incomplete;
}

class _InlineParser {
  _InlineParser(String source, this.streaming, this.options)
    : s = streaming ? _trimPartial(source) : source,
      n = 0 {
    n = s.length;
  }

  final String s;
  int n;
  final bool streaming;
  final MarkdownParserOptions options;

  final List<Object> toks = [];
  final StringBuffer buf = StringBuffer();
  int i = 0;

  /// Removes trailing syntax that is probably the start of a closing
  /// delimiter or of a link, so it is not painted for a frame and then
  /// restyled when the rest arrives.
  static String _trimPartial(String t) {
    var s = t;
    var end = s.length;
    while (end > 0 && '*_~'.contains(s[end - 1])) {
      end--;
    }
    if (end < s.length) s = s.substring(0, end);
    if (s.endsWith('![')) {
      s = s.substring(0, s.length - 2);
    } else if (s.endsWith('[') || s.endsWith('<')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  List<Inline> parse() {
    while (i < n) {
      final ch = s[i];
      switch (ch) {
        case r'\':
          _backslash();
        case '\n':
          _newline();
        case '`':
          _backtick();
        case '*' || '_' || '~':
          _delimRun();
        case '[':
          _bracket(image: false);
        case '!':
          if (i + 1 < n && s[i + 1] == '[') {
            _bracket(image: true);
          } else {
            buf.write(ch);
            i++;
          }
        case '<':
          _angle();
        case '&':
          _entity();
        case 'h':
          _bareUrl();
        default:
          buf.write(ch);
          i++;
      }
    }
    _flush();
    return _resolve();
  }

  void _flush() {
    if (buf.isEmpty) return;
    toks.add(InlineText(buf.toString()));
    buf.clear();
  }

  void _backslash() {
    if (i + 1 < n) {
      final nx = s[i + 1];
      if (nx == '\n') {
        _flush();
        toks.add(const InlineLineBreak());
        i += 2;
        return;
      }
      if (_isAsciiPunct(nx)) {
        buf.write(nx);
        i += 2;
        return;
      }
    }
    buf.write(r'\');
    i++;
  }

  void _newline() {
    final text = buf.toString();
    var e = text.length;
    while (e > 0 && text[e - 1] == ' ') {
      e--;
    }
    final hard = text.length - e >= 2;
    buf
      ..clear()
      ..write(text.substring(0, e));
    _flush();
    toks.add(hard ? const InlineLineBreak() : const InlineSoftBreak());
    i++;
    while (i < n && s[i] == ' ') {
      i++;
    }
  }

  static String _normalizeCode(String content) {
    final c = content.replaceAll('\n', ' ');
    if (c.length > 2 &&
        c.startsWith(' ') &&
        c.endsWith(' ') &&
        c.trim().isNotEmpty) {
      return c.substring(1, c.length - 1);
    }
    return c;
  }

  void _backtick() {
    var j = i;
    while (j < n && s[j] == '`') {
      j++;
    }
    final len = j - i;
    var k = j;
    var found = -1;
    while (k < n) {
      final at = s.indexOf('`', k);
      if (at < 0) break;
      var e = at;
      while (e < n && s[e] == '`') {
        e++;
      }
      if (e - at == len) {
        found = at;
        break;
      }
      k = e;
    }
    if (found >= 0) {
      _flush();
      toks.add(InlineCode(_normalizeCode(s.substring(j, found))));
      i = found + len;
    } else if (streaming) {
      final rest = s.substring(j);
      if (rest.trim().isNotEmpty) {
        _flush();
        toks.add(InlineCode(_normalizeCode(rest)));
      }
      i = n;
    } else {
      buf.write(s.substring(i, j));
      i = j;
    }
  }

  void _delimRun() {
    final ch = s[i];
    var j = i;
    while (j < n && s[j] == ch) {
      j++;
    }
    final count = j - i;
    if (ch == '~' && (count != 2 || !options.strikethrough)) {
      buf.write(s.substring(i, j));
      i = j;
      return;
    }
    final before = i == 0 ? ' ' : s[i - 1];
    final after = j == n ? ' ' : s[j];
    final wsB = _isWs(before);
    final wsA = _isWs(after);
    final pB = _isPunct(before);
    final pA = _isPunct(after);
    final left = !wsA && (!pA || wsB || pB);
    final right = !wsB && (!pB || wsA || pA);
    final canOpen = ch == '_' ? left && (!right || pB) : left;
    final canClose = ch == '_' ? right && (!left || pA) : right;
    _flush();
    toks.add(_Delim(ch, count, canOpen, canClose));
    i = j;
  }

  /// Index of the `]` matching the `[` at [open], or -1.
  int _findClose(int open) {
    var depth = 0;
    for (var p = open; p < n; p++) {
      final c = s[p];
      if (c == r'\') {
        p++;
      } else if (c == '[') {
        depth++;
      } else if (c == ']') {
        depth--;
        if (depth == 0) return p;
      }
    }
    return -1;
  }

  void _bracket({required bool image}) {
    final open = image ? i + 1 : i;
    final close = _findClose(open);
    final literal = image ? '![' : '[';
    if (close < 0 || close + 1 >= n || s[close + 1] != '(') {
      buf.write(literal);
      i = open + 1;
      return;
    }
    final tail = _linkTail(close + 2);
    final label = s.substring(open + 1, close);
    if (tail == null || (tail.incomplete && !streaming)) {
      buf.write(literal);
      i = open + 1;
      return;
    }
    _flush();
    if (tail.incomplete) {
      if (!image) toks.addAll(_sub(label));
      i = n;
      return;
    }
    if (image) {
      toks.add(
        InlineImage(url: tail.url, alt: _plain(_sub(label)), title: tail.title),
      );
    } else {
      toks.add(
        InlineLink(url: tail.url, title: tail.title, children: _sub(label)),
      );
    }
    i = tail.end;
  }

  List<Inline> _sub(String text) => _InlineParser(text, false, options).parse();

  static String _plain(List<Inline> nodes) {
    final b = StringBuffer();
    void walk(List<Inline> list) {
      for (final node in list) {
        switch (node) {
          case InlineText(:final text):
            b.write(text);
          case InlineCode(:final code):
            b.write(code);
          case InlineEmphasis(:final children) ||
              InlineStrong(:final children) ||
              InlineStrikethrough(:final children) ||
              InlineLink(:final children):
            walk(children);
          case InlineImage(:final alt):
            b.write(alt);
          case InlineLineBreak() || InlineSoftBreak():
            b.write(' ');
        }
      }
    }

    walk(nodes);
    return b.toString();
  }

  /// Parses `url "title")` starting right after `](`.
  _Tail? _linkTail(int from) {
    var q = from;
    void skipWs() {
      while (q < n && _isWs(s[q])) {
        q++;
      }
    }

    skipWs();
    if (q >= n) return _Tail.incomplete();
    String url;
    if (s[q] == '<') {
      final e = s.indexOf('>', q);
      if (e < 0) return _Tail.incomplete();
      url = s.substring(q + 1, e);
      q = e + 1;
    } else {
      var depth = 0;
      final st = q;
      while (q < n) {
        final c = s[q];
        if (_isWs(c)) break;
        if (c == r'\' && q + 1 < n) {
          q += 2;
          continue;
        }
        if (c == '(') {
          depth++;
        } else if (c == ')') {
          if (depth == 0) break;
          depth--;
        }
        q++;
      }
      url = s.substring(st, q);
      if (q >= n) return _Tail.incomplete();
    }
    skipWs();
    if (q >= n) return _Tail.incomplete();
    String? title;
    if (s[q] == '"' || s[q] == "'" || s[q] == '(') {
      final closer = s[q] == '(' ? ')' : s[q];
      final e = s.indexOf(closer, q + 1);
      if (e < 0) return _Tail.incomplete();
      title = s.substring(q + 1, e);
      q = e + 1;
      skipWs();
      if (q >= n) return _Tail.incomplete();
    }
    if (s[q] != ')') return null;
    return _Tail.complete(
      url.replaceAllMapped(RegExp(r'\\([!-/:-@\[-`{-~])'), (m) => m[1]!),
      title,
      q + 1,
    );
  }

  void _angle() {
    if (options.autolinks) {
      final m = _angleAutolinkRe.matchAsPrefix(s, i);
      if (m != null) {
        _flush();
        final url = m[1]!;
        toks.add(InlineLink(url: url, children: [InlineText(url)]));
        i = m.end;
        return;
      }
    }
    buf.write('<');
    i++;
  }

  void _entity() {
    final m = _entityRe.matchAsPrefix(s, i);
    if (m != null) {
      final body = m[1]!;
      String? decoded;
      if (body.startsWith('#')) {
        final cp = body.length > 1 && (body[1] == 'x' || body[1] == 'X')
            ? int.tryParse(body.substring(2), radix: 16)
            : int.tryParse(body.substring(1));
        if (cp != null &&
            cp > 0 &&
            cp <= 0x10FFFF &&
            !(cp >= 0xD800 && cp <= 0xDFFF)) {
          decoded = String.fromCharCode(cp);
        }
      } else {
        decoded = _entities[body];
      }
      if (decoded != null) {
        buf.write(decoded);
        i = m.end;
        return;
      }
    }
    buf.write('&');
    i++;
  }

  void _bareUrl() {
    if (options.autolinks &&
        (i == 0 || !_isAlnum(s[i - 1])) &&
        (s.startsWith('http://', i) || s.startsWith('https://', i))) {
      final schemeLen = s.startsWith('https://', i) ? 8 : 7;
      var e = i + schemeLen;
      while (e < n && !_isWs(s[e]) && s[e] != '<') {
        e++;
      }
      var url = s.substring(i, e);
      while (url.length > schemeLen) {
        final last = url[url.length - 1];
        if ('.,:;!?\'"*_~'.contains(last)) {
          url = url.substring(0, url.length - 1);
        } else if (last == ')' &&
            ')'.allMatches(url).length > '('.allMatches(url).length) {
          url = url.substring(0, url.length - 1);
        } else {
          break;
        }
      }
      if (url.length > schemeLen) {
        _flush();
        toks.add(InlineLink(url: url, children: [InlineText(url)]));
        i += url.length;
        return;
      }
    }
    buf.write('h');
    i++;
  }

  bool _compatible(_Delim o, _Delim c) {
    if (o.char == '~') return o.count == 2 && c.count == 2;
    if ((o.canClose || c.canOpen) &&
        (o.orig + c.orig) % 3 == 0 &&
        !(o.orig % 3 == 0 && c.orig % 3 == 0)) {
      return false;
    }
    return true;
  }

  List<Inline> _flatten(List<Object> items) {
    final out = <Inline>[];
    void add(Inline node) {
      if (node is InlineText && out.isNotEmpty && out.last is InlineText) {
        out[out.length - 1] = InlineText(
          (out.last as InlineText).text + node.text,
        );
      } else {
        out.add(node);
      }
    }

    for (final t in items) {
      if (t is Inline) {
        add(t);
      } else if (t is _Delim && t.count > 0) {
        add(InlineText(t.char * t.count));
      }
    }
    return out;
  }

  List<Inline> _resolve() {
    for (var ci = 0; ci < toks.length; ci++) {
      final c = toks[ci];
      if (c is! _Delim || !c.canClose || c.count == 0) continue;
      var oi = ci - 1;
      while (oi >= 0) {
        final o = toks[oi];
        if (o is _Delim &&
            o.char == c.char &&
            o.canOpen &&
            o.count > 0 &&
            _compatible(o, c)) {
          break;
        }
        oi--;
      }
      if (oi < 0) continue;
      final o = toks[oi] as _Delim;
      final use = c.char == '~' ? 2 : (o.count >= 2 && c.count >= 2 ? 2 : 1);
      final inner = _flatten(toks.sublist(oi + 1, ci));
      final node = c.char == '~'
          ? InlineStrikethrough(inner)
          : use == 2
          ? InlineStrong(inner)
          : InlineEmphasis(inner);
      o.count -= use;
      c.count -= use;
      toks.replaceRange(oi + 1, ci, [node]);
      ci = oi + 1;
    }
    if (streaming) {
      for (var k = toks.length - 1; k >= 0; k--) {
        final t = toks[k];
        if (t is! _Delim || !t.canOpen || t.count == 0) continue;
        if (t.char == '~' && t.count != 2) continue;
        final rest = toks.sublist(k + 1);
        var inner = _flatten(rest);
        if (inner.isEmpty) {
          t.count = 0;
          continue;
        }
        var left = t.count;
        t.count = 0;
        if (t.char == '~') {
          inner = [InlineStrikethrough(inner)];
        } else {
          while (left > 0) {
            final u = left >= 2 ? 2 : 1;
            inner = [u == 2 ? InlineStrong(inner) : InlineEmphasis(inner)];
            left -= u;
          }
        }
        toks.replaceRange(k + 1, toks.length, inner);
      }
    }
    return _flatten(toks);
  }
}
