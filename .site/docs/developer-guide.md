---
id: developer-guide
title: Developer Guide
sidebar_label: Developer Guide
---

Stem is a spec-driven background job platform for Dart. This guide walks through installing Stem, registering tasks, enqueueing work, and operating a worker/beat process locally.

## Prerequisites

- Dart 3.3+
 - Redis 7+ (for production-style testing)
 - Postgres 14+ (optional: enables the Postgres result backend & scheduler)
- Node.js 18+ (for the CLI and Docusaurus docs site)

The repository already contains in-memory adapters for local experimentation, so you can start without Redis while learning the APIs.

## Installing Stem

Add Stem to your Dart package:

```bash
dart pub add stem
```

The package exposes contracts, registry helpers, broker/backends, and CLI utilities from `package:stem/stem.dart`.

## Registering Tasks

Create a task handler by implementing `TaskHandler` or using `FunctionTaskHandler` for isolate-friendly entrypoints.

```dart
import 'package:stem/stem.dart';

class EmailTask implements TaskHandler<void> {
  @override
  String get name => 'email.send';

  @override
  TaskOptions get options => const TaskOptions(
        maxRetries: 5,
        softTimeLimit: Duration(seconds: 10),
        hardTimeLimit: Duration(seconds: 20),
      );

  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    // TODO: integrate with email provider
    context.progress(0.5);
    context.progress(1.0);
  }
}
```

Register handlers with `SimpleTaskRegistry` and share the registry with both the producer and worker processes.

```dart
final registry = SimpleTaskRegistry()
  ..register(EmailTask());
```

## Configuring a Stem Client

Construct a `StemConfig` from environment variables or instantiate manually. The config controls broker/backend URLs, default queue, prefetch multiplier, and default retry limit.

```dart
final config = StemConfig.fromEnvironment();
final broker = await RedisStreamsBroker.connect(config.brokerUrl);

final backend = switch (config.resultBackendUrl) {
  final url when url != null && url.startsWith('postgres') =>
    await PostgresResultBackend.connect(url, applicationName: 'stem-dev'),
  final url when url != null =>
    await RedisResultBackend.connect(url),
  _ => InMemoryResultBackend(),
};

final scheduleStore = switch (config.scheduleStoreUrl) {
  final url when url != null && url.startsWith('postgres') =>
    await PostgresScheduleStore.connect(url, applicationName: 'stem-dev'),
  final url when url != null =>
    await RedisScheduleStore.connect(url),
  _ => InMemoryScheduleStore(),
};

final stem = Stem(broker: broker, registry: registry, backend: backend);
```

For quick experiments you can rely on the in-memory implementations:

```dart
final broker = InMemoryBroker();
final backend = InMemoryResultBackend();
```

Both `PostgresResultBackend.connect` and `PostgresScheduleStore.connect`
create the required tables automatically when they are missing, so you can
point the adapters at an empty database during local development or CI.

### StemConfig Environment Variables

`StemConfig.fromEnvironment` reads the standard `STEM_*` variables shared by the CLI, producers, and workers:

| Variable | Purpose |
| --- | --- |
| `STEM_BROKER_URL` | Broker connection string (`redis://` or `rediss://`) |
| `STEM_RESULT_BACKEND_URL` | Result backend connection string (`redis://`, `rediss://`, or `postgres://`) |
| `STEM_SCHEDULE_STORE_URL` | Schedule store connection (`redis://`/`postgres://`, defaults to broker when omitted) |
| `STEM_DEFAULT_QUEUE` | Default queue name for tasks without explicit routing |
| `STEM_PREFETCH_MULTIPLIER` | Prefetch factor relative to worker concurrency |
| `STEM_DEFAULT_MAX_RETRIES` | Global fallback retry limit |
| `STEM_SIGNING_KEYS` / `STEM_SIGNING_ACTIVE_KEY` | HMAC signing secrets and active key |
| `STEM_SIGNING_PUBLIC_KEYS` / `STEM_SIGNING_PRIVATE_KEYS` | Ed25519 verify/sign key material |
| `STEM_SIGNING_ALGORITHM` | `hmac-sha256` (default) or `ed25519` |
| `STEM_TLS_CA_CERT` | Custom CA bundle for TLS handshakes |
| `STEM_TLS_CLIENT_CERT` / `STEM_TLS_CLIENT_KEY` | Mutual TLS credentials |
| `STEM_TLS_ALLOW_INSECURE` | Set to `true` to temporarily bypass certificate validation |

