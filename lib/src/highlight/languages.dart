import 'highlighter.dart';
import 'rule_highlighter.dart';

String _words(String list) => '\\b(?:${list.split(' ').join('|')})\\b';

LexRule _r(String pattern, TokenKind kind, {String? next, bool ci = false}) =>
    LexRule(pattern, kind, next: next, caseSensitive: !ci);

const String _number =
    r'\b(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?)[a-zA-Z]{0,2}\b';
const String _dq = r'"(?:[^"\\]|\\.)*(?:"|$)';
const String _sq = r"'(?:[^'\\]|\\.)*(?:'|$)";
const String _operators = r'[+\-*/%=<>!&|^~?:]+';
const String _punct = r'[{}()\[\];,.]';

/// `/* … */` support: a rule for the root state and the `block` state.
List<LexRule> _blockCommentRoot() => [
  _r(r'/\*', TokenKind.comment, next: 'block'),
];

List<LexRule> _blockCommentState() => [
  _r(r'\*/', TokenKind.comment, next: 'root'),
  _r(r'(?:[^*]|\*(?!/))+', TokenKind.comment),
];

LanguageDefinition _cLike({
  required String name,
  List<String> aliases = const [],
  required String keywords,
  String types = '',
  String constants = 'true false null',
  bool preprocessor = false,
  bool annotations = false,
  bool rawBacktick = false,
  bool charLiteral = true,
  bool lifetimes = false,
}) {
  return LanguageDefinition(
    name: name,
    aliases: aliases,
    states: {
      'root': [
        _r(r'//.*', TokenKind.comment),
        ..._blockCommentRoot(),
        if (preprocessor) _r(r'^\s*#\s*\w+', TokenKind.meta),
        if (annotations) _r(r'@\w+', TokenKind.meta),
        _r(_dq, TokenKind.string),
        if (rawBacktick) _r(r'`', TokenKind.string, next: 'raw'),
        if (lifetimes) _r(r"'[a-zA-Z_]\w*(?!')", TokenKind.meta),
        if (charLiteral) _r(r"'(?:[^'\\]|\\.)'", TokenKind.string),
        _r(_number, TokenKind.number),
        _r(_words(keywords), TokenKind.keyword),
        _r(_words(constants), TokenKind.constant),
        if (types.isNotEmpty) _r(_words(types), TokenKind.type),
        _r(r'\b[A-Z][A-Za-z0-9_]*\b', TokenKind.type),
        _r(r'\b[a-zA-Z_]\w*(?=\s*\()', TokenKind.function),
        _r(r'[A-Za-z_]\w*', TokenKind.plain),
        _r(_operators, TokenKind.operator),
        _r(_punct, TokenKind.punctuation),
      ],
      'block': _blockCommentState(),
      if (rawBacktick)
        'raw': [
          _r(r'`', TokenKind.string, next: 'root'),
          _r(r'[^`]+', TokenKind.string),
        ],
    },
  );
}

final LanguageDefinition _dart = LanguageDefinition(
  name: 'dart',
  states: {
    'root': [
      _r(r'///.*|//.*', TokenKind.comment),
      ..._blockCommentRoot(),
      _r(r'@\w+', TokenKind.meta),
      _r("'''", TokenKind.string, next: 'tsq'),
      _r('"""', TokenKind.string, next: 'tdq'),
      _r('r?$_dq', TokenKind.string),
      _r("r?$_sq", TokenKind.string),
      _r(_number, TokenKind.number),
      _r(
        _words(
          'abstract as assert async await base break case catch class '
          'const continue covariant default deferred do dynamic else enum '
          'export extends extension external factory final finally for '
          'Function get hide if implements import in interface is late '
          'library mixin new of on operator part required rethrow return '
          'sealed set show static super switch sync this throw try typedef '
          'var void when while with yield',
        ),
        TokenKind.keyword,
      ),
      _r(_words('true false null'), TokenKind.constant),
      _r(_words('int double num bool'), TokenKind.type),
      _r(r'\b[A-Z_$][A-Za-z0-9_$]*\b', TokenKind.type),
      _r(r'\b[a-z_$][\w$]*(?=\s*[(<])', TokenKind.function),
      _r(r'[A-Za-z_$][\w$]*', TokenKind.plain),
      _r(_operators, TokenKind.operator),
      _r(_punct, TokenKind.punctuation),
    ],
    'block': _blockCommentState(),
    'tsq': [
      _r("'''", TokenKind.string, next: 'root'),
      _r(r"(?:[^'\\]|\\.|'(?!''))+", TokenKind.string),
    ],
    'tdq': [
      _r('"""', TokenKind.string, next: 'root'),
      _r(r'(?:[^"\\]|\\.|"(?!""))+', TokenKind.string),
    ],
  },
);

