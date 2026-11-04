import 'dart:collection';
import 'dart:math' as math;

import '../ast/block.dart';
import '../ast/document.dart';
import '../ast/inline.dart';
import 'inline_parser.dart';
import 'line_buffer.dart';
import 'options.dart';

final RegExp _fenceRe = RegExp(r'^( {0,3})(`{3,}|~{3,})[ \t]*(.*?)[ \t]*$');
final RegExp _fenceCloseRe = RegExp(r'^ {0,3}(`{3,}|~{3,})[ \t]*$');
final RegExp _atxRe = RegExp(r'^ {0,3}(#{1,6})(?:[ \t]+(.*?))?[ \t]*$');
final RegExp _atxCloseRe = RegExp(r'(^|[ \t]+)#+[ \t]*$');
final RegExp _hrRe = RegExp(r'^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$');
final RegExp _quoteRe = RegExp(r'^ {0,3}> ?(.*)$');
final RegExp _listRe = RegExp(r'^( *)(?:([-+*])|(\d{1,9})([.)]))( +|$)(.*)$');
final RegExp _setextRe = RegExp(r'^ {0,3}(=+|-+)[ \t]*$');
final RegExp _delimRe = RegExp(
  r'^ {0,3}\|?[ \t]*:?-+:?[ \t]*(?:\|[ \t]*:?-+:?[ \t]*)*\|?[ \t]*$',
);
final RegExp _taskRe = RegExp(r'^\[([ xX])\](?:[ \t]+|$)');
final RegExp _hideShortRe = RegExp(
  r'^(?:#{1,6}|[-*+_=~`|:>]{1,2}|\d{1,9}[.)]|\$\$?|\\\[?)$',
);
final RegExp _mathOpenRe = RegExp(r'^ {0,3}(\$\$(?!\$)|\\\[)(.*)$');
final RegExp _hideMathCloseRe = RegExp(r'^\s*(?:\$\$?|\\\]?)\s*$');
final RegExp _thinkOpenRe = RegExp(
  r'^ {0,3}<(think|thinking)>',
  caseSensitive: false,
);
final RegExp _hideDashesRe = RegExp(r'^[|\-:=\s]+$');
final RegExp _hideFenceRe = RegExp(r'^ {0,3}[`~]+$');
final RegExp _leadingMarkersRe = RegExp(r'^[ \t>]+');

class _Counters {
  int inlineParses = 0;
}

sealed class _Open {
  _Open(this.id);
  final int id;
  _Open clone();
}

class _ParaOpen extends _Open {
  _ParaOpen(super.id, this.lines);
  final List<String> lines;
  @override
  _ParaOpen clone() => _ParaOpen(id, List.of(lines));
}

class _FenceOpen extends _Open {
  _FenceOpen(super.id, this.char, this.len, this.indent, this.info)
    : lines = [];
  _FenceOpen._(
    super.id,
    this.char,
    this.len,
    this.indent,
    this.info,
    this.lines,
  );
  final String char;
  final int len;
  final int indent;
  final String info;
  final List<String> lines;
  @override
  _FenceOpen clone() =>
      _FenceOpen._(id, char, len, indent, info, List.of(lines));
}

class _CodeOpen extends _Open {
  _CodeOpen(super.id, this.lines);
  final List<String> lines;
  @override
  _CodeOpen clone() => _CodeOpen(id, List.of(lines));
}

class _MathOpen extends _Open {
  _MathOpen(super.id, this.closer, this.openLine, this.lines);
  final String closer;
  final String openLine;
  final List<String> lines;
  @override
  _MathOpen clone() => _MathOpen(id, closer, openLine, List.of(lines));
}

/// A `<think>` section. Unlike quotes, its content is parsed by a child
/// engine that lives as long as the section, so each append costs the same
/// however long the model has been thinking, and finished blocks inside it
/// keep their identity.
class _ThinkOpen extends _Open {
  _ThinkOpen(super.id, this.tag, this.child);
  final String tag;
  final _Engine child;