### Signing & TLS Guardrails

Producers should construct a `PayloadSigner` from the config and pass it into `Stem`. Workers should use the same configuration to verify signatures.

```dart
final signingConfig = config.signing;
final producerSigner = PayloadSigner.maybe(signingConfig);
final workerSigner = PayloadSigner.maybe(signingConfig);

if (producerSigner == null) {
  // Signing disabled; continue without signatures.
}

final stem = Stem(
  broker: broker,
  registry: registry,
  backend: backend,
  signer: producerSigner,
);

final worker = Worker(
  broker: broker,
  registry: registry,
  backend: backend,
  signer: workerSigner,
);
```

If a producer boots with an incomplete configuration (for example, the active Ed25519 key lacks a private key), Stem logs a warning and `Stem.enqueue` throws before publishing any messages. Workers automatically dead-letter tampered envelopes with a `signature-invalid` reason and record the failure in the result backend.

When connecting to TLS-enabled brokers or backends, use `rediss://` URLs together with the `STEM_TLS_*` variables. Failed handshakes emit warnings containing the host, certificate paths, and a reminder that `STEM_TLS_ALLOW_INSECURE=true` can be used temporarily for debugging.

#### Generate TLS Assets for Redis & HTTP endpoints

Use the automation script to bootstrap a private certificate authority plus
server/client certificates:

```bash
# SANs can include multiple DNS entries (comma-separated)
scripts/security/generate_tls_assets.sh certs stem.local,redis,api.localhost
```

This creates `ca.crt`, `server.crt`, `server.key`, `client.crt`, and
`client.key`. Point Stem services at the generated files:

```bash
export STEM_TLS_CA_CERT=/certs/ca.crt
export STEM_TLS_CLIENT_CERT=/certs/client.crt
export STEM_TLS_CLIENT_KEY=/certs/client.key
```

The enqueuer example also enables HTTPS automatically when
`ENQUEUER_TLS_CERT` / `ENQUEUER_TLS_KEY` are set. Use the same assets to run the
HTTP API over TLS:

```bash
export ENQUEUER_TLS_CERT=/certs/server.crt
export ENQUEUER_TLS_KEY=/certs/server.key
export ENQUEUER_TLS_CLIENT_CA=/certs/ca.crt # optional mutual TLS
```

- `server.crt`/`server.key` stay with the Redis instance and the HTTPS enqueuer
  service so they can terminate TLS and assert their identity to clients.
- `client.crt`/`client.key` are mounted by Stem producers and workers when
  mutual TLS is enabled (`STEM_TLS_CLIENT_CERT`/`STEM_TLS_CLIENT_KEY`), allowing
  Redis to reject unauthenticated connections.
- `ca.crt` is distributed to every Stem process (via `STEM_TLS_CA_CERT` and
  optionally `ENQUEUER_TLS_CLIENT_CA`) so they trust the server certificates
  without disabling verification.

With Redis configured via `--port 0 --tls-port 6379 --tls-auth-clients yes`,
plaintext connections are refused and both the enqueue API and workers connect
securely using the generated credentials.

## Enqueueing Tasks

```dart
final taskId = await stem.enqueue(
  'email.send',
  args: {'recipient': 'ops@example.com'},
  headers: {'tenant': 'billing'},
  options: const TaskOptions(queue: 'notifications'),
);
print('queued task $taskId');
```

Stem persists the envelope via the broker and records an initial `queued` status in the result backend.

