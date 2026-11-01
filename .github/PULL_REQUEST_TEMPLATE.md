## What and why

<!-- What does this change, and what problem does it solve? Link the issue. -->

## Checklist

- [ ] `dart format .`, `flutter analyze` and `flutter test` pass
- [ ] Parser changes: a test covers the new behavior **and** the chunk-boundary
      suite still passes (it checks that any chunking gives the same result)
- [ ] Public API changes are documented with dartdoc and listed in `CHANGELOG.md`
- [ ] Visual changes: golden images regenerated (`flutter test --update-goldens test/golden`) and reviewed
