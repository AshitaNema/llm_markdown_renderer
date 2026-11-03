/// An incremental Markdown parser designed for LLM output that arrives in
/// small chunks.
///
/// This library imports nothing from Flutter, so it can run in isolates,
/// tests and Dart scripts. The package as a whole depends on the Flutter SDK,
/// so a project using it must be built with Flutter installed. Flutter apps
/// normally import `llm_markdown_renderer.dart`, which re-exports everything
/// here.
library;

export 'src/ast/block.dart';
export 'src/ast/document.dart';
export 'src/ast/inline.dart';
export 'src/highlight/highlighter.dart';
export 'src/highlight/rule_highlighter.dart';
export 'src/parser/block_parser.dart' show IncrementalMarkdownParser;
export 'src/parser/options.dart';