  late final String closeTag = '</$tag>';
  late final RegExp _closeStartRe = RegExp(
    '^\\s*${RegExp.escape(closeTag)}',
    caseSensitive: false,
  );
  late final RegExp _closeEndRe = RegExp(
    '${RegExp.escape(closeTag)}\\s*\$',
    caseSensitive: false,
  );

  /// The closing tag on [line], if it starts or ends the line (`</think>`,
  /// `…done.</think>`, `</think> The answer`) and the section is not inside
  /// a code block, where `</think>` is just code.
  Match? closeIn(String line) {
    final c = child.open;
    if (c is _FenceOpen || (c is _ListOpen && c.cur.inFence)) return null;
    if (c is _CodeOpen && _indentOf(line) >= 4) return null;
    return _closeStartRe.firstMatch(line) ?? _closeEndRe.firstMatch(line);
  }

  @override
  _ThinkOpen clone() => _ThinkOpen(id, tag, _Engine._preview(child));
}

class _QuoteOpen extends _Open {
  _QuoteOpen(super.id, this.lines, this.lastBlank);
  final List<String> lines;
  bool lastBlank;
  @override
  _QuoteOpen clone() => _QuoteOpen(id, List.of(lines), lastBlank);
}

class _ItemBuf {
  _ItemBuf(
    this.id,
    this.markerIndent,
    this.contentIndent,
    this.lines, {
    this.fenceChar,
    this.fenceLen = 0,
  });
  final int id;
  final int markerIndent;
  final int contentIndent;
  final List<String> lines;
  String? fenceChar;
  int fenceLen;

  bool get inFence => fenceChar != null;

  void add(String line) {
    lines.add(line);
    if (inFence) {
      final m = _fenceCloseRe.firstMatch(line);
      if (m != null && m[1]![0] == fenceChar && m[1]!.length >= fenceLen) {
        fenceChar = null;
        fenceLen = 0;
      }
    } else {
      final m = _openFence(line);
      if (m != null) {
        fenceChar = m[2]![0];
        fenceLen = m[2]!.length;
      }
    }
  }

  _ItemBuf clone() => _ItemBuf(
    id,
    markerIndent,
    contentIndent,
    List.of(lines),
    fenceChar: fenceChar,
    fenceLen: fenceLen,
  );
}

class _ListOpen extends _Open {
  _ListOpen(
    super.id,
    this.ordered,
    this.delim,
    this.start,
    this.items,
    this.cur,
    this.nextItem,
    this.blankSeen,
  );
  final bool ordered;
  final String delim;
  final int start;
  final List<ListItem> items;
  _ItemBuf cur;
  int nextItem;
  bool blankSeen;
  @override
  _ListOpen clone() => _ListOpen(
    id,
    ordered,
    delim,
    start,
    List.of(items),
    cur.clone(),
    nextItem,
    blankSeen,
  );
}

class _TableOpen extends _Open {
  _TableOpen(super.id, this.alignments, this.header, this.rows);
  final List<TableAlignment> alignments;
  final List<List<Inline>> header;
  final List<List<List<Inline>>> rows;
  @override
  _TableOpen clone() => _TableOpen(id, alignments, header, List.of(rows));
}

Match? _openFence(String line) {
  final m = _fenceRe.firstMatch(line);
  if (m == null) return null;
  if (m[2]!.startsWith('`') && m[3]!.contains('`')) return null;
  return m;
}

/// The start of a display math block on [line]: its closing delimiter and,
/// for a one-line block (`$$E=mc^2$$`), its TeX.
///
/// A block opens only on a line that is just `$$` or `\[`, or that is one
/// complete non-empty block. Anything else (`$$ is the PID`, `\[1\] Smith`,
/// `$$a$$ and text`) is a paragraph, so prose cannot open a block that would
/// swallow the text after it.
({String closer, String? tex})? _mathStart(String line) {
  final m = _mathOpenRe.firstMatch(line);
  if (m == null) return null;
  final closer = m[1] == r'$$' ? r'$$' : r'\]';
  final rest = m[2]!.trim();
  if (rest.isEmpty) return (closer: closer, tex: null);
  final at = rest.indexOf(closer);
  if (at < 0 || at + closer.length != rest.length || _escaped(rest, at)) {
    return null;
  }
  final tex = rest.substring(0, at).trim();
  return tex.isEmpty ? null : (closer: closer, tex: tex);
}

