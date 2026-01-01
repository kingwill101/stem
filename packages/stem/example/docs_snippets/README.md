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

**Note:** Paths are relative to the markdown file's location.

## Running Examples

```bash
dart pub get
dart analyze
```

## Adding New Examples

1. Create or edit a file in `lib/` with proper region markers
2. Reference the region in your markdown file using the syntax above
3. Run `npm run build` from `.site/` to verify it works
