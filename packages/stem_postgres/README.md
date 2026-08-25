<p align="center">
  <img src="../../.site/static/img/stem-logo.png" width="300" alt="Stem Logo" />
</p>

# stem_postgres

[![pub package](https://img.shields.io/pub/v/stem_postgres.svg)](https://pub.dev/packages/stem_postgres)
[![Dart](https://img.shields.io/badge/dart-%3E%3D3.12-blue.svg)](https://dart.dev)
[![License](https://img.shields.io/badge/license-MIT-purple.svg)](https://github.com/kingwill101/stem/blob/main/LICENSE)
[![Coverage](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/kingwill101/stem/main/packages/stem_postgres/coverage/coverage.json)](https://github.com/kingwill101/stem/actions/workflows/stem_postgres.yaml)
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

### Direct enqueue

```dart
import 'package:stem/stem.dart';
import 'package:stem_postgres/stem_postgres.dart';

Future<void> main() async {
  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler(
        name: 'demo.pg',
        entrypoint: (context, args) async {
          print('Hello ${(args['name'] as String?) ?? 'world'}');
        },
      ),
    );

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

### Transactional outbox

Use `PostgresTransactionalOutbox` when a task must be published atomically
with application data in PostgreSQL. The outbox facade is producer-only:
enqueue through it inside `outbox.transaction`, and pass the underlying broker
to the relay.

```dart
final outbox = await PostgresTransactionalOutbox.connect(
  'postgresql://postgres:postgres@localhost:5432/stem',
);
final broker = await PostgresBroker.connect(
  'postgresql://postgres:postgres@localhost:5432/stem',
);
final producerBroker = outbox.wrap(broker); // accepts any QueueBroker
final stem = Stem(broker: producerBroker, registry: registry);

await outbox.transaction((transaction) async {
  await transaction.context.table('orders').create({
    'id': orderId,
    'state': 'created',
  });
  await stem.enqueue('orders.process', args: {'id': orderId});
});

await outbox.dispatch(broker: broker);

await broker.close();
await outbox.close();
```

The relay is at least once. A crash after broker publication and before the
outbox row is marked dispatched can publish the same envelope again. Stem's
Postgres broker deduplicates queue rows by envelope ID, but task handlers and
external side effects must still be idempotent. Run migrations when opening
the outbox, or apply the `stem_task_outbox` migration as part of your normal
deployment process. The transaction boundary covers application writes and
broker publication records; result-backend status writes and unique-task
claims remain separate stores and should not be treated as part of the same
database commit unless they are made transaction-aware by the application.

### Distributed rate limiting

`PostgresRateLimiter` shares a token bucket across worker processes. Refill
uses PostgreSQL server time, and each acquire locks and updates one bucket row
inside a transaction.

```dart
final limiter = await PostgresRateLimiter.connect(
  'postgresql://postgres:postgres@localhost:5432/stem',
  namespace: 'billing-worker',
);

final workerConfig = StemWorkerConfig(rateLimiter: limiter);
```

Opening the limiter runs the package migrations, including the
`stem_rate_limit_buckets` table. A denied acquisition includes `retryAfter` so
the worker can schedule the next attempt. Close the limiter with the worker's
other resources.

### Typed `TaskDefinition`

```dart
import 'package:stem/stem.dart';
import 'package:stem_postgres/stem_postgres.dart';

final demoPg = TaskDefinition<PgArgs, void>(
  name: 'demo.pg',
  encodeArgs: (args) => {'name': args.name},
  metadata: TaskMetadata(description: 'Postgres-backed demo task'),
);

class PgArgs {
  const PgArgs({required this.name});
  final String name;
}

Future<void> main() async {
  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<void>(
        name: demoPg.name,
        entrypoint: (context, args) async {
          print('Hello ${(args['name'] as String?) ?? 'world'}');
        },
        metadata: demoPg.metadata,
      ),
    );

  final broker = await PostgresBroker.connect(
    'postgresql://postgres:postgres@localhost:5432/stem',
  );
  final backend = await PostgresResultBackend.connect(
    'postgresql://postgres:postgres@localhost:5432/stem',
  );

  final stem = Stem(broker: broker, registry: registry, backend: backend);
  await stem.enqueueCall(demoPg(const PgArgs(name: 'Stem')));
}
```

## Tests

Postgres integration suites expect the docker stack provided by `stem_cli`:

```bash
source ../../stem_cli/_init_test_env
dart test
```

The tests skip automatically if `STEM_TEST_POSTGRES_URL` is missing.