/// Whether the character at [at] is preceded by an odd number of
/// backslashes (so `\$$` or `\\]` is not a closing delimiter).
bool _escaped(String s, int at) {
  var k = at;
  while (k > 0 && s.codeUnitAt(k - 1) == 0x5C) {
    k--;
  }
  return (at - k).isOdd;
}

/// The TeX of an open math block. While streaming, a trailing `$` or `\`
/// is probably the start of the closing delimiter and is left out.
String _mathTex(_MathOpen o, {required bool streaming}) {
  var tex = o.lines.join('\n').trimRight();
  if (streaming) {
    final partial = o.closer == r'$$' ? r'$' : r'\';
    if (tex.endsWith(partial) && !tex.endsWith(r'\\')) {
      tex = tex.substring(0, tex.length - 1);
    }
  }
  return tex.trim();
}

int _indentOf(String line) {
  var i = 0;
  while (i < line.length && line.codeUnitAt(i) == 0x20) {
    i++;
  }
  return i;
}

String _stripIndent(String line, int max) {
  final n = math.min(_indentOf(line), max);
  return n == 0 ? line : line.substring(n);
}

String _expandTabs(String line) {
  if (!line.contains('\t')) return line;
  final b = StringBuffer();
  var col = 0;
  var i = 0;
  for (; i < line.length; i++) {
    final c = line[i];
    if (c == ' ') {
      b.write(' ');
      col++;
    } else if (c == '\t') {
      final w = 4 - (col % 4);
      b.write(' ' * w);
      col += w;
    } else {
      break;
    }
  }
  b.write(line.substring(i));
  return b.toString();
}

String? _languageOf(String info) {
  var first = info.trim().split(RegExp(r'\s+')).first;
  if (first.startsWith('{')) first = first.substring(1);
  if (first.startsWith('.')) first = first.substring(1);
  first = first.replaceAll(RegExp(r'[{}]'), '');
  return first.isEmpty ? null : first;
}

List<String> _splitRow(String line) {
  var t = line.trim();
  if (t.startsWith('|')) t = t.substring(1);
  if (t.endsWith('|') && !t.endsWith(r'\|')) t = t.substring(0, t.length - 1);
  final cells = <String>[];
  final cur = StringBuffer();
  for (var i = 0; i < t.length; i++) {
    final c = t[i];
    if (c == r'\' && i + 1 < t.length && t[i + 1] == '|') {
      cur.write('|');
      i++;
    } else if (c == '|') {
      cells.add(cur.toString().trim());
      cur.clear();
    } else {
      cur.write(c);
    }
  }
  cells.add(cur.toString().trim());
  return cells;
}

/// Line-oriented block state machine.
///
/// Holds the committed blocks plus at most one open block. Nested containers
/// (list items, block quotes) are parsed by running a child engine over the
/// container's de-indented lines.
class _Engine {
  _Engine(this.options, this.counters, {this.parentId, this.isPreview = false});

  _Engine._preview(_Engine base)
    : options = base.options,
      counters = base.counters,
      parentId = base.parentId,
      isPreview = true,
      seq = base.seq,
      open = base.open?.clone(),
      inherited = base.committed;

  final MarkdownParserOptions options;
  final _Counters counters;
  final int? parentId;

  /// Whether this engine renders speculative output of a still-growing line.
  final bool isPreview;

  final List<Block> committed = [];

  /// For the preview of a thinking section's child engine: the real engine's
  /// committed blocks, shared rather than copied; [committed] then only holds
  /// what the preview adds.
  List<Block> inherited = const [];
  _Open? open;
  int seq = 0;

