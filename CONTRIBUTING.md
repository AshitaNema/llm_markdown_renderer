# Contributing

Thanks for helping. Bug reports with a reproducible Markdown sample are the most
useful contribution.

## Reporting a rendering bug

Open an issue with the **exact Markdown** and, if you can, **how it was
streamed** (chunk sizes). Flicker and layout jumps often depend on where a chunk
boundary falls, so the chunking matters. The issue form asks for both.

## Development setup

```sh
git clone https://github.com/AshitaNema/llm_markdown_renderer
cd llm_markdown_renderer
flutter pub get
flutter test
```

Before opening a pull request:

```sh
dart format .
flutter analyze
(cd example && flutter pub get && flutter analyze)
flutter test
```

## How the code is organised

[ARCHITECTURE.md](ARCHITECTURE.md) explains the layers and lists which test file
proves what. In short: `lib/src/parser` is plain Dart (no Flutter imports),
`lib/src/widgets` is the Flutter layer.

## Rules of thumb

* **Parser changes need the chunk-boundary suite.** The invariant is that every
  way of chunking an input yields the same document as parsing it in one piece.
  Add a sample to `test/fixtures.dart` that exercises your change; it is then
  tested with every 2-way split, one character at a time, and random partitions.
* **Keep appends cheap.** Work per chunk should depend on the chunk and the open
  block, not on the document length. `test/parser/incremental_test.dart` guards
  this; `dart run benchmark/append_cost.dart` shows the numbers.
* **Keep the public API small.** Everything exported is something to keep stable.
  Put helpers under `lib/src` and do not export them without discussion.
* **Document public members.** `public_member_api_docs` is an error.
* **Golden tests** use the default test font so they are identical on every
  platform. If a visual change is intended, regenerate with
  `flutter test --update-goldens test/golden` and review the images in the diff.

## Adding a highlighted language

Add a `LanguageDefinition` in `lib/src/highlight/languages.dart` (see the
existing ones) and list it in `builtInLanguages`. Add a sample line to the
"every language" test and one assertion on its distinctive tokens in
`test/highlight/highlighter_test.dart`.

## Commits and pull requests

Keep commits focused, describe *why* in the message, and fill in the pull
request template. By contributing you agree that your contribution is licensed
under the MIT license of this repository.
