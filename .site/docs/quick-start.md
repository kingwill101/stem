---
id: quick-start
title: Quick Start
sidebar_label: Quick Start
---

This walkthrough spins up Stem end-to-end in minutes.

## 1. Clone & Bootstrap

```bash
git clone <your-fork-url>
cd stem
``` 

## 2. Run the Docker Compose Stack

The OTLP metrics example ships with a collector and worker wired together.

```bash
cd examples/otel_metrics
docker compose up --build
```

This launches:

- **collector** – OpenTelemetry Collector forwarding metrics to Jaeger & logs
- **jaeger-ui** – Jaeger all-in-one UI at [http://localhost:16686](http://localhost:16686)
- **worker** – Stem worker enqueueing demo tasks every second

Watch the collector logs for `stem.*` metrics and inspect traces in Jaeger.

## 3. Explore the CLI Locally

Open a new terminal and install dependencies:

```bash
dart pub get
```

Run the in-memory examples (no Docker required):

```bash
cd examples/monolith_service
dart run bin/service.dart
```

In another terminal:

```bash
curl -X POST http://localhost:8080/enqueue -d '{"name":"Ada"}'
```

Observe worker logs and query task status via the service API.

## 4. Next Steps

- Read the [Developer Guide](developer-guide.md) for details on registering
  tasks, starting workers, and enabling observability.
- Review the [Operations Guide](operations-guide.md) and
  [Broker Comparison](broker-comparison.md) before deploying.
- Check out the [Scaling Playbook](scaling-playbook.md) when sizing clusters.

## Embed Stem in Your App

Once you are comfortable with the CLI flow, wire Stem directly into your
application service:

```dart
import 'package:stem/stem.dart';

Future<void> main() async {
  final config = StemConfig.fromEnvironment();

final broker = await RedisStreamsBroker.connect(
  config.brokerUrl,
  tls: config.tls,
);

final backend = switch (config.resultBackendUrl) {
  final url when url != null && url.startsWith('postgres') =>
    await PostgresResultBackend.connect(url, applicationName: 'stem-app'),
  final url when url != null =>
    await RedisResultBackend.connect(url, tls: config.tls),
  _ => InMemoryResultBackend(),
};

final scheduleStore = switch (config.scheduleStoreUrl) {
  final url when url != null && url.startsWith('postgres') =>
    await PostgresScheduleStore.connect(url, applicationName: 'stem-beat'),
  final url when url != null =>
    await RedisScheduleStore.connect(url),
  _ => InMemoryScheduleStore(),
};

  final registry = SimpleTaskRegistry()..register(EmailTask());
  final stem = Stem(
    broker: broker,
    registry: registry,
  backend: backend,
  signer: PayloadSigner.maybe(config.signing),
);

final worker = Worker(
  broker: broker,
  registry: registry,
  backend: backend,
  concurrency: 4,
  signer: PayloadSigner.maybe(config.signing),
);

final beat = Beat(
  broker: broker,
  store: scheduleStore,
  lockStore: InMemoryLockStore(),
);

  await worker.start();
  await stem.enqueue('email.send', args: {'recipient': 'ops@example.com'});
}
```

The `EmailTask` handler mirrors the basic example in the developer guide; swap
in your own task definitions as needed.

Producers will emit a warning and throw immediately if the signing configuration
is incomplete (for example, `STEM_SIGNING_PRIVATE_KEYS` is missing the active
Ed25519 key). Workers that encounter tampered payloads fail fast, log the event,
and move the envelope to the dead-letter queue.

Run `stem health` in your deployment environment to confirm broker/back-end
connectivity and TLS handshakes before rolling out new services.

### Spin Up Local Dependencies

Need Postgres or Redis for integration testing? The repository ships with a
Compose stack under `docker/testing/`:

```bash
docker compose -f docker/testing/docker-compose.yml up -d
export STEM_TEST_POSTGRES_URL=postgres://postgres:postgres@127.0.0.1:65432/stem_test
export STEM_TEST_REDIS_URL=redis://127.0.0.1:56379/0
dart test test/integration
docker compose -f docker/testing/docker-compose.yml down
```

Suites automatically skip when the environment variables are missing, so you can
opt in only when exercising adapters against live services.

### Secure the Stack

Bootstrap TLS certificates for both Redis and the enqueue HTTP API with the
automation script:

```bash
scripts/security/generate_tls_assets.sh certs stem.local,redis,api.localhost
```

Mount the generated files and set the corresponding environment variables:

```bash
export STEM_TLS_CA_CERT=/certs/ca.crt
export STEM_TLS_CLIENT_CERT=/certs/client.crt
export STEM_TLS_CLIENT_KEY=/certs/client.key
export ENQUEUER_TLS_CERT=/certs/server.crt
export ENQUEUER_TLS_KEY=/certs/server.key
```

- `server.crt`/`server.key` live with Redis and the enqueue API container to
  terminate TLS and prove service identity.
- `client.crt`/`client.key` are mounted by Stem producers/workers when
  `STEM_TLS_CLIENT_CERT` and `STEM_TLS_CLIENT_KEY` are set so Redis accepts only
  authenticated clients.
- `ca.crt` is copied to every Stem process via `STEM_TLS_CA_CERT` (and
  `ENQUEUER_TLS_CLIENT_CA` for HTTPS) so certificate validation stays enabled.

Redis should be launched with `--port 0 --tls-port 6379 --tls-auth-clients yes`
to refuse plaintext connections. Use `stem health` after deployment to verify
both Redis and HTTPS endpoints negotiate successfully.

### Schedule & Compose Work

Run the scheduler alongside your worker to keep periodic jobs flowing:

```dart
final scheduleStore = InMemoryScheduleStore();
final beat = Beat(
  store: scheduleStore,
  broker: broker,
  lockStore: InMemoryLockStore(),
);

await scheduleStore.upsert(
  ScheduleEntry(
    id: 'cleanup-temp-files',
    taskName: 'maintenance.cleanup',
    spec: 'every:5m',
    queue: 'maintenance',
  ),
);

await beat.start();
```

Operators can manage schedules with the CLI:

```bash
stem schedule list
stem schedule dry-run --id cleanup-temp-files --count 5
```

Use the canvas helpers when you need to chain or fan-out tasks:

```dart
final canvas = Canvas(
  broker: broker,
  backend: backend,
  registry: registry,
);

await canvas.chord(
  body: [
    task('image.resize', args: {'size': '1x'}),
    task('image.resize', args: {'size': '2x'}),
  ],
  callback: task('image.publish'),
);
```

Group/chord completion state is visible via the result backend (`stem observe
metrics`, `stem dlq`, or `ResultBackend.getGroup`) just like single tasks.