  /// Reasoning models emit `<think>` only at the very start of a reply, so a
  /// section can only open before anything else (at the top level). A
  /// sentence that merely starts with the tag later on stays text.
  bool get _thinkingAllowed => options.thinking && parentId == null && seq == 0;

  int _newId() {
    final k = seq++;
    return parentId == null ? k : parentId! * 31 + k;
  }

  List<Inline> _inl(String text, bool streaming) {
    counters.inlineParses++;
    return parseInlines(text, streaming: streaming, options: options);
  }

  // -------------------------------------------------------------------------
  // Line processing
  // -------------------------------------------------------------------------

  void feed(String raw) {
    final line = _expandTabs(raw);
    final o = open;
    if (o == null) {
      _start(line);
      return;
    }
    switch (o) {
      case final _FenceOpen f:
        final m = _fenceCloseRe.firstMatch(line);
        if (m != null && m[1]![0] == f.char && m[1]!.length >= f.len) {
          _closeOpen();
        } else {
          f.lines.add(_stripIndent(line, f.indent));
        }
      case final _ThinkOpen th:
        final close = th.closeIn(line);
        if (close == null) {
          th.child.feed(line);
        } else {
          final before = line.substring(0, close.start).trimRight();
          if (before.trim().isNotEmpty) th.child.feed(before);
          _closeOpen();
          final after = line.substring(close.end).trimLeft();
          if (after.isNotEmpty) _start(after);
        }
      case final _MathOpen m:
        final t = line.trim();
        final end = t.length - m.closer.length;
        if (t.isEmpty) {
          // TeX display math cannot contain a blank line: this was not math.
          _abandonMath(m);
          feed(line);
        } else if (t.endsWith(m.closer) && !_escaped(t, end)) {
          final before = t.substring(0, end);
          if (before.trim().isNotEmpty) m.lines.add(before);
          _closeOpen();
        } else if (t.startsWith(m.closer)) {
          _closeOpen();
          _start(t.substring(m.closer.length).trimLeft());
        } else {
          m.lines.add(line);
        }
      case final _CodeOpen c:
        if (line.trim().isEmpty) {
          c.lines.add(line.length >= 4 ? line.substring(4) : '');
        } else if (_indentOf(line) >= 4) {
          c.lines.add(line.substring(4));
        } else {
          _closeOpen();
          _start(line);
        }
      case final _ParaOpen p:
        _feedParagraph(p, line);
      case final _QuoteOpen q:
        _feedQuote(q, line);
      case final _ListOpen l:
        _feedList(l, line);
      case final _TableOpen t:
        if (line.trim().isEmpty || !line.contains('|')) {
          _closeOpen();
          _start(line);
        } else {
          t.rows.add(_cells(line, t.alignments.length, streaming: isPreview));
        }
    }
  }

