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
final RegExp _citationRe = RegExp(
  r'\[(\^[A-Za-z0-9_-]{1,32}|\d{1,3}(?:[ \t]*,[ \t]*\d{1,3})*)\]',
);
final RegExp _partialCitationRe = RegExp(
  r'\[(?:\^[A-Za-z0-9_-]{0,32}|\d{1,3}(?:[ \t]*,[ \t]*\d{1,3})*[ \t]*,?[ \t]*)$',
);
final RegExp _wordCharRe = RegExp(r'[\p{L}\p{N}]', unicode: true);
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

bool _isDigit(String ch) {
  final c = ch.codeUnitAt(0);
  return c >= 0x30 && c <= 0x39;
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
    : s = streaming ? _trimPartial(source, options) : source,
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
  static String _trimPartial(String t, MarkdownParserOptions options) {
    var s = t;
    var end = s.length;
    final partial = options.math ? r'*_~$' : '*_~';
    while (end > 0 && partial.contains(s[end - 1])) {
      end--;
    }
    if (end < s.length) s = s.substring(0, end);
    if (s.endsWith('![')) {
      s = s.substring(0, s.length - 2);
    } else if (s.endsWith('[') || s.endsWith('<')) {
      s = s.substring(0, s.length - 1);
    }
    if (options.math && s.endsWith(r'\')) s = s.substring(0, s.length - 1);
    if (options.citations) {
      // Only the last `[` can start a partial marker; checking just that one
      // keeps this O(1) instead of a regex scan of the whole open block.
      var at = s.length - 1;
      final stop = s.length > 40 ? s.length - 40 : 0;
      while (at >= stop && s.codeUnitAt(at) != 0x5B) {
        at--;
      }
      if (at >= stop &&
          _partialCitationRe.matchAsPrefix(s, at) != null &&
          !(at > 0 && s[at - 1] == r'\') &&
          (s.startsWith('[^', at) || !_gluedBefore(s, at))) {
        s = s.substring(0, at);
      }
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
        case r'$' when options.math:
          _dollar();
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
      if (options.math && nx == '(' && _texParen()) return;
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

  void _math(String tex, {required bool display, bool isOpen = false}) {
    _flush();
    toks.add(InlineMath(tex, display: display, isOpen: isOpen));
  }

  /// The position from which no `\)` follows, once a search has found none;
  /// later openers past it skip the scan, so many unclosed `\(` stay linear.
  int _noParenCloseFrom = -1;

  /// `\(…\)` at [i]; returns whether it was consumed as math.
  ///
  /// Display math written as `\[…\]` is only recognised as a block (on its
  /// own lines); inline, `\[` stays an escaped bracket.
  bool _texParen() {
    final from = i + 2;
    if (_noParenCloseFrom >= 0 && from >= _noParenCloseFrom) return false;
    final close = s.indexOf(r'\)', from);
    if (close < 0) {
      _noParenCloseFrom = from;
      return false;
    }
    final tex = s.substring(from, close).trim();
    if (tex.isEmpty) return false;
    _math(tex, display: false);
    i = close + 2;
    return true;
  }

  /// `$…$` or `$$…$$` at [i].
  ///
  /// Without a closing delimiter the dollar stays text, also while
  /// streaming: `$HOME` or `echo $$` must not flash as math. The one
  /// exception is `$\`, which is unambiguous TeX (`$\frac{a}{`), shown as
  /// open math while streaming.
  void _dollar() {
    if (i + 1 < n && s[i + 1] == r'$') {
      final close = _findDollars(i + 2);
      final tex = close < 0 ? '' : s.substring(i + 2, close).trim();
      if (tex.isNotEmpty) {
        _math(tex, display: true);
        i = close + 2;
      } else {
        buf.write(r'$$');
        i += 2;
      }
      return;
    }
    final next = i + 1 < n ? s[i + 1] : ' ';
    final close = _isWs(next) ? -1 : _findDollar(i + 1);
    if (close >= 0) {
      _math(s.substring(i + 1, close), display: false);
      i = close + 1;
    } else if (streaming && close == -1 && next == r'\') {
      _math(s.substring(i + 1).trim(), display: false, isOpen: true);
      i = n;
    } else {
      buf.write(r'$');
      i++;
    }
  }

  /// Index of the next `$$` at or after [from] (skipping TeX escapes such
  /// as `\$`), or -1.
  int _findDollars(int from) {
    for (var p = from; p < n - 1; p++) {
      if (s[p] == r'\') {
        p++;
      } else if (s[p] == r'$' && s[p + 1] == r'$') {
        return p;
      }
    }
    return -1;
  }

  /// Index of the `$` closing inline math whose content starts at [from].
  ///
  /// Returns -1 when there is none, and -2 when a `$` that cannot close is
  /// found first: then the opening `$` is most likely a price
  /// (`$5 and $10`), so it is not treated as math even while streaming.
  int _findDollar(int from) {
    for (var p = from; p < n; p++) {
      final c = s[p];
      if (c == r'\') {
        p++;
      } else if (c == r'$') {
        final closes =
            p > from && !_isWs(s[p - 1]) && (p + 1 >= n || !_isDigit(s[p + 1]));
        return closes ? p : -2;
      }
    }
    return -1;
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

  /// Where the last citation ended, so `[1][2]` is two citations while
  /// `m[i][0]` is none.
  int _citationEnd = -1;

  /// Whether the text before [at] makes a `[` index something (`array[1]`,
  /// `split()[0]`, `数组[1]`) rather than start a citation.
  static bool _gluedBefore(String s, int at) {
    if (at == 0) return false;
    final prev = s[at - 1];
    return prev == ']' || prev == ')' || _wordCharRe.hasMatch(prev);
  }

  /// A citation such as `[1]`, `[1, 2]` or `[^note]` at [i]; returns
  /// whether it was consumed.
  bool _citation() {
    final m = _citationRe.matchAsPrefix(s, i);
    if (m == null) return false;
    final body = m[1]!;
    final footnote = body.startsWith('^');
    if (!footnote && i != _citationEnd && _gluedBefore(s, i)) return false;
    if (m.end < n && (s[m.end] == '(' || s[m.end] == ':')) return false;
    // While streaming, the next character may still be `(` or `:`.
    if (streaming && m.end == n) return false;
    final labels = footnote
        ? [body.substring(1)]
        : [for (final l in body.split(',')) l.trim()];
    if (labels.contains('0')) return false; // `[0, 1]` is a range
    _flush();
    toks.add(InlineCitation(labels, source: m[0]));
    i = _citationEnd = m.end;
    return true;
  }

  void _bracket({required bool image}) {
    if (!image && options.citations && _citation()) return;
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
          case InlineMath(:final tex):
            b.write(tex);
          case InlineCitation(:final source):
            b.write(source);
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