final LanguageDefinition _javascript = LanguageDefinition(
  name: 'javascript',
  aliases: const ['js', 'jsx', 'ts', 'tsx', 'typescript', 'mjs', 'cjs'],
  states: {
    'root': [
      _r(r'//.*', TokenKind.comment),
      ..._blockCommentRoot(),
      _r(r'@\w+', TokenKind.meta),
      _r(_dq, TokenKind.string),
      _r(_sq, TokenKind.string),
      _r('`', TokenKind.string, next: 'tpl'),
      _r(_number, TokenKind.number),
      _r(
        _words(
          'abstract as async await break case catch class const '
          'continue debugger declare default delete do else enum export '
          'extends finally for from function get if implements import in '
          'instanceof interface let namespace new of private protected '
          'public readonly return set static super switch this throw try '
          'type typeof var void while with yield',
        ),
        TokenKind.keyword,
      ),
      _r(_words('true false null undefined NaN Infinity'), TokenKind.constant),
      _r(
        _words(
          'string number boolean any unknown never object symbol '
          'bigint',
        ),
        TokenKind.type,
      ),
      _r(r'\b[A-Z][A-Za-z0-9_$]*\b', TokenKind.type),
      _r(r'[A-Za-z_$][\w$]*(?=\s*[(<])', TokenKind.function),
      _r(r'[A-Za-z_$][\w$]*', TokenKind.plain),
      _r(_operators, TokenKind.operator),
      _r(_punct, TokenKind.punctuation),
    ],
    'block': _blockCommentState(),
    'tpl': [
      _r('`', TokenKind.string, next: 'root'),
      _r(r'(?:[^`\\]|\\.)+', TokenKind.string),
    ],
  },
);

final LanguageDefinition _json = LanguageDefinition(
  name: 'json',
  aliases: const ['jsonc', 'json5'],
  states: {
    'root': [
      _r(r'"(?:[^"\\]|\\.)*"(?=\s*:)', TokenKind.property),
      _r(_dq, TokenKind.string),
      _r(r'-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?', TokenKind.number),
      _r(_words('true false null'), TokenKind.constant),
      _r(r'//.*', TokenKind.comment),
      _r(r'[{}\[\],:]', TokenKind.punctuation),
    ],
  },
);