  void _start(String line) {
    if (line.trim().isEmpty) return;
    if (_indentOf(line) >= 4) {
      open = _CodeOpen(_newId(), [line.substring(4)]);
      return;
    }
    final fm = _openFence(line);
    if (fm != null) {
      open = _FenceOpen(
        _newId(),
        fm[2]![0],
        fm[2]!.length,
        fm[1]!.length,
        fm[3]!,
      );
      return;
    }
    final tm = _thinkingAllowed ? _thinkOpenRe.firstMatch(line) : null;
    if (tm != null) {
      final id = _newId();
      open = _ThinkOpen(
        id,
        tm[1]!.toLowerCase(),
        _Engine(options, counters, parentId: id, isPreview: isPreview),
      );
      final rest = line.substring(tm.end).trimLeft();
      if (rest.isNotEmpty) feed(rest);
      return;
    }
    final mm = options.math ? _mathStart(line) : null;
    if (mm != null) {
      final tex = mm.tex;
      if (tex != null) {
        committed.add(MathBlock(id: _newId(), isOpen: isPreview, tex: tex));
      } else {
        open = _MathOpen(_newId(), mm.closer, line, []);
      }
      return;
    }
    final am = _atxRe.firstMatch(line);
    if (am != null) {
      final content = (am[2] ?? '').replaceFirst(_atxCloseRe, '').trim();
      committed.add(
        HeadingBlock(
          id: _newId(),
          isOpen: isPreview,
          level: am[1]!.length,
          children: _inl(content, isPreview),
        ),
      );
      return;
    }
    if (_hrRe.hasMatch(line)) {
      committed.add(ThematicBreakBlock(id: _newId()));
      return;
    }
    final qm = _quoteRe.firstMatch(line);
    if (qm != null) {
      open = _QuoteOpen(_newId(), [qm[1]!], qm[1]!.trim().isEmpty);
      return;
    }
    final lm = _listRe.firstMatch(line);
    if (lm != null) {
      final id = _newId();
      final ordered = lm[2] == null;
      open = _ListOpen(
        id,
        ordered,
        ordered ? lm[4]! : lm[2]!,
        ordered ? int.parse(lm[3]!) : 1,
        [],
        _newItem(id, 0, lm),
        1,
        false,
      );
      return;
    }
    open = _ParaOpen(_newId(), [line.trimLeft()]);
  }

  bool _isBlockStart(String line) {
    if (_indentOf(line) >= 4) return false;
    if (_openFence(line) != null) return true;
    if (options.math && _mathStart(line) != null) return true;
    if (_atxRe.hasMatch(line) ||
        _hrRe.hasMatch(line) ||
        _quoteRe.hasMatch(line)) {
      return true;
    }
    final lm = _listRe.firstMatch(line);
    if (lm != null && lm[6]!.isNotEmpty) {
      return lm[2] != null || lm[3] == '1';
    }
    return false;
  }

  void _feedParagraph(_ParaOpen p, String line) {
    if (line.trim().isEmpty) {
      _closeOpen();
      return;
    }
    final sm = _setextRe.firstMatch(line);
    if (sm != null) {
      open = null;
      committed.add(
        HeadingBlock(
          id: p.id,
          isOpen: false,
          level: sm[1]!.startsWith('=') ? 1 : 2,
          children: _inl(p.lines.join('\n').trimRight(), false),
        ),
      );
      return;
    }
    if (options.tables && line.contains('|') && _delimRe.hasMatch(line)) {
      final headerLine = p.lines.last;
      if (headerLine.contains('|')) {
        final header = _splitRow(headerLine);
        final delim = _splitRow(line);
        if (header.length == delim.length) {
          final before = p.lines.sublist(0, p.lines.length - 1);
          open = null;
          var id = p.id;
          if (before.isNotEmpty) {
            committed.add(_para(p.id, before, false));
            id = _newId();
          }
          open = _TableOpen(
            id,
            [for (final d in delim) _alignmentOf(d)],
            _cells(headerLine, delim.length, streaming: false),
            [],
          );
          return;
        }
      }
    }
    if (_isBlockStart(line)) {
      _closeOpen();
      _start(line);
      return;
    }
    p.lines.add(line.trimLeft());
  }

  static TableAlignment _alignmentOf(String cell) {
    final l = cell.startsWith(':');
    final r = cell.endsWith(':');
    if (l && r) return TableAlignment.center;
    if (r) return TableAlignment.right;
    if (l) return TableAlignment.left;
    return TableAlignment.none;
  }

  List<List<Inline>> _cells(String line, int cols, {required bool streaming}) {
    final raw = _splitRow(line);
    return [
      for (var i = 0; i < cols; i++)
        i < raw.length ? _inl(raw[i], streaming) : const <Inline>[],
    ];
  }

  void _feedQuote(_QuoteOpen q, String line) {
    final m = _quoteRe.firstMatch(line);
    if (m != null) {
      q.lines.add(m[1]!);
      q.lastBlank = m[1]!.trim().isEmpty;
    } else if (line.trim().isEmpty) {
      _closeOpen();
    } else if (!q.lastBlank && !_isBlockStart(line)) {
      q.lines.add(line.trimLeft());
    } else {
      _closeOpen();
      _start(line);
    }
  }

