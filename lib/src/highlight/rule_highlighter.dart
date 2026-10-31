import 'highlighter.dart';
import 'languages.dart';

/// One lexing rule: when [pattern] matches at the current position, the match
/// becomes a token of [kind] and lexing continues in state [next] (or stays in
/// the current state when `null`).
final class LexRule {
  /// Creates a rule.
  LexRule(String pattern, this.kind, {this.next, bool caseSensitive = true})
    : regExp = RegExp(pattern, caseSensitive: caseSensitive);

  /// The compiled pattern; it is matched anchored at the current position.
  final RegExp regExp;

  /// The category of the produced token.
  final TokenKind kind;

  /// The state to switch to after a match, or `null` to stay.
  final String? next;
}

/// A language described as a set of named lexer states.
///
/// Every state is an ordered list of [LexRule]s; the first rule that matches at
/// the current position wins. The state named `root` is the initial state.
/// Multi-line constructs (block comments, triple-quoted strings) are modelled
/// by rules that switch to another state and back.
final class LanguageDefinition {
  /// Creates a language definition.
  const LanguageDefinition({
    required this.name,
    required this.states,
    this.aliases = const [],
  });

  /// The canonical, lower-case name, e.g. `dart`.
  final String name;

  /// Other names that select this language, e.g. `js` for `javascript`.
  final List<String> aliases;

  /// The lexer states, keyed by name. Must contain `root`.
  final Map<String, List<LexRule>> states;
}

/// A [CodeHighlighter] driven by small regular-expression lexers.
///
/// Built-in languages: Dart, JavaScript/TypeScript (`js`, `jsx`, `ts`, `tsx`),
/// JSON, Python (`py`), Bash (`sh`, `shell`, `zsh`), YAML (`yml`), SQL, HTML and
/// XML (`xml`, `svg`), CSS, C, C++, Java, Kotlin, Swift, Go, Rust, C# (`cs`)
/// and diffs (`diff`, `patch`). Pass [extraLanguages] to add or override
/// languages.
final class RuleBasedHighlighter implements CodeHighlighter {
  /// Creates a highlighter with the built-in languages plus [extraLanguages].
  const RuleBasedHighlighter({this.extraLanguages = const []});

  /// Languages added to (or overriding) the built-in set.
  final List<LanguageDefinition> extraLanguages;

  static Map<String, LanguageDefinition>? _builtIn;

  static Map<String, LanguageDefinition> _index(
    Iterable<LanguageDefinition> defs,
  ) {
    final map = <String, LanguageDefinition>{};
    for (final d in defs) {
      map[d.name] = d;
      for (final a in d.aliases) {
        map[a] = d;
      }
    }
    return map;
  }

  /// Looks up a language by name or alias (case-insensitive).
  LanguageDefinition? languageFor(String? language) {
    if (language == null) return null;
    final key = language.toLowerCase();
    for (final d in extraLanguages.reversed) {
      if (d.name == key || d.aliases.contains(key)) return d;
    }
    return (_builtIn ??= _index(builtInLanguages))[key];
  }

  @override
  LineHighlight highlightLine(String? language, String line, Object? state) {
    final def = languageFor(language);
    if (def == null || line.isEmpty) return LineHighlight(const [], state);
    var current = state is String && def.states.containsKey(state)
        ? state
        : 'root';
    final tokens = <Token>[];
    var pos = 0;

    void add(TokenKind kind, int start, int end) {
      if (tokens.isNotEmpty) {
        final last = tokens.last;
        if (last.kind == kind && last.end == start) {
          tokens[tokens.length - 1] = Token(kind, last.start, end);
          return;
        }
      }
      tokens.add(Token(kind, start, end));
    }

    outer:
    while (pos < line.length) {
      for (final rule in def.states[current]!) {
        final m = rule.regExp.matchAsPrefix(line, pos);
        if (m == null || m.end == pos) continue;
        add(rule.kind, pos, m.end);
        if (rule.next != null) current = rule.next!;
        pos = m.end;
        continue outer;
      }
      add(TokenKind.plain, pos, pos + 1);
      pos++;
    }
    return LineHighlight(tokens, current == 'root' ? null : current);
  }
}
