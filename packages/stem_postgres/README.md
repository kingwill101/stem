# stem_postgres

[![pub package](https://img.shields.io/pub/v/stem_postgres.svg)](https://pub.dev/packages/stem_postgres)
[![Dart](https://img.shields.io/badge/dart-%3E%3D3.9.0-blue.svg)](https://dart.dev)
[![License](https://img.shields.io/badge/license-MIT-purple.svg)](https://github.com/kingwill101/stem/blob/main/LICENSE)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-support-yellow.svg)](https://www.buymeacoffee.com/kingwill101)

Postgres broker, result backend, and scheduler helpers for the Stem runtime.

## Install

```bash
dart pub add stem_postgres
```

Add the core runtime if you haven't already:

```bash
dart pub add stem
```

## Usage

```dart
import 'package:stem/stem.dart';
import 'package:stem_postgres/stem_postgres.dart';

Future<void> main() async {
  final registry = SimpleTaskRegistry()
    ..register(FunctionTaskHandler(name: 'demo.pg', handler: print));

  final broker = await PostgresBroker.connect(
    'postgresql://postgres:postgres@localhost:5432/stem',
  );
  final backend = await PostgresResultBackend.connect(
    'postgresql://postgres:postgres@localhost:5432/stem',
  );

  final stem = Stem(broker: broker, registry: registry, backend: backend);
  await stem.enqueue('demo.pg', args: {'name': 'Stem'});
}
```

## Tests

Postgres integration suites expect the docker stack provided by `stem_cli`:

```bash
source ../../stem_cli/_init_test_env
dart test
```

The tests skip automatically if `STEM_TEST_POSTGRES_URL` is missing.
