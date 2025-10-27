# stem_sqlite

[![pub package](https://img.shields.io/pub/v/stem_sqlite.svg)](https://pub.dev/packages/stem_sqlite)
[![Dart](https://img.shields.io/badge/dart-%3E%3D3.9.0-blue.svg)](https://dart.dev)
[![License](https://img.shields.io/badge/license-MIT-purple.svg)](https://github.com/kingwill101/stem/blob/main/LICENSE)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-support-yellow.svg)](https://www.buymeacoffee.com/kingwill101)

SQLite broker and result backend implementations for the Stem runtime. Use it
to embed Stem into single-node or desktop deployments without external
infrastructure.

## Install

```bash
dart pub add stem_sqlite
```

Add the core runtime if you haven't already:

```bash
dart pub add stem
```

## Usage

```dart
import 'package:stem/stem.dart';
import 'package:stem_sqlite/stem_sqlite.dart';

Future<void> main() async {
  final registry = SimpleTaskRegistry()
    ..register(FunctionTaskHandler(name: 'demo.sqlite', handler: print));

  final broker = await SqliteBroker.open(
    SqliteConnection.inMemory(), // or SqliteConnection.file('stem.db')
  );
  final backend = await SqliteResultBackend.open(
    SqliteConnection.inMemory(),
  );

  final stem = Stem(broker: broker, backend: backend, registry: registry);
  await stem.enqueue('demo.sqlite', args: {'name': 'Stem'});
}
```

## Tests

The package bundles compliance tests from `stem_adapter_tests`. Running

```bash
dart test
```

executes the shared broker and backend contract suites against the SQLite
adapters.

## Support

Report issues or feature requests on the
[GitHub tracker](https://github.com/kingwill101/stem/issues). Commercial support
is available via [Buy Me A Coffee](https://www.buymeacoffee.com/kingwill101).
