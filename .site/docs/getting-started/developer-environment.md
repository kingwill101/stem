---
title: Connect to Infrastructure
sidebar_label: Infrastructure
sidebar_position: 3
slug: /getting-started/developer-environment
---

Move from a process-local demo to **three separate processes**: a producer, a
worker, and a result observer. Start with one broker/backend combination before
adding routing, recurring schedules, or autoscaling.

This tutorial uses Redis for both delivery and results. It demonstrates the
current source API; check your resolved package's documentation if you are using
an older release.

## 1. Start a development Redis instance

In a separate terminal:

```bash
docker run --rm --name stem-redis-demo \
  -p 127.0.0.1:6379:6379 redis:7-alpine \
  redis-server --appendonly yes
```

This binds Redis to localhost and enables AOF inside the container. It is
**disposable development storage**: `--rm` removes the container on exit, and
there is no mounted data volume. For retained deployments, configure durable
storage, backups, access controls, and TLS separately. Do not expose an
unauthenticated development Redis port publicly.

Use the same connection settings in every terminal that runs the example:

```bash
export STEM_BROKER_URL=redis://127.0.0.1:6379/0
export STEM_RESULT_BACKEND_URL=redis://127.0.0.1:6379/1
export STEM_NAMESPACE=infrastructure-demo
```

The different Redis database numbers separate queue keys from result keys in
this single-instance example. They are not independent failure domains.
Redis Cluster deployments need a different database/namespace strategy.

## 2. Create the application

```bash
dart create -t console infrastructure_demo
cd infrastructure_demo
dart pub add stem stem_redis
```

If you are testing unreleased source, use compatible local path dependencies
instead of mixing current examples with older published packages.

Save the following as `bin/infrastructure_demo.dart`. All three commands use
the same typed task definition, queue defaults, broker, and backend. Creating
a client does not start a worker.

```dart title="bin/infrastructure_demo.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/infrastructure.dart#infrastructure-main

```

The same example is checked into
`packages/stem/example/docs_snippets/lib/infrastructure.dart`. From a repository
checkout, run it in the `docs_snippets` package after `dart pub get`.

## 3. Enqueue, process, and read the result

Run these commands in order. They intentionally use separate Dart processes:

```bash
# Producer: enqueues one task, prints its ID, and exits.
dart run bin/infrastructure_demo.dart enqueue

# Worker: processes queued tasks, then stops after an idle window.
dart run bin/infrastructure_demo.dart work

# Observer: replace TASK_ID with the ID printed by the producer.
dart run bin/infrastructure_demo.dart result TASK_ID
```

Expected result: `42`. The worker is a **one-shot drain**, not a daemon. Its
idle window is a local observation, not proof that every queue is globally
empty. Delayed work may require another invocation.

The worker budget stops admission; it does not forcibly interrupt an inline
handler or a database operation that is already running. Do not call
`worker.start()` before `worker.runUntilIdle()`, and keep client-owned stores
open until the worker has finished draining.

For a continuously running service, use an application-owned worker lifecycle
and a process supervisor. See
[Programmatic workers](../workers/programmatic-integration.md) rather than
wrapping this batch command in an unbounded loop.

## 4. Check configuration before scaling

| Symptom | Check |
| --- | --- |
| Enqueue succeeds, but no work runs | A worker process is running; it uses the same broker URL and subscribes to the selected queue |
| Worker logs an unknown task | That worker registers `infrastructure.double` with a compatible definition |
| Work completes, but the observer finds no result | Producer, worker, and observer use the same result backend and namespace; retention has not expired |
| Results appear more than once externally | The side effect needs an idempotency key; leases and acknowledgements do not provide exactly-once effects |
| A workflow does not survive restart | In addition to the broker/backend, its workflow store must be persistent and the definitions must be re-registered |

Changing an environment variable alone does not create adapters. This example
reads the URLs explicitly and passes `StemRedisAdapter` to `StemClient.fromUrl`.
To use PostgreSQL, add its package and adapter registration too.

## 5. Add one operational feature at a time

- **Routing:** keep producer rules and worker subscriptions aligned. See
  [Routing](../core-concepts/routing.md).
- **Recurring jobs:** a schedule entry still needs a running scheduler to
  publish due tasks. See [Beat guide](../scheduler/beat-guide.md).
- **Visibility:** observe queue counts, retained results, and worker health
  before changing concurrency. See [Observe & Operate](./observability-and-ops.md).
- **Recovery:** test process termination, lease expiry, and idempotent
  redelivery against the selected adapter.
- **Workflow persistence:** use the
  [workflow path](../workflows/getting-started.md), not task-result storage alone.

Signals run in the process that emits them. If another service needs durable
notifications, build that integration explicitly; an in-process listener is
not a persisted event stream.

For deployment tradeoffs, continue with [Broker caveats](../brokers/caveats.md)
and the [Production checklist](./production-checklist.md).
