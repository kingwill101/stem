<p align="center">
  <img src=".site/static/img/stem-logo.png" width="400" alt="Stem Logo" />
</p>

<p align="center">
  <strong>Dart-native background job platform</strong><br>
  Queues, retries, scheduling, workflows, and observability — all in pure Dart.
</p>

<p align="center">
  <a href="https://pub.dev/packages/stem"><img src="https://img.shields.io/pub/v/stem.svg" alt="Pub Version"></a>
  <a href="https://github.com/kingwill101/stem/actions"><img src="https://github.com/kingwill101/stem/workflows/CI/badge.svg" alt="CI Status"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT"></a>
</p>

---

## Why Stem?

- **Pure Dart** — No external worker processes, no FFI bindings. Runs anywhere Dart runs.
- **Pluggable backends** — Swap between SQLite, Redis, or Postgres with a single line.
- **Battle-tested patterns** — Retries with backoff, rate limiting, dead-letter queues, and priority scheduling.
- **Workflows** — Durable, checkpointed execution for complex multi-step processes.
- **Canvas API** — Compose tasks into groups, chains, and chords.
- **Observability** — Built-in OpenTelemetry integration for traces and metrics.

---

## Quick Start

```dart
import 'dart:async';

import 'package:stem/stem.dart';

class EmailTask extends TaskHandler<String> {
  @override
  String get name => 'email.send';

  @override
  Future<String> call(TaskContext ctx, Map<String, Object?> args) async {
    final to = args['to'] as String;
    return 'sent to $to';
  }
}

Future<void> main() async {
  final client = await StemClient.inMemory(tasks: [EmailTask()]);
  final worker = await client.createWorker();
  unawaited(worker.start());

  final taskId = await client.stem.enqueue(
    'email.send',
    args: {'to': 'hello@example.com'},
  );
  final result = await client.stem.waitForTask<String>(taskId);
  print('Result: ${result?.value}');

  await worker.shutdown();
  await client.close();
}
```

---

## Architecture

```
                               PRODUCERS
            ┌───────────────────┬───────────────────┬──────────────────┐
            │                   │                   │                  │
            v                   v                   v                  v
       ┌─────────┐        ┌──────────┐        ┌───────────┐        ┌──────────┐
       │  Stem   │        │  Canvas  │        │ Workflow  │        │  Client  │
       │ Client  │        │ (chains, │        │   API     │        │  SDKs    │
       └────┬────┘        │ groups)  │        └─────┬─────┘        └────┬─────┘
            │             └────┬─────┘              │                    │
            └──────────────────┼────────────────────┼────────────────────┘
                               │
                               v
        ┌──────────────────────────────────────────────────────────┐
        │                         BROKER                           │
        │ queues / leases / acks / nack / delayed / dlq             │
        └───────────────┬───────────────────────────┬──────────────┘
                        │                           │
                        v                           v
               ┌──────────────────┐         ┌─────────────────────┐
               │  Workflow Engine │         │       Workers       │
               │  claim runs &    │         │  (many, independent)│
               │  schedule steps  │         └───────┬───────┬─────┘
               └───────┬──────────┘                 │       │
                       │                            │       │
            enqueue steps ──────────────────────────┘       │
                       │                                    │
                       v                                    v
            ┌──────────────────┐                  ┌──────────────────┐
            │  Workflow Store  │                  │  Task Registry   │
            │  (runs/steps)    │                  │   & Handlers     │
            └────────┬─────────┘                  └────────┬─────────┘
                     │                                     │
                     v                                     v
            ┌──────────────────┐                  ┌──────────────────┐
            │    Event Bus     │                  │  Result Backend  │
            └──────────────────┘                  └──────────────────┘

        ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─

                              SCHEDULING

            ┌────────────────┐     ┌────────────────┐
            │ Beat Scheduler │---->│ Schedule Store │
            │     (cron)     │     └────────────────┘
            └───────┬────────┘             │
                    │                      │
                    v                      v
                 ┌────────┐          ┌────────────┐
                 │ Broker │<---------│ Lock Store │
                 └────────┘          └────────────┘
            (enqueues scheduled tasks / lease guards)

       ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─

                             ADAPTERS

         ┌────────────┐   ┌────────────┐   ┌────────────┐
         │   SQLite   │   │   Redis    │   │  Postgres  │
         │  (local)   │   │ (streams)  │   │ (durable)  │
         └────────────┘   └────────────┘   └────────────┘
```

---

## Packages