## Running a Worker

Workers coordinate task execution, isolate pooling, heartbeats, and retry workflows.

```dart
final worker = Worker(
  broker: broker,
  registry: registry,
  backend: backend,
  consumerName: 'worker-1',
  concurrency: 4,
  prefetchMultiplier: 2,
);

await worker.start();
```

Behind the scenes the worker maintains a task isolate pool, enforces soft/hard time limits, emits heartbeats, and records task lifecycle metrics.

Use `await worker.shutdown()` for graceful termination.

## Scheduling Tasks

Stem ships a Beat scheduler that reads schedule definitions from Redis (or the
in-memory store in examples). You can manage schedules programmatically or via
the CLI.

```dart
final scheduleStore = InMemoryScheduleStore();
final beat = Beat(
  store: scheduleStore,
  broker: broker,
  lockStore: InMemoryLockStore(),
  tickInterval: const Duration(seconds: 1),
);

await scheduleStore.upsert(
  ScheduleEntry(
    id: 'send-daily-digest',
    taskName: 'email.send_digest',
    queue: 'notifications',
    spec: 'cron:0 8 * * *', // every day at 08:00
    args: {'plan': 'premium'},
    jitter: const Duration(minutes: 5),
  ),
);

await beat.start();
```

The beat instance polls `ScheduleStore.due`, applies optional jitter, and enqueues
tasks through the broker. Pair it with `stem schedule` for operators:

```bash
# Inspect current schedules
stem schedule list

# Dry-run the next few fire times
stem schedule dry-run --id send-daily-digest --count 3

# Apply definitions from a YAML file
stem schedule apply --file schedules.yaml --yes
```

For production, run at least two beat instances pointing at the same schedule
store so they can fail over gracefully.

### Canvas primitives

Stem’s canvas layer makes it easy to compose tasks into chains, groups, and
chords. Instantiate `Canvas` with the same broker/backend you give to Stem:

```dart
final canvas = Canvas(
  broker: broker,
  backend: backend,
  registry: registry,
);

// Chain: A -> B -> C
final chainId = await canvas.chain([
  task('profile.fetch', args: {'userId': userId}),
  task('profile.enrich'),
  task('profile.cache'),
]);

// Group: run tasks in parallel and get a group id back
final groupId = await canvas.group([
  task('report.generate', args: {'region': 'us'}),
  task('report.generate', args: {'region': 'eu'}),
]);

// Chord: group with callback when all succeed
await canvas.chord(
  body: [
    task('image.resize', args: {'size': '1x'}),
    task('image.resize', args: {'size': '2x'}),
  ],
  callback: task('image.publish'),
);
```

Group/chord completions are tracked through the result backend. Use
`ResultBackend.getGroup` to observe progress or `stem observe metrics` to watch
canvas-related counters.

## CLI Utilities

The `stem` CLI wraps observability commands, schedule helpers, and DLQ management:

```bash
stem observe metrics
stem dlq list --queue default
stem dlq replay --queue default --limit 5 --yes
stem health --broker rediss://redis:6380
```

The CLI automatically reads connection details from the standard `StemConfig` environment variables.

`stem health` performs a quick connectivity check against the configured broker and result backend. TLS-specific failures include certificate metadata and hints for enabling `STEM_TLS_ALLOW_INSECURE=true` during troubleshooting.

## Example Application

Two runnable examples live under `examples/`:

- `examples/monolith_service` – a single Dart service exposing an HTTP endpoint that enqueues tasks and starts an in-process worker & beat.
- `examples/microservice` – separate enqueue API and worker package communicating through Redis.

See each example’s README for setup commands. The repository CI runs their smoke tests to guarantee they remain functional.

## Next Steps

- Read the [Operations Guide](operations-guide.md) for deployment and troubleshooting practices.
- Review the [Scaling Playbook](scaling-playbook.md) when planning horizontal expansion.
- Explore the `test/` suite for practical patterns around retries, DLQ handling, and isolate-aware task execution.