final LanguageDefinition _python = LanguageDefinition(
  name: 'python',
  aliases: const ['py', 'python3'],
  states: {
    'root': [
      _r(r'#.*', TokenKind.comment),
      _r('[rRbBfFuU]{0,2}"""', TokenKind.string, next: 'tdq'),
      _r("[rRbBfFuU]{0,2}'''", TokenKind.string, next: 'tsq'),
      _r('[rRbBfFuU]{0,2}$_dq', TokenKind.string),
      _r("[rRbBfFuU]{0,2}$_sq", TokenKind.string),
      _r(r'@[\w.]+', TokenKind.meta),
      _r(_number, TokenKind.number),
      _r(
        _words(
          'and as assert async await break class continue def del elif '
          'else except finally for from global if import in is lambda '
          'nonlocal not or pass raise return try while with yield match '
          'case',
        ),
        TokenKind.keyword,
      ),
      _r(_words('True False None self cls'), TokenKind.constant),
      _r(r'\b[A-Z][A-Za-z0-9_]*\b', TokenKind.type),
      _r(r'\b[a-zA-Z_]\w*(?=\s*\()', TokenKind.function),
      _r(r'[A-Za-z_]\w*', TokenKind.plain),
      _r(_operators, TokenKind.operator),
      _r(_punct, TokenKind.punctuation),
    ],
    'tdq': [
      _r('"""', TokenKind.string, next: 'root'),
      _r(r'(?:[^"\\]|\\.|"(?!""))+', TokenKind.string),
    ],
    'tsq': [
      _r("'''", TokenKind.string, next: 'root'),
      _r(r"(?:[^'\\]|\\.|'(?!''))+", TokenKind.string),
    ],
  },
);

final LanguageDefinition _bash = LanguageDefinition(
  name: 'bash',
  aliases: const ['sh', 'shell', 'zsh', 'console'],
  states: {
    'root': [
      _r(r'(?:^|(?<=\s))#.*', TokenKind.comment),
      _r(r'\$(?:\w+|\{[^}]*\}|[@#?$!*-])', TokenKind.variable),
      _r(_dq, TokenKind.string),
      _r(r"'[^']*(?:'|$)", TokenKind.string),
      _r(
        _words(
          'if then else elif fi for while until do done case esac '
          'function in return exit export local readonly source select '
          'time',
        ),
        TokenKind.keyword,
      ),
      _r(
        _words(
          'echo cd ls cat grep sed awk find mkdir rm cp mv chmod chown '
          'curl wget git npm yarn pip python node docker sudo apt brew '
          'tar make flutter dart',
        ),
        TokenKind.function,
      ),
      _r(r'(?<![\w-])--?[A-Za-z][\w-]*', TokenKind.property),
      _r(_number, TokenKind.number),
      _r(r'[|&;<>]+|\$\(|\)|[=!]', TokenKind.operator),
      _r(r'[A-Za-z_][\w./-]*', TokenKind.plain),
    ],
  },
);

final LanguageDefinition _yaml = LanguageDefinition(
  name: 'yaml',
  aliases: const ['yml'],
  states: {
    'root': [
      _r(r'(?:^|(?<=\s))#.*', TokenKind.comment),
      _r(
        r'''^[ \t]*(?:-[ \t]+)?[^\s:#'"\-][^:#]*?(?=:(?:\s|$))''',
        TokenKind.property,
      ),
      _r(
        r'''^[ \t]*(?:-[ \t]+)?(?:"[^"]*"|'[^']*')(?=\s*:)''',
        TokenKind.property,
      ),
      _r(_dq, TokenKind.string),
      _r(_sq, TokenKind.string),
      _r(r'[&*][\w-]+', TokenKind.meta),
      _r(_number, TokenKind.number),
      _r(_words('true false null yes no on off'), TokenKind.constant),
      _r(r'[-:\[\]{},|>?]', TokenKind.punctuation),
      _r(r'[A-Za-z_][\w./-]*', TokenKind.plain),
    ],
  },
);

