/// A Flutter-free, incremental Markdown parser designed for LLM output that
/// arrives in small chunks.
///
/// Import this library to use the parser from plain Dart (CLIs, servers,
/// isolates). Flutter apps normally import `llm_markdown_renderer.dart`,
/// which re-exports everything here.
library;

export 'src/ast/block.dart';
export 'src/ast/document.dart';
export 'src/ast/inline.dart';
export 'src/highlight/highlighter.dart';
export 'src/highlight/rule_highlighter.dart';
export 'src/parser/block_parser.dart' show IncrementalMarkdownParser;
export 'src/parser/inline_parser.dart' show parseInlines;
export 'src/parser/line_buffer.dart' show LineBuffer;
export 'src/parser/options.dart';
