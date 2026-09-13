# Stem Documentation Examples

This package contains runnable Dart code examples that are embedded in the Stem
documentation.

## Purpose

By keeping examples in a proper Dart package:
- Code can be analyzed and type-checked
- Examples can be tested to ensure APIs are correct
- IDE support works properly for maintenance
- Documentation stays in sync with actual API

## Structure

```
packages/stem/example/docs_snippets/
├── lib/
│   ├── quick_start.dart
│   ├── tasks.dart
│   ├── workers_programmatic.dart
│   └── ...
└── pubspec.yaml
```

## Using Regions

Code is organized using region comments that can be extracted in docs:

```dart
// #region my-example
void exampleCode() {
  // This code will be embedded in documentation
}
// #endregion my-example
```

## Embedding in Documentation

In markdown files, use the code fence with `file=` meta:

````markdown
```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/quick_start.dart#quickstart-main

```
````

This imports only the code between `// #region quickstart-main` and
`// #endregion quickstart-main`.

To import an entire file (no region):

````markdown
```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/quick_start.dart

```
````

**Note:** Ordinary relative paths resolve from the Markdown file's directory.
`<rootDir>` resolves to `.site/` because that is the root configured by the
site's snippet plugin. Region names and their closing markers must exist:
invalid includes fail the documentation build rather than rendering an error
comment in the published page.

## Running Examples

```bash
dart pub get
dart analyze
```

The infrastructure tutorial also runs across three processes. Set
`STEM_BROKER_URL`, `STEM_RESULT_BACKEND_URL`, and a dedicated `STEM_NAMESPACE`
for a local Redis instance, then run:

```bash
dart run lib/infrastructure.dart enqueue
dart run lib/infrastructure.dart work
dart run lib/infrastructure.dart result TASK_ID
```

Use the ID printed by `enqueue`. The expected result is `42`; `work` is a
one-shot worker that stops after an idle window. See the website's
Infrastructure guide for deployment assumptions and cleanup.

## Adding New Examples

1. Create or edit a file in `lib/` with proper region markers
2. Reference the region in your markdown file using the syntax above
3. Run `npm run build` from `.site/` to verify it works
4. Run `npm run test:docs` from `.site/` after resolving the root workspace
   with `flutter pub get`. This verifies snippet-import failures and executes
   the selected complete README/site/core-skill examples against local APIs.