final LanguageDefinition _sql = LanguageDefinition(
  name: 'sql',
  aliases: const ['mysql', 'postgresql', 'postgres', 'sqlite', 'psql'],
  states: {
    'root': [
      _r(r'--.*', TokenKind.comment),
      ..._blockCommentRoot(),
      _r(_sq, TokenKind.string),
      _r(_dq, TokenKind.property),
      _r(_number, TokenKind.number),
      _r(
        _words(
          'select from where insert into values update set delete '
          'create table alter drop index view join inner left right outer '
          'full cross on group by order having limit offset as and or not '
          'is in like between distinct union all case when then else end '
          'primary key foreign references default unique exists asc desc '
          'with returning begin commit rollback add column constraint '
          'check if',
        ),
        TokenKind.keyword,
        ci: true,
      ),
      _r(_words('null true false'), TokenKind.constant, ci: true),
      _r(
        _words(
          'int integer bigint smallint serial text varchar char '
          'boolean bool date time timestamp float double decimal numeric '
          'uuid json jsonb blob',
        ),
        TokenKind.type,
        ci: true,
      ),
      _r(r'\b[a-zA-Z_]\w*(?=\s*\()', TokenKind.function),
      _r(r'[A-Za-z_]\w*', TokenKind.plain),
      _r(_operators, TokenKind.operator),
      _r(_punct, TokenKind.punctuation),
    ],
    'block': _blockCommentState(),
  },
);

final LanguageDefinition _html = LanguageDefinition(
  name: 'html',
  aliases: const ['xml', 'svg', 'xhtml', 'vue'],
  states: {
    'root': [
      _r(r'<!--', TokenKind.comment, next: 'comment'),
      _r(r'<!\w*[^>]*>?', TokenKind.meta),
      _r(r'</?[A-Za-z][\w:.-]*', TokenKind.tag, next: 'tag'),
      _r(r'&#?\w+;', TokenKind.constant),
      _r(r'[^<&]+', TokenKind.plain),
    ],
    'comment': [
      _r(r'-->', TokenKind.comment, next: 'root'),
      _r(r'(?:[^-]|-(?!->))+', TokenKind.comment),
    ],
    'tag': [
      _r(r'/?>', TokenKind.tag, next: 'root'),
      _r(r'\s+', TokenKind.plain),
      _r(r'[\w:.@-]+(?=\s*=)', TokenKind.attribute),
      _r(
        r'"[^"]*"?|'
        "'[^']*'?",
        TokenKind.string,
      ),
      _r(r'=', TokenKind.operator),
      _r(r'[^\s>/=]+', TokenKind.plain),
      _r(r'/', TokenKind.plain),
    ],
  },
);

final LanguageDefinition _css = LanguageDefinition(
  name: 'css',
  aliases: const ['scss', 'less'],
  states: {
    'root': [
      ..._blockCommentRoot(),
      _r(r'//.*', TokenKind.comment),
      _r(_dq, TokenKind.string),
      _r(_sq, TokenKind.string),
      _r(r'@[\w-]+', TokenKind.keyword),
      _r(r'#[0-9a-fA-F]{3,8}\b', TokenKind.number),
      _r(r'-?\d*\.?\d+(?:px|em|rem|%|vh|vw|s|ms|deg|fr)?\b', TokenKind.number),
      _r(r'[\w-]+(?=\s*:\s)', TokenKind.property),
      _r(r'[.#][A-Za-z_-][\w-]*', TokenKind.type),
      _r(r'!important', TokenKind.keyword),
      _r(r'[\w-]+(?=\()', TokenKind.function),
      _r(r'[A-Za-z-]+', TokenKind.plain),
      _r(r'[{}();,:>+~*]', TokenKind.punctuation),
    ],
    'block': _blockCommentState(),
  },
);

final LanguageDefinition _diff = LanguageDefinition(
  name: 'diff',
  aliases: const ['patch'],
  states: {
    'root': [
      _r(r'^(?:\+\+\+|---)\s.*|^diff\s.*|^index\s.*', TokenKind.meta),
      _r(r'^@@.*', TokenKind.meta),
      _r(r'^\+.*', TokenKind.addition),
      _r(r'^-.*', TokenKind.deletion),
      _r(r'.+', TokenKind.plain),
    ],
  },
);

