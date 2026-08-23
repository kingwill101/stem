# Contributing

Stem changes should improve a documented contract or close a demonstrated
reliability gap. New subsystems need a design note and failure tests before
they become part of the public product story.

Before opening a pull request:

```bash
dart pub get
dart run tool/check_examples.dart --skip-diff

cd packages/stem
dart format lib test --set-exit-if-changed
dart analyze --fatal-infos
dart test --exclude-tags soak --fail-fast
```

For package-wide release validation, run the release planner from the
repository root:

```bash
dart run tool/publish.dart --plan
```

The release tool derives package membership and dependency order from the Dart
workspace. It requires a clean Git tree for a real release and validates
formatting, analysis, tests, generated sources, changelog headings, and pub
publication archives.
