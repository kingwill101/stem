# stem_redis

Redis Streams broker, result backend, and scheduler utilities for the Stem task
runtime.

## Install

```bash
dart pub add stem_redis
```

Add the core runtime if you haven't already:

```bash
dart pub add stem
```

## Usage

```dart
import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';

Future<void> main() async {
  final registry = SimpleTaskRegistry()
    ..register(FunctionTaskHandler(name: 'demo.hello', handler: print));

  final broker = await RedisStreamsBroker.connect('redis://localhost:6379');
  final backend = await RedisResultBackend.connect('redis://localhost:6379/1');

  final stem = Stem(broker: broker, registry: registry, backend: backend);
  await stem.enqueue('demo.hello', args: {'name': 'Stem'});
}
```

## Tests

Integration suites require the dockerised Redis/Postgres stack provided by the
CLI package:

```bash
source ../../stem_cli/_init_test_env
dart test
```

The redis contract tests will automatically skip if `STEM_TEST_REDIS_URL` is not
set.