  _ItemBuf _newItem(int listId, int index, Match lm) {
    final mi = lm[1]!.length;
    final marker = lm[2] ?? '${lm[3]}${lm[4]}';
    final spaces = lm[5]!.length;
    final rest = lm[6]!;
    final pad = rest.isEmpty ? 1 : (spaces > 4 ? 1 : spaces);
    final first = spaces > 4 && rest.isNotEmpty
        ? '${' ' * (spaces - 1)}$rest'
        : rest;
    final buf = _ItemBuf(listId * 31 + index, mi, mi + marker.length + pad, []);
    buf.add(first);
    return buf;
  }

  void _feedList(_ListOpen l, String line) {
    final cur = l.cur;
    if (line.trim().isEmpty) {
      cur.lines.add('');
      l.blankSeen = true;
      return;
    }
    final indent = _indentOf(line);
    final lm = _listRe.firstMatch(line);
    final isMarker = lm != null && !cur.inFence && !_hrRe.hasMatch(line);
    if (isMarker &&
        indent < cur.markerIndent + 2 &&
        indent < cur.contentIndent) {
      final sameKind = l.ordered
          ? lm[2] == null && lm[4] == l.delim
          : lm[2] == l.delim;
      if (sameKind) {
        l.items.add(_buildItem(l.cur, streaming: false, moreFollows: true));
        l.cur = _newItem(l.id, l.nextItem++, lm);
        l.blankSeen = false;
      } else {
        _closeOpen();
        _start(line);
      }
      return;
    }
    if (indent >= cur.contentIndent ||
        (isMarker && indent >= cur.markerIndent + 2)) {
      cur.add(_stripIndent(line, cur.contentIndent));
      l.blankSeen = false;
      return;
    }
    if (!cur.inFence && !l.blankSeen && !_isBlockStart(line)) {
      cur.add(line.trimLeft());
      return;
    }
    _closeOpen();
    _start(line);
  }

  // -------------------------------------------------------------------------
  // Snapshots
  // -------------------------------------------------------------------------

  ParagraphBlock _para(int id, List<String> lines, bool streaming) =>
      ParagraphBlock(
        id: id,
        isOpen: streaming,
        children: _inl(lines.join('\n').trimRight(), streaming),
      );