/// The languages every [RuleBasedHighlighter] understands.
final List<LanguageDefinition> builtInLanguages = [
  _dart,
  _javascript,
  _json,
  _python,
  _bash,
  _yaml,
  _sql,
  _html,
  _css,
  _diff,
  _cLike(
    name: 'c',
    keywords:
        'auto break case const continue default do else enum extern for '
        'goto if inline register restrict return sizeof static struct switch '
        'typedef union volatile while',
    types:
        'int char float double void long short unsigned signed size_t bool '
        'uint8_t uint16_t uint32_t uint64_t int8_t int16_t int32_t int64_t',
    constants: 'true false NULL',
    preprocessor: true,
  ),
  _cLike(
    name: 'cpp',
    aliases: const ['c++', 'cc', 'cxx', 'h', 'hpp'],
    keywords:
        'alignas and asm auto break case catch class const constexpr '
        'continue decltype default delete do dynamic_cast else enum explicit '
        'export extern for friend goto if inline namespace new noexcept '
        'operator override private protected public return sizeof static '
        'static_cast struct switch template this throw try typedef typename '
        'union using virtual volatile while',
    types:
        'int char float double void long short unsigned signed bool auto '
        'size_t string vector map set',
    constants: 'true false nullptr NULL',
    preprocessor: true,
  ),
  _cLike(
    name: 'java',
    keywords:
        'abstract assert break case catch class const continue default '
        'do else enum extends final finally for goto if implements import '
        'instanceof interface native new package private protected public '
        'return static strictfp super switch synchronized this throw throws '
        'transient try var volatile while record sealed permits',
    types: 'int long short byte float double boolean char void String Object',
    annotations: true,
  ),
  _cLike(
    name: 'kotlin',
    aliases: const ['kt', 'kts'],
    keywords:
        'abstract as break by catch class companion const constructor '
        'continue crossinline data do else enum external final finally for '
        'fun get if import in infix init inline inner interface internal is '
        'lateinit noinline object open operator out override package private '
        'protected public reified return sealed set super suspend this throw '
        'try typealias val var vararg when where while',
    types:
        'Int Long Short Byte Float Double Boolean Char String Unit Any '
        'Nothing',
    annotations: true,
  ),
  _cLike(
    name: 'swift',
    keywords:
        'actor associatedtype async await break case catch class '
        'continue default defer deinit do else enum extension fallthrough '
        'fileprivate final for func guard if import in indirect init inout '
        'internal is lazy let mutating nonmutating open operator override '
        'private protocol public repeat rethrows return self Self static '
        'struct subscript super switch throw throws try typealias var weak '
        'where while',
    types:
        'Int Double Float Bool String Character Array Dictionary Set '
        'Optional Any Void',
    constants: 'true false nil',
    annotations: true,
  ),
  _cLike(
    name: 'go',
    aliases: const ['golang'],
    keywords:
        'break case chan const continue default defer else '
        'fallthrough for func go goto if import interface map package range '
        'return select struct switch type var',
    types:
        'int int8 int16 int32 int64 uint uint8 uint16 uint32 uint64 float32 '
        'float64 string bool byte rune error any',
    constants: 'true false nil iota',
    rawBacktick: true,
  ),
  _cLike(
    name: 'rust',
    aliases: const ['rs'],
    keywords:
        'as async await break const continue crate dyn else enum extern '
        'fn for if impl in let loop match mod move mut pub ref return self '
        'Self static struct super trait type unsafe use where while',
    types:
        'i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool '
        'char str String Vec Option Result Box',
    constants: 'true false None Some Ok Err',
    lifetimes: true,
    annotations: false,
  ),
  _cLike(
    name: 'csharp',
    aliases: const ['cs', 'c#'],
    keywords:
        'abstract as async await base break case catch checked class '
        'const continue default delegate do else enum event explicit extern '
        'finally fixed for foreach goto if implicit in interface internal is '
        'lock namespace new operator out override params private protected '
        'public readonly ref return sealed sizeof stackalloc static struct '
        'switch this throw try typeof unchecked unsafe using var virtual '
        'void volatile while record init',
    types:
        'int long short byte float double decimal bool char string object '
        'dynamic',
  ),
];