| Package | Description | pub.dev |
|---------|-------------|---------|
| [`stem`](./packages/stem) | Core runtime: contracts, worker, scheduler, in-memory adapters, signals, Canvas, workflows | [![pub](https://img.shields.io/pub/v/stem.svg)](https://pub.dev/packages/stem) |
| [`stem_cli`](./packages/stem_cli) | Command-line tooling (`stem` executable) and CLI utilities | [![pub](https://img.shields.io/pub/v/stem_cli.svg)](https://pub.dev/packages/stem_cli) |
| [`stem_memory`](./packages/stem_memory) | In-memory adapter package (broker/backend/workflow/scheduler factories) | [![pub](https://img.shields.io/pub/v/stem_memory.svg)](https://pub.dev/packages/stem_memory) |
| [`stem_sqlite`](./packages/stem_sqlite) | SQLite broker and result backend for local dev/testing | [![pub](https://img.shields.io/pub/v/stem_sqlite.svg)](https://pub.dev/packages/stem_sqlite) |
| [`stem_redis`](./packages/stem_redis) | Redis Streams broker, result backend, and watchdog helpers | [![pub](https://img.shields.io/pub/v/stem_redis.svg)](https://pub.dev/packages/stem_redis) |
| [`stem_postgres`](./packages/stem_postgres) | Postgres broker, result backend, and scheduler stores | [![pub](https://img.shields.io/pub/v/stem_postgres.svg)](https://pub.dev/packages/stem_postgres) |
| [`stem_flutter`](./packages/stem_flutter) | Adapter-neutral Flutter helpers for mobile worker isolates and queue monitoring | [![pub](https://img.shields.io/pub/v/stem_flutter.svg)](https://pub.dev/packages/stem_flutter) |
| [`stem_flutter_sqlite`](./packages/stem_flutter_sqlite) | Flutter SQLite runtime/storage helpers for mobile Stem apps | [![pub](https://img.shields.io/pub/v/stem_flutter_sqlite.svg)](https://pub.dev/packages/stem_flutter_sqlite) |
| [`stem_builder`](./packages/stem_builder) | Build-time code generator for annotated tasks and workflows | [![pub](https://img.shields.io/pub/v/stem_builder.svg)](https://pub.dev/packages/stem_builder) |
| [`stem_adapter_tests`](./packages/stem_adapter_tests) | Shared contract test suites for adapter implementations | [![pub](https://img.shields.io/pub/v/stem_adapter_tests.svg)](https://pub.dev/packages/stem_adapter_tests) |
| [`stem_dashboard`](./packages/dashboard) | Hotwire-based operations dashboard (experimental) | — |

---

## Features

### Task Options

```dart
TaskOptions(
  queue: 'high-priority',      // Target queue
  maxRetries: 5,               // Retry on failure
  priority: 10,                // Higher = processed first
  rateLimit: '100/m',          // Rate limiting
  softTimeLimit: Duration(seconds: 30),
  hardTimeLimit: Duration(minutes: 2),
  visibilityTimeout: Duration(minutes: 5),
)
```

### Canvas — Task Composition

```dart
// Chain: sequential execution, results flow forward
await canvas.chain([
  task('resize', args: {'file': 'img.png'}),
  task('upload', args: {'bucket': 's3://photos'}),
  task('notify', args: {'channel': 'slack'}),
]);

// Group: parallel execution
await canvas.group([
  task('resize', args: {'size': 'small'}),
  task('resize', args: {'size': 'medium'}),
  task('resize', args: {'size': 'large'}),
]);

// Chord: parallel tasks + callback when all complete
await canvas.chord(
  [task('fetch.a'), task('fetch.b'), task('fetch.c')],
  callback: task('aggregate'),
);
```

### Durable Workflows

```dart
final workflow = WorkflowScript('order.process', (wf) async {
  final validated = await wf.activity('validate', args: order);
  final charged = await wf.activity('charge', args: validated);
  
  await wf.sleep(Duration(hours: 24)); // Durable sleep!
  
  await wf.activity('ship', args: charged);
});
```

### Cron Scheduling

```dart
final beat = BeatScheduler(
  broker: broker,
  scheduleStore: store,
  entries: [
    ScheduleEntry(
      name: 'daily-report',
      cron: '0 9 * * *',  // Every day at 9 AM
      task: task('reports.generate'),
    ),
  ],
);
```

---

## CLI

```bash
# Run a worker
stem worker --queue default --concurrency 8

# Run the beat scheduler
stem schedule list

# Inspect dead-letter queue
stem dlq list
stem dlq retry <task-id>

# List registered tasks
stem tasks ls

# Health check
stem health
```

---

## Development

### Prerequisites

- Dart 3.9.2+
- Docker (for adapter integration tests)

### Setup

```bash
# Clone the repository
git clone https://github.com/kingwill101/stem.git
cd stem

# Install dependencies
dart pub get

# Run quality gates
dart format --output=none --set-exit-if-changed .
dart analyze
task test:no-env
```

### Adapter Tests

Integration tests require the Docker test stack:

```bash
# Run all package tests with Docker-backed integration env
task test

# Run coverage workflow for core adapters/runtime packages
task coverage

# Run targeted adapter suites (auto-bootstraps integration env)
task test:contract
task test:redis
task test:postgres
```

Targeted adapter tasks now bootstrap integration environment automatically.
If bootstrap still fails (for example Docker unavailable), run:

```bash
source ./packages/stem_cli/_init_test_env
```

Capability flags and skip behavior for adapter contract suites are documented in
[`packages/stem_adapter_tests/README.md`](./packages/stem_adapter_tests/README.md).

---

## Contributing

Contributions are welcome! Please read the contribution guidelines before submitting a PR.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## License

MIT License — see [LICENSE](./LICENSE) for details.

---

<p align="center">
  <a href="https://www.buymeacoffee.com/kingwill101">
    <img src="https://img.buymeacoffee.com/button-api/?text=Support development&emoji=&slug=kingwill101&button_colour=FFDD00&font_colour=000000&font_family=Cookie&outline_colour=000000&coffee_colour=ffffff" />
  </a>
</p>