  ListItem _buildItem(
    _ItemBuf b, {
    required bool streaming,
    required bool moreFollows,
  }) {
    final lines = List<String>.of(b.lines);
    var trailing = 0;
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
      trailing++;
    }
    bool? checked;
    if (options.taskLists && lines.isNotEmpty) {
      final m = _taskRe.firstMatch(lines[0]);
      if (m != null) {
        checked = m[1] != ' ';
        lines[0] = lines[0].substring(m.end);
      }
    }
    final internalBlank = lines.any((x) => x.trim().isEmpty);
    return ListItem(
      id: b.id,
      isOpen: streaming,
      checked: checked,
      isLoose: internalBlank || (moreFollows && trailing > 0),
      children: _nested(b.id, lines, streaming),
    );
  }

  List<Block> _nested(int parent, List<String> lines, bool streaming) {
    final e = _Engine(
      options,
      counters,
      parentId: parent,
      isPreview: streaming,
    );
    for (final l in lines) {
      e.feed(l);
    }
    if (streaming) {
      final o = e.open;
      return [...e.committed, if (o != null) e._snap(o, streaming: true)];
    }
    e.finish();
    return e.committed;
  }

  Block _snap(_Open o, {required bool streaming}) {
    switch (o) {
      case final _ParaOpen p:
        return _para(p.id, p.lines, streaming);
      case final _FenceOpen f:
        return CodeBlock(
          id: f.id,
          isOpen: streaming,
          lines: List.unmodifiable(f.lines),
          info: f.info,
          language: _languageOf(f.info),
        );
      case final _ThinkOpen th:
        final c = th.child;
        if (!streaming) c.finish();
        final co = c.open;
        return ThinkingBlock(
          id: th.id,
          isOpen: streaming,
          children: UnmodifiableListView([
            ...c.inherited,
            ...c.committed,
            if (streaming && co != null) c._snap(co, streaming: true),
          ]),
        );
      case final _MathOpen m:
        return MathBlock(
          id: m.id,
          isOpen: streaming,
          tex: _mathTex(m, streaming: streaming),
        );
      case final _CodeOpen c:
        final lines = List<String>.of(c.lines);
        while (lines.isNotEmpty && lines.last.trim().isEmpty) {
          lines.removeLast();
        }
        return CodeBlock(
          id: c.id,
          isOpen: streaming,
          lines: List.unmodifiable(lines),
          isFenced: false,
        );
      case final _QuoteOpen q:
        return BlockQuoteBlock(
          id: q.id,
          isOpen: streaming,
          children: _nested(q.id, q.lines, streaming),
        );
      case final _ListOpen l:
        return ListBlock(
          id: l.id,
          isOpen: streaming,
          ordered: l.ordered,
          start: l.start,
          items: [
            ...l.items,
            _buildItem(l.cur, streaming: streaming, moreFollows: false),
          ],
        );
      case final _TableOpen t:
        return TableBlock(
          id: t.id,
          isOpen: streaming,
          alignments: t.alignments,
          header: t.header,
          rows: List.of(t.rows),
        );
    }
  }

  void _closeOpen() {
    final o = open;
    if (o == null) return;
    open = null;
    committed.add(_snap(o, streaming: false));
  }

  /// Re-reads an unclosed math block as ordinary text, starting with a
  /// paragraph holding its opening line. Only the open block is replayed,
  /// so this stays cheap.
  void _abandonMath(_MathOpen m) {
    open = _ParaOpen(m.id, [m.openLine.trimLeft()]);
    m.lines.forEach(feed);
  }

  void finish() {
    // Replaying can open another (shorter) unclosed block; repeat until none.
    for (var o = open; o is _MathOpen; o = open) {
      _abandonMath(o);
    }
    _closeOpen();
  }

  // -------------------------------------------------------------------------
  // Streaming tail
  // -------------------------------------------------------------------------

  bool _hidePending(String pending) {
    final o = open;
    if (o is _FenceOpen) return _hideFenceRe.hasMatch(pending);
    if (o is _MathOpen) return _hideMathCloseRe.hasMatch(pending);
    if (o is _ThinkOpen) {
      return _isTagPrefix(pending, '</${o.tag}>') ||
          o.child._hidePending(pending);
    }
    if (_thinkingAllowed &&
        (_isTagPrefix(pending, '<think>') ||
            _isTagPrefix(pending, '<thinking>'))) {
      return true;
    }
    final s = pending.replaceFirst(_leadingMarkersRe, '');
    if (s.isEmpty) return true;
    if (_hideShortRe.hasMatch(s)) return true;
    return (o is _ParaOpen || o is _TableOpen || s.contains('|')) &&
        _hideDashesRe.hasMatch(s);
  }

  /// [pending] without a trailing start of [tag] (`done.</thi`), so the
  /// partial tag is not painted as text for a few frames. Only the last few
  /// characters are looked at.
  static String _withoutPartialTag(String pending, String tag) {
    final lower = pending.length > tag.length
        ? pending.substring(pending.length - tag.length).toLowerCase()
        : pending.toLowerCase();
    for (var k = 2; k < tag.length && k <= lower.length; k++) {
      if (tag.startsWith(lower.substring(lower.length - k))) {
        return pending.substring(0, pending.length - k);
      }
    }
    return pending;
  }

  /// Whether [pending] is the start of [tag] (`<thi` for `<think>`), which
  /// would be painted as text for a few frames otherwise.
  static bool _isTagPrefix(String pending, String tag) {
    if (pending.length > tag.length + 8) return false;
    final p = pending.trim().toLowerCase();
    return p.isNotEmpty && p.length < tag.length && tag.startsWith(p);
  }

  /// The not-yet-committed blocks, including a speculative rendering of the
  /// unterminated [pending] line.
  List<Block> tail(String pending) {
    final o0 = open;
    if (o0 is _ThinkOpen) pending = _withoutPartialTag(pending, o0.closeTag);
    if (pending.trim().isEmpty || _hidePending(pending)) {
      final o = open;
      return [if (o != null) _snap(o, streaming: true)];
    }
    final e = _Engine._preview(this)..feed(pending);
    final o = e.open;
    return [...e.committed, if (o != null) e._snap(o, streaming: true)];
  }
}

/// Parses Markdown incrementally, as it is streamed in chunks.
///
/// Feed text with [append] in chunks of any size (even one character, or
/// splitting a code fence, a `\r\n` or a surrogate pair) and read the current
/// [document] at any time. Each [append] does work proportional to the new
/// text plus the single still-open block; blocks that have been closed are
/// never parsed again and keep their object identity across snapshots.
///
/// The parser imports nothing from Flutter, so it can run in isolates, tests
/// and Dart scripts.
///
/// ```dart
/// final parser = IncrementalMarkdownParser();
/// parser.append('# Hi\n\nSome **bo');
/// print(parser.document.blocks); // [Heading1, Paragraph(open)]
/// parser.complete();
/// ```
///
/// The guarantee tested for this class: for every way of splitting an input
/// into chunks, [document] after the last chunk equals the document produced
/// by appending the whole input at once.
class IncrementalMarkdownParser {
  /// Creates a parser with the given [options].
  IncrementalMarkdownParser({this.options = const MarkdownParserOptions()}) {
    _engine = _Engine(options, _counters);
  }

  /// Parses a complete [markdown] string in one go.
  static MarkdownDocument parse(
    String markdown, {
    MarkdownParserOptions options = const MarkdownParserOptions(),
  }) {
    final p = IncrementalMarkdownParser(options: options)
      ..append(markdown)
      ..complete();
    return p.document;
  }

  /// The parser options in effect.
  final MarkdownParserOptions options;

  final _Counters _counters = _Counters();
  late _Engine _engine;
  LineBuffer _lines = LineBuffer();
  MarkdownDocument? _doc;
  bool _complete = false;

  /// Whether [complete] has been called.
  bool get isComplete => _complete;

  /// How many times inline content has been parsed so far.
  ///
  /// Intended for tests and diagnostics: it grows with the amount of
  /// *open* content per [append], not with the size of the document.
  int get debugInlineParseCount => _counters.inlineParses;

  /// Appends [chunk] of Markdown.
  ///
  /// Throws a [StateError] if the parser is already [isComplete].
  void append(String chunk) {
    if (_complete) {
      throw StateError('append() called after complete(); call reset() first.');
    }
    if (chunk.isEmpty) return;
    for (final line in _lines.add(chunk)) {
      _engine.feed(line);
    }
    _doc = null;
  }

  /// Marks the input as finished: the last line is processed and every open
  /// block is closed (an unterminated code fence simply ends).
  void complete() {
    if (_complete) return;
    final rest = _lines.flush();
    if (rest != null) _engine.feed(rest);
    _engine.finish();
    _complete = true;
    _doc = null;
  }

  /// Discards all state so the parser can be reused for a new document.
  void reset() {
    _counters.inlineParses = 0;
    _engine = _Engine(options, _counters);
    _lines = LineBuffer();
    _complete = false;
    _doc = null;
  }

  /// The current snapshot of the document.
  ///
  /// The snapshot is cached until the next [append]/[complete]/[reset].
  MarkdownDocument get document => _doc ??= _build();

  MarkdownDocument _build() {
    if (_complete) {
      return MarkdownDocument(_engine.committed, isComplete: true);
    }
    return MarkdownDocument([
      ..._engine.committed,
      ..._engine.tail(_lines.pending),
    ], isComplete: false);
  }
}
