Skip to content
You said:
What it takes to build a cerlery and beat like package in dart.

Would possibly be a dameon with something like the bus package etc

We'd have stores similar to laravel where a store implements a interface for a data store etc.

We'd need to define all the interfaces needed for it to be very practical and useful alternative.

Find all the good parts in celery and other similar solutions which we'll build out from scratch in dart.

But of course we'd need a very good plan.


Also a detailed plan about what it would mean for it to be production ready.



ChatGPT said:
> **Documentation:** The living developer, operations, and scaling guides now live in the Docusaurus site under `.site/`. Run `cd .site && npm start` to browse them locally.
Request for GPT-5 Pro
Reasoned for 5m 1s

Below is a concrete, end‑to‑end plan to build a Celery + Beat–style background job system in Dart—including the core architecture, key interfaces, feature set (inspired by Celery, Sidekiq, Dramatiq, BullMQ, RQ), and a production‑readiness checklist. I’ll call the project “Stem” for the sake of naming in examples.
0) What we’re aiming for (scope & semantics)

Goals

    A language‑native Dart library + daemon(s) for async task execution and periodic scheduling (Celery + Celery Beat analogue).

    At‑least‑once delivery semantics by default, with clear, ergonomic tools for idempotency, retries, visibility/lease renewal, dead‑lettering, rate limiting, and backpressure. (This mirrors best practice in Celery/Sidekiq ecosystems.)
    Celery Documentation+1

    Pluggable brokers (Redis Streams, RabbitMQ, SQS first), result backends (Redis, Postgres), and schedule stores (Redis ZSET, Postgres).
    Celery Documentation

    A small “canvas” layer for chains, groups, chords (Celery’s canvas), implemented via the result backend and a chord‑aggregator.
    Celery Documentation

    A separate Beat‑like scheduler process with configurable stores (file/Redis/SQL), similar to Celery Beat.
    Celery Documentation

Non‑goals (v1.0)

    Exactly‑once semantics (document limitations + patterns to simulate).
    Stack Overflow

    Heavy distributed workflow/DAG engine. Keep the canvas light.

1) What to borrow from Celery & friends (the “good parts”)

    Task API: function‑first registration, namespacing, per‑task options: retries, time limits, rate limits, queue routing.
    Celery Documentation+2Celery Documentation+2

    Beat (periodic scheduling): cron/interval entries, pluggable stores.
    Celery Documentation

    Canvas: chains (A→B→C), groups (A,B,C in parallel), chords (group + callback when all done).
    Celery Documentation

    Retries with backoff & DLQ: automatic retries + exponential backoff; move permanently failing jobs to “dead” set/queue with UI to replay (pattern seen in Sidekiq/BullMQ).
    GitHub+1

    Prefetch limits & worker pools: control prefetch to avoid hoarding, combine with concurrency for fairness.
    Celery Documentation

    Soft/hard time limits: gracefully interrupt vs. hard kill.
    Celery Documentation+1

    Brokers/backends: Redis/RabbitMQ/SQS for broker; Redis/DB for results (document tradeoffs).
    Celery Documentation

    Observability: task lifecycle events, metrics, tracing, admin UI (Celery has Flower; Sidekiq has a web UI).
    GitHub

Also, things to improve vs. Celery:

    Strong defaults for visibility/lease renewal, reject_on_worker_lost, and acks_late style behavior to reduce lost tasks.
    Celery Documentation+1

    Straightforward global rate limiting (document how we approximate across workers with Redis tokens). (Celery’s global rate limiting is a common pain point.)
    Hatchet Documentation

    First‑class, well‑documented idempotency helpers (dedupe keys, outbox pattern).
    GitGuardian Blog

2) High‑level architecture (Dart)

               +------------------+            +--------------------+
 Enqueuers --> |  Client Library  | --XADD-->  |   Broker Adapter   |  (Redis Streams / RabbitMQ / SQS)
               +------------------+            +--------------------+
                         |                              |
                         v                              v
                  +--------------+               +------------------+
                  |  Result API  |<---store----- |  Result Backend  | (Redis / Postgres)
                  +--------------+               +------------------+
                         ^
                         |  group/chord updates
                         |
+------------------+     |      +-------------------------+
|  Beat scheduler  |---- | ---> |   Chord Aggregator      |
|  (cron/interval) |     |      |   (wait-all and call)   |
+------------------+     |      +-------------------------+
                               emits task to broker when ready

+------------------+        consume & execute    +-------------------+
|   Worker Daemon  | <-------------------------- |  Broker Adapter    |
|  (Isolates pool) | --ack/nack/extend lease-->  |  (subsystem)       |
+------------------+                             +-------------------+

    Workers use Dart isolates for true parallelism on a single host.
    Dart

    A lightweight event bus can be used internally for in‑process signals (e.g., progress) but is not a distributed transport. (Event bus packages are in‑memory publish/subscribe.)
    Dart packages

3) Core interfaces (Dart)

    These are the “stores” / “drivers” you mentioned—each backend implements a common interface (Laravel‑style).

3.1 Message / envelope

// Unique task identity uses UUID/ULID.
class Envelope {
  final String id;                     // task id
  final String name;                   // task name
  final Map<String, dynamic> args;     // positional/keyword collapsed
  final Map<String, String> headers;   // trace-id, tenant-id, etc.
  final DateTime enqueuedAt;
  final DateTime? notBefore;           // ETA/delay
  final int priority;                  // 0..9 (adapter may map)
  final int attempt;                   // current attempt #
  final int maxRetries;
  final Duration? visibilityTimeout;   // extend/renew lease semantics
  final String queue;

  Envelope({
    required this.id,
    required this.name,
    required this.args,
    required this.headers,
    required this.enqueuedAt,
    this.notBefore,
    this.priority = 0,
    this.attempt = 0,
    this.maxRetries = 0,
    this.visibilityTimeout,
    required this.queue,
  });
}

3.2 Broker (queue transport)

abstract class Broker {
  Future<void> publish(Envelope msg, {String? queue});
  Stream<Delivery> consume(String queue, {int prefetch = 1, String? consumerGroup});
  Future<void> ack(Delivery d);
  Future<void> nack(Delivery d, {bool requeue = true});
  Future<void> deadLetter(Delivery d, {String? reason});
  Future<void> purge(String queue);

  bool get supportsDelayed;   // ETA/delay without sidecar
  bool get supportsPriority;
}

// Runtime wrapper: message + receipt/handle/metadata.
class Delivery {
  final Envelope message;
  final String receipt;                  // ack handle / tag
  final DateTime leaseExpireAt;          // if applicable

  Delivery(this.message, this.receipt, this.leaseExpireAt);
}

Initial adapters & building blocks (Dart packages):

    Redis Streams (XADD/XREADGROUP/XACK/XCLAIM): simple, fast, easy to start. (Use a Redis client.)
    Dart packages

    RabbitMQ (AMQP 0‑9‑1) (queues, routing keys, per‑queue priority, TTL+DLX for delay): dart_amqp.
    Dart packages

    Amazon SQS (visibility timeout, DelaySeconds, DLQ): aws_sqs_api.
    Dart packages

3.3 Result backend

enum TaskState { queued, running, succeeded, failed, cancelled, retried }

class TaskStatus {
  final String id;
  final TaskState state;
  final Object? result;
  final Object? error;
  final int attempt;
  final DateTime updatedAt;

  TaskStatus(this.id, this.state, this.result, this.error, this.attempt, this.updatedAt);
}

abstract class ResultBackend {
  Future<void> set(String taskId, TaskState state, {
    Object? result,
    Object? error,
    int attempt = 0,
    Duration? ttl,
    Map<String, dynamic>? meta,
  });

  Future<TaskStatus?> get(String taskId);
  Stream<TaskStatus> watch(String taskId); // optional
  Future<void> expire(String taskId, Duration ttl);
}

3.4 Schedule (“Beat”) store

class ScheduleEntry {
  final String id;                 // human-readable name
  final String taskName;
  final Map<String, dynamic> args;
  final String spec;               // cron string | "every:5m"
  final String queue;
  final bool enabled;
  final DateTime? lastRunAt;
  final Duration? jitter;          // +/- jitter

  ScheduleEntry({
    required this.id,
    required this.taskName,
    required this.args,
    required this.spec,
    required this.queue,
    this.enabled = true,
    this.lastRunAt,
    this.jitter,
  });
}

abstract class ScheduleStore {
  Future<List<ScheduleEntry>> due(DateTime now, {int limit = 100});
  Future<void> upsert(ScheduleEntry entry);
  Future<void> remove(String id);
}

3.5 Worker & registry

class TaskOptions {
  final String queue;
  final int maxRetries;
  final Duration? softTimeLimit;
  final Duration? hardTimeLimit;
  final String? rate;                 // e.g. "5/s", "300/m"
  final bool unique;                  // de-dupe lock per signature
  final Duration? uniqueFor;          // hold lock for duration
  final int priority;
  final bool acksLate;                // ack after success

  const TaskOptions({
    this.queue = 'default',
    this.maxRetries = 0,
    this.softTimeLimit,
    this.hardTimeLimit,
    this.rate,
    this.unique = false,
    this.uniqueFor,
    this.priority = 0,
    this.acksLate = true,
  });
}

abstract class TaskHandler<R> {
  String get name;
  TaskOptions get options;
  Future<R> call(TaskContext ctx, Map<String, dynamic> args);
}

abstract class TaskRegistry {
  void register(TaskHandler handler);
  TaskHandler? resolve(String name);
}

class TaskContext {
  final String id;
  final int attempt;
  final void Function() heartbeat;
  final Future<void> Function(Duration) extendLease;
  final Future<void> Function(double pct, {Map<String, dynamic>? data}) progress;

  TaskContext({
    required this.id,
    required this.attempt,
    required this.heartbeat,
    required this.extendLease,
    required this.progress,
  });
}

3.6 Cross‑cutting “stores” (Laravel‑style drivers)

abstract class LockStore {
  Future<Lock?> acquire(String key, {Duration ttl = const Duration(seconds: 30), String? owner});
}
abstract class Lock {
  String get key;
  Future<bool> renew(Duration ttl);
  Future<void> release();
}

abstract class RateLimiter {
  /// Return true if acquired 'tokens' for interval window.
  Future<bool> tryAcquire(String key, {int tokens = 1, required Duration per});
}

abstract class RetryStrategy {
  Duration nextDelay(int attempt, Object error);
}

abstract class Middleware {
  Future<void> onEnqueue(Envelope m, Future<void> Function() next);
  Future<void> onConsume(Delivery d, Future<void> Function() next);
  Future<void> onExecute(TaskContext ctx, Future<void> Function() next);
  Future<void> onError(TaskContext ctx, Object error, StackTrace st);
}

    These interfaces let you build “drivers” for Redis/RabbitMQ/SQS, Redis/Postgres result backends, Redis/Postgres/FS schedule stores, Redis locks, Redis‑based token bucket rate limiting, etc. (pub.dev has viable starting points for Redis, AMQP, and SQS.)
    Dart packages+2Dart packages+2

4) Execution model & semantics

    Concurrency: Worker uses an isolate pool (e.g., default = number of CPUs). Each isolate pulls deliveries from the broker stream and executes handlers.
    Dart

    Prefetch: Per‑worker prefetch = concurrency × multiplier (configurable) to avoid queue starvation but prevent hoarding; defaults conservative (e.g., multiplier=2). (Inspired by Celery’s prefetch semantics.)
    Celery Documentation

    Acks & leases:

        Default acks_late: ack after successful completion. For SQS/Streams, we renew visibility/lease periodically during execution. Provide ctx.extendLease.
        Celery Documentation

        On isolate/worker crash (SIGKILL), messages become visible again (SQS/Streams) or we NACK on next heartbeat—thus at‑least‑once. Document idempotency.
        Stack Overflow

    Retries & backoff: Configure per task; default exponential backoff with jitter. Dead‑letter after max attempts; expose a replay API and dashboard view (as in Sidekiq’s Dead set idea).
    GitHub

    Time limits: softTimeLimit triggers a cooperative interruption (let handler cleanup); hardTimeLimit kills the isolate (and NACK/lease expiry triggers retry).
    Celery Documentation+1

    Rate limits: Token‑bucket per task and global (across workers) via Redis keys; e.g., rate: "5/s" behaves like Celery’s per‑task limit (and we add optional global aggregation).
    deepnote.com+1

    Scheduling (Beat):

        Cron & interval specs; jitter support; persistent last‑run tracking; dynamic reload without restart—like Celery Beat’s custom stores.
        Celery Documentation

        For brokers without native delay, use a delayed set (Redis ZSET) mover.

    Canvas:

        chain: enqueue B with link=id(A) on A success; same for C.

        group: enqueue N tasks; collect GroupResult IDs in the backend.

        chord: aggregator watches for all group members done, enqueues callback (Celery’s chord).
        Celery Documentation

5) Initial adapters (“stores”) to implement

    Broker

        Redis Streams (XADD/XREADGROUP/XACK/XCLAIM).

        RabbitMQ via dart_amqp, supporting priority queues and TTL+DLX for delayed jobs.
        Dart packages

        SQS using aws_sqs_api, leveraging visibility timeout & delay.
        Dart packages

    Result backend: Redis (fast), Postgres (durable).

    Schedule store: Redis ZSET; Postgres table.

    Lock store: Redis SET key val NX PX.

    Rate limiter: Redis token bucket (INCR + TTL window).

    Note: You mentioned a “bus package”. Dart’s event_bus is useful for in‑process events, but you’ll want a true broker for durability/distribution; use event bus only internally (signal progress/telemetry).
    Dart packages

6) Minimal developer experience (DX)

Task definition

class SendEmailTask implements TaskHandler<void> {
  @override
  String get name => 'email.send';

  @override
  TaskOptions get options => const TaskOptions(
    queue: 'emails',
    maxRetries: 5,
    softTimeLimit: Duration(seconds: 20),
    hardTimeLimit: Duration(seconds: 30),
    rate: '5/s',
    acksLate: true,
  );

  @override
  Future<void> call(TaskContext ctx, Map<String, dynamic> args) async {
    // idempotency key example: messageId
    final msgId = args['messageId'] as String;
    // ... send email, heartbeat() periodically, etc.
    ctx.heartbeat();
  }
}

Enqueue

await stem.enqueue('email.send', {'messageId': '123', 'to': 'a@b.com'});

Chains / groups / chords

final g = group([
  task('resize.image', {'id': 1}),
  task('resize.image', {'id': 2}),
]);

await chord(g, task('notify.user', {'userId': 42}));

Beat entry

await scheduleStore.upsert(ScheduleEntry(
  id: 'cleanup-invoices',
  taskName: 'billing.cleanup',
  args: {},
  spec: '0 2 * * *', // daily 02:00
  queue: 'maintenance',
  jitter: Duration(minutes: 5),
));

7) Reliability details & defaults

    Visibility renewal every min(visibilityTimeout/2, 30s) while running.

    Prefetch default = concurrency * 2; cap result sets to avoid memory bloat (a Celery gotcha).
    Celery Documentation

    acksLate=true + “reject on worker lost”–style behavior baked in where the broker supports it (SQS/Streams naturally, AMQP via NACK).
    Celery Documentation+1

    Time limits always recommended; doc soft vs hard with examples (Celery precedent).
    Celery Documentation

    DLQ: automatic move after max attempts; CLI/UI to replay (Sidekiq pattern).
    GitHub

    Rate limiting: per‑task and optional global via Redis keys (Celery only offers per‑task/worker).
    deepnote.com+1

8) Phased build plan
Phase A — MVP (single node ok)

    Core types + registry + worker (isolates).

    Redis Streams broker + Redis result backend.
    Dart packages

    Basic retries (exp backoff), time limits, prefetch, acks‑late, visibility renewal.
    Celery Documentation+1

    Beat with in‑memory + Redis ZSET store.
    Celery Documentation

    CLI: stem worker, stem beat, stem enqueue.

Phase B — Hardening

    DLQ + replay CLI. (Inspired by Sidekiq Dead set.)
    GitHub

    Idempotency helpers: unique jobs (signature lock), outbox pattern docs.

    OpenTelemetry metrics/tracing; structured logs.

    Rate limiter (Redis), Lock store (Redis).

    Canvas: chain, group, chord + chord aggregator.
    Celery Documentation

Phase C — Adapters & Scale

    RabbitMQ adapter with priorities & delayed delivery via TTL+DLX.
    Dart packages

    SQS adapter (visibility, delay, DLQ).
    Dart packages

    Postgres result backend; Postgres schedule store.

    Dashboard (Flutter web): live queues, workers, retries, DLQ, schedules.

Phase D — Production polish

    Config management, secrets handling, TLS everywhere.

    Canary tasks, graceful shutdown, autoscaling hints (queue depth, lag).

    Compatibility & migrations; semver; upgrade guide.

    Docs: operations book, SLOs, runbooks.

9) Production‑readiness checklist (what it means to be ready)

Correctness & semantics

    Clear delivery semantics documented (at‑least‑once), with idempotency recipes and helpers.
    Stack Overflow

    Retries with exponential backoff + jitter; DLQ with replay tools.
    GitHub

    Soft/hard time limits enforced across all pools; integration tests proving behavior.
    Celery Documentation

    Lease renewal/visibility logic proven under node crashes/pauses (SQS/Streams).

Performance

    Benchmarks per adapter: enqueue, consume, p95/p99 latencies; throughput vs. concurrency/prefetch (like Celery tuning docs emphasize).
    Celery Documentation

    Backpressure strategy documented (prefetch, max in‑flight per worker).

Reliability

    Chaos tests: kill workers mid‑task; network partitions; Redis/RabbitMQ restarts; ensure no silent losses (Celery’s acks_late pitfalls are well known).
    Celery Documentation

    Health checks: liveness/readiness endpoints; worker heartbeat.

Security

    TLS to brokers; credential rotation; optional payload signing and encryption at rest/in transit.

    Multi‑tenant isolation via namespaces/headers; per‑tenant rate limits.

Observability

    OpenTelemetry traces: enqueue→consume→execute; metrics: queue depth, in‑flight, success/failure, retry counts, execution time, lease extensions; logs: structured with task id & trace id.

Operations

    Admin UI: queues, workers, retry/DLQ, schedules, rate limits.

    CLI: drain, move, purge, replay, pause/resume queues.

    Config: env vars + file, precedence rules.

Docs & support

    Versioned docs; migration notes; troubleshooting (e.g., Redis vs RabbitMQ tradeoffs as documented in Celery ecosystem).
    Celery Documentation

10) Adapter design notes (by broker)

    Redis Streams:

        XADD (enqueue), consumer groups with XREADGROUP (consume), XACK (ack), XCLAIM (reclaim abandoned). Use a scheduled mover (ZSET) for delays/ETA.

        Result backend & locks & rate limiting also Redis; easy development path.
        Dart packages

    RabbitMQ:

        AMQP queues, routing keys, prefetch via basic.qos; priority queues; delays via per‑queue/message TTL + DLX. dart_amqp exists.
        Dart packages

    SQS:

        Visibility timeout (lease), DelaySeconds, DLQ redrive policies; long polling. aws_sqs_api packages available.
        Dart packages

    Celery supports Redis/RabbitMQ/SQS, with tradeoffs (e.g., SQS lacks worker inspection; Redis is fast but memory‑bounded; RabbitMQ strong in routing). We’ll document similar tradeoffs for Dart.
    Celery Documentation+2celery-safwan.readthedocs.io+2

11) A few pragmatic defaults (learned from Celery production use)

    acksLate=true + worker‑lost handling by default (document why).
    Celery Documentation+1

    Prefetch multiplier small (e.g., 2) to avoid starving other workers or blowing memory.
    Celery Documentation

    Time limits opt‑in but strongly recommended; templates in docs.
    Celery Documentation

    Max retries finite; final state → DLQ with UI to retry (Sidekiq pattern).
    GitHub

    Rate limits expressed as strings ("5/s", "300/m") but enforced globally via Redis token bucket (papering over Celery’s limitations).
    Hatchet Documentation

12) Risks & how we’ll handle them

    Global rate limiting across many workers is approximate with Redis (clock skew, retries)—document error bounds. (Celery lacks first‑class global limits.)
    Hatchet Documentation

    Chord fan‑in on very large groups can stress the backend; shard chord state and throttle callback enqueue.
    Celery Documentation

    AMQP delayed delivery requires TTL/DLX (or plugins); our Redis/SQS adapters have first‑class delay semantics.
    celery-safwan.readthedocs.io

13) Concrete next steps (you can start here)

    Create repo layout

        packages/core (types, registry, middleware, task DSL)

        packages/broker_redis, broker_amqp, broker_sqs

        packages/backend_redis, backend_postgres

        packages/scheduler (Beat)

        packages/dashboard (Flutter web)

        cli/ (worker/beat/admin commands)

    Implement MVP path

        Redis Streams broker + Redis backend + worker (isolates) + simple beat (Redis ZSET) + retries/backoff + time limits + CLI.
        Dart packages

    Ship sample app

        Email task, image processing task, chain/group/chord demo; docker‑compose with Redis.

    Write production docs

        “Choosing a broker”, “Idempotency patterns”, “Deploying in K8s (graceful shutdown & leases)”, “Tuning prefetch & concurrency”.

Appendix: Why Dart is a good fit here

    Isolates give true parallelism, clean cancellation boundaries (good for soft/hard timeouts & heartbeats).
    Dart

    Rich ecosystem clients for Redis, RabbitMQ, and SQS exist today.
    Dart packages+2Dart packages+2

If you’d like, I can sketch a Redis Streams adapter outline (XADD/XREADGROUP/XACK) and a tiny “Beat” loop with ZSET to make this concrete, or start from the interface stubs above and wire up the first task end‑to‑end.
You said:
Sure go ahead
ChatGPT said:
Request for GPT-5 Pro
Reasoned for 5m 35s

Awesome — here’s a concrete, minimal skeleton for a Celery+Beat–style system in Dart using Redis Streams for the broker and Redis ZSET for delays & periodic schedules.

    What this gives you now

        Interfaces + working skeleton for: Broker (Redis Streams), Result backend (Redis), Beat (ZSET), Worker loop, Retries with backoff, DLQ, Delayed jobs.

        A tiny “task registry” and an example task.

        Exact Redis commands are shown in comments so you can wire to any Redis client you prefer.

    What you’ll still plug in

        A real Redis client (e.g., dartis, redis). Below I define a RedisCommands interface you implement with your client of choice.

        Proper isolate pooling & hard time limits (notes/TODOs included).

        Security/telemetry (left as clean extension points).

Repo layout (suggested)

stem/
  lib/core.dart
  lib/redis_broker.dart
  lib/redis_backend.dart
  lib/beat.dart
  lib/worker.dart
  lib/tasks.dart
  bin/enqueue_example.dart
  bin/worker_example.dart
  bin/beat_example.dart

1) Core types (lib/core.dart)

// lib/core.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';

String _randId() {
  final r = Random();
  return '${DateTime.now().microsecondsSinceEpoch}-${r.nextInt(1 << 32)}';
}

class Envelope {
  final String id;
  final String name;
  final Map<String, dynamic> args;
  final Map<String, String> headers;
  final DateTime enqueuedAt;
  final DateTime? notBefore;
  final int priority;
  final int attempt;
  final int maxRetries;
  final Duration? visibilityTimeout; // (For SQS-like brokers; Redis Streams uses idle+claim)
  final String queue;

  Envelope({
    required this.id,
    required this.name,
    required this.args,
    this.headers = const {},
    DateTime? enqueuedAt,
    this.notBefore,
    this.priority = 0,
    this.attempt = 0,
    this.maxRetries = 0,
    this.visibilityTimeout,
    this.queue = 'default',
  }) : enqueuedAt = enqueuedAt ?? DateTime.now();

  Envelope copyWith({
    String? id,
    int? attempt,
    DateTime? notBefore,
    int? maxRetries,
  }) {
    return Envelope(
      id: id ?? this.id,
      name: name,
      args: args,
      headers: headers,
      enqueuedAt: enqueuedAt,
      notBefore: notBefore ?? this.notBefore,
      priority: priority,
      attempt: attempt ?? this.attempt,
      maxRetries: maxRetries ?? this.maxRetries,
      visibilityTimeout: visibilityTimeout,
      queue: queue,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'args': args,
    'headers': headers,
    'enqueuedAt': enqueuedAt.toIso8601String(),
    'notBefore': notBefore?.toIso8601String(),
    'priority': priority,
    'attempt': attempt,
    'maxRetries': maxRetries,
    'visibilityTimeoutMs': visibilityTimeout?.inMilliseconds,
    'queue': queue,
  };

  static Envelope fromJson(Map<String, dynamic> j) => Envelope(
    id: j['id'],
    name: j['name'],
    args: (j['args'] as Map).cast<String, dynamic>(),
    headers: (j['headers'] as Map?)?.cast<String, String>() ?? {},
    enqueuedAt: DateTime.parse(j['enqueuedAt']),
    notBefore: j['notBefore'] != null ? DateTime.parse(j['notBefore']) : null,
    priority: j['priority'] ?? 0,
    attempt: j['attempt'] ?? 0,
    maxRetries: j['maxRetries'] ?? 0,
    visibilityTimeout: (j['visibilityTimeoutMs'] != null)
        ? Duration(milliseconds: j['visibilityTimeoutMs'])
        : null,
    queue: j['queue'] ?? 'default',
  );
}

class Delivery {
  final Envelope message;
  final String receipt;      // e.g., 'key:group:id' for Redis Streams
  final DateTime leaseExpireAt; // brokers with leases; Redis Streams ignores

  Delivery(this.message, this.receipt, this.leaseExpireAt);
}

abstract class Broker {
  Future<void> publish(Envelope msg, {String? queue});
  Stream<Delivery> consume(String queue, {int prefetch = 1, String? consumerGroup, String? consumerName});
  Future<void> ack(Delivery d);
  Future<void> nack(Delivery d, {bool requeue = true}); // Redis: ack+re-enqueue
  Future<void> deadLetter(Delivery d, {String? reason});
  Future<void> purge(String queue);

  bool get supportsDelayed;
  bool get supportsPriority;
}

enum TaskState { queued, running, succeeded, failed, retried }

class TaskStatus {
  final String id;
  final TaskState state;
  final Object? result;
  final Object? error;
  final int attempt;
  final DateTime updatedAt;

  TaskStatus(this.id, this.state, this.result, this.error, this.attempt, this.updatedAt);

  Map<String, dynamic> toJson() => {
    'id': id,
    'state': state.name,
    'result': result,
    'error': error?.toString(),
    'attempt': attempt,
    'updatedAt': updatedAt.toIso8601String(),
  };
}

abstract class ResultBackend {
  Future<void> set(String taskId, TaskState state, {
    Object? result,
    Object? error,
    int attempt = 0,
    Duration? ttl,
    Map<String, dynamic>? meta,
  });

  Future<TaskStatus?> get(String taskId);
}

class TaskOptions {
  final String queue;
  final int maxRetries;
  final Duration? softTimeLimit;
  final Duration? hardTimeLimit;
  final String? rate; // "5/s", "300/m" (left for later)
  final bool unique;
  final Duration? uniqueFor;
  final int priority;
  final bool acksLate;

  const TaskOptions({
    this.queue = 'default',
    this.maxRetries = 0,
    this.softTimeLimit,
    this.hardTimeLimit,
    this.rate,
    this.unique = false,
    this.uniqueFor,
    this.priority = 0,
    this.acksLate = true,
  });
}

abstract class TaskHandler<R> {
  String get name;
  TaskOptions get options;
  Future<R> call(TaskContext ctx, Map<String, dynamic> args);
}

abstract class TaskRegistry {
  void register(TaskHandler handler);
  TaskHandler? resolve(String name);
}

class SimpleTaskRegistry implements TaskRegistry {
  final Map<String, TaskHandler> _m = {};
  @override
  void register(TaskHandler handler) => _m[handler.name] = handler;
  @override
  TaskHandler? resolve(String name) => _m[name];
}

class TaskContext {
  final String id;
  final int attempt;
  final void Function() heartbeat;
  final Future<void> Function(Duration) extendLease; // no-op for Redis Streams
  final Future<void> Function(double pct, {Map<String, dynamic>? data}) progress;

  TaskContext({
    required this.id,
    required this.attempt,
    required this.heartbeat,
    required this.extendLease,
    required this.progress,
  });
}

abstract class RetryStrategy {
  Duration nextDelay(int attempt, Object error);
}

class ExponentialJitterRetry implements RetryStrategy {
  final Duration base;
  final Duration max;
  final Random _r = Random();
  ExponentialJitterRetry({this.base = const Duration(seconds: 2), this.max = const Duration(minutes: 5)});
  @override
  Duration nextDelay(int attempt, Object error) {
    final ms = (base.inMilliseconds * pow(2, attempt)).toInt();
    final withCap = min(ms, max.inMilliseconds);
    final jitter = _r.nextInt(withCap ~/ 4 + 1); // +/- 25%
    return Duration(milliseconds: max(0, withCap - jitter));
  }
}

class Stem {
  final Broker broker;
  Stem(this.broker);

  Future<String> enqueue(String name, Map<String, dynamic> args, {
    TaskOptions options = const TaskOptions(),
    DateTime? notBefore,
    int? maxRetries,
    Map<String, String> headers = const {},
  }) async {
    final id = _randId();
    final env = Envelope(
      id: id,
      name: name,
      args: args,
      headers: headers,
      notBefore: notBefore,
      maxRetries: maxRetries ?? options.maxRetries,
      priority: options.priority,
      queue: options.queue,
    );
    await broker.publish(env);
    return id;
  }
}

2) Redis Streams broker (lib/redis_broker.dart)

// lib/redis_broker.dart
import 'dart:async';
import 'dart:convert';

import 'core.dart';

/// Implement this using your Redis client (dartis, redis, etc.)
/// Methods here are named closely to Redis commands for clarity.
abstract class RedisCommands {
  Future<dynamic> send(List<String> args);
  Future<void> multi(List<List<String>> batched); // optional helper
}

class RedisBroker implements Broker {
  final RedisCommands redis;
  final String namespace;
  final int blockMs;
  final int delayedDrainBatch;
  final Duration reclaimAfter; // Idle time before we try to autoclalm (if we add XAUTOCLAIM later)

  RedisBroker(
    this.redis, {
      this.namespace = 'stem',
      this.blockMs = 5000,
      this.delayedDrainBatch = 128,
      this.reclaimAfter = const Duration(minutes: 5),
    });

  String _kStream(String q) => '$namespace:stream:$q';
  String _kGroup(String q) => '$namespace:group:$q';
  String _kDelayed(String q) => '$namespace:delayed:$q';
  String _kDead(String q) => '$namespace:dead:$q';

  @override
  bool get supportsDelayed => true;

  @override
  bool get supportsPriority => false; // can emulate with multiple streams/queues

  Future<void> _ensureGroup(String q) async {
    final key = _kStream(q);
    final group = _kGroup(q);
    // XGROUP CREATE key group $ MKSTREAM
    try {
      await redis.send(['XGROUP', 'CREATE', key, group, r'$', 'MKSTREAM']);
    } catch (e) {
      // BUSYGROUP is fine; ignore
    }
  }

  @override
  Future<void> publish(Envelope m, {String? queue}) async {
    final q = queue ?? m.queue;
    if (m.notBefore != null) {
      // Delayed: ZADD delayed:<q> score=<epoch ms> member=<serialized envelope>
      final score = m.notBefore!.millisecondsSinceEpoch.toString();
      await redis.send(['ZADD', _kDelayed(q), score, jsonEncode(m.toJson())]);
      return;
    }
    await _ensureGroup(q);
    // XADD stream * fields...
    final fields = [
      'id', m.id,
      'name', m.name,
      'args', jsonEncode(m.args),
      'headers', jsonEncode(m.headers),
      'enqueuedAt', m.enqueuedAt.toIso8601String(),
      'attempt', m.attempt.toString(),
      'maxRetries', m.maxRetries.toString(),
      'priority', m.priority.toString(),
      'queue', m.queue,
    ];
    await redis.send(['XADD', _kStream(q), '*', ...fields]);
  }

  Future<void> _drainDelayed(String q) async {
    final now = DateTime.now().millisecondsSinceEpoch.toString();
    // ZRANGEBYSCORE key -inf now LIMIT 0 N
    final res = await redis.send(['ZRANGEBYSCORE', _kDelayed(q), '-inf', now, 'LIMIT', '0', '$delayedDrainBatch']);
    if (res is List && res.isNotEmpty) {
      for (final member in res.cast<String>()) {
        final ok = await redis.send(['ZREM', _kDelayed(q), member]);
        if (ok == 1 || ok == '1') {
          final env = Envelope.fromJson(jsonDecode(member));
          await publish(env.copyWith(notBefore: null), queue: q);
        }
      }
    }
  }

  @override
  Stream<Delivery> consume(String queue, {int prefetch = 1, String? consumerGroup, String? consumerName}) async* {
    final group = consumerGroup ?? _kGroup(queue);
    final consumer = consumerName ?? 'c-${DateTime.now().millisecondsSinceEpoch}';
    await _ensureGroup(queue);

    while (true) {
      await _drainDelayed(queue);

      // XREADGROUP GROUP <group> <consumer> COUNT <prefetch> BLOCK <ms> STREAMS <key> >
      final resp = await redis.send([
        'XREADGROUP','GROUP',group,consumer,
        'COUNT','$prefetch',
        'BLOCK','$blockMs',
        'STREAMS', _kStream(queue), '>'
      ]);

      if (resp == null) continue;
      if (resp is! List || resp.isEmpty) continue;

      // resp format: [[streamKey, [[id, [field, value, field, value, ...]], ...]]]
      for (final streamArr in resp.cast<List>()) {
        final entries = (streamArr[1] as List).cast<List>();
        for (final entry in entries) {
          final id = entry[0] as String;
          final fieldList = (entry[1] as List).cast<String>();
          final map = <String, String>{};
          for (var i = 0; i < fieldList.length; i += 2) {
            map[fieldList[i]] = fieldList[i + 1];
          }
          final env = Envelope(
            id: map['id']!,
            name: map['name']!,
            args: jsonDecode(map['args']!) as Map<String, dynamic>,
            headers: (jsonDecode(map['headers']!) as Map).cast<String, String>(),
            enqueuedAt: DateTime.parse(map['enqueuedAt']!),
            notBefore: null,
            priority: int.parse(map['priority'] ?? '0'),
            attempt: int.parse(map['attempt'] ?? '0'),
            maxRetries: int.parse(map['maxRetries'] ?? '0'),
            queue: map['queue'] ?? queue,
          );
          // For Redis Streams, "lease" is conceptual. We encode receipt as "streamKey|group|id"
          yield Delivery(env, '${_kStream(queue)}|$group|$id', DateTime.now());
        }
      }
    }
  }

  @override
  Future<void> ack(Delivery d) async {
    final parts = d.receipt.split('|'); // [key, group, id]
    await redis.send(['XACK', parts[0], parts[1], parts[2]]);
  }

  @override
  Future<void> nack(Delivery d, {bool requeue = true}) async {
    // Redis Streams has no NACK; strategy: ACK the message then re-enqueue if requested.
    await ack(d);
    if (requeue) {
      final env = d.message.copyWith(
        attempt: d.message.attempt + 1,
        id: d.message.id, // keep id for visibility (or new id if you prefer)
      );
      await publish(env);
    }
  }

  @override
  Future<void> deadLetter(Delivery d, {String? reason}) async {
    await ack(d);
    // LPUSH dead list with a compact JSON
    final payload = jsonEncode({
      'envelope': d.message.toJson(),
      'reason': reason,
      'deadAt': DateTime.now().toIso8601String(),
    });
    await redis.send(['LPUSH', _kDead(d.message.queue), payload]);
  }

  @override
  Future<void> purge(String queue) async {
    await redis.send(['DEL', _kStream(queue)]);
    await redis.send(['DEL', _kDelayed(queue)]);
  }
}

    Command mapping notes

        Enqueue: XADD stem:stream:<queue> * id <...> name <...> ...

        Consume: XREADGROUP GROUP stem:group:<queue> <consumer> COUNT <N> BLOCK <ms> STREAMS stem:stream:<queue> >

        Ack: XACK

        Delayed: ZADD stem:delayed:<queue> <msSinceEpoch> <json> then a small mover (_drainDelayed) pushes due items to stream.

3) Redis result backend (lib/redis_backend.dart)

// lib/redis_backend.dart
import 'dart:convert';
import 'core.dart';
import 'redis_broker.dart';

class RedisResultBackend implements ResultBackend {
  final RedisCommands redis;
  final String namespace;
  final Duration defaultTtl;

  RedisResultBackend(this.redis, {this.namespace = 'stem', this.defaultTtl = const Duration(days: 1)});

  String _k(String id) => '$namespace:result:$id';

  @override
  Future<void> set(String taskId, TaskState state, {Object? result, Object? error, int attempt = 0, Duration? ttl, Map<String, dynamic>? meta}) async {
    final t = TaskStatus(taskId, state, result, error, attempt, DateTime.now());
    await redis.send(['SET', _k(taskId), jsonEncode(t.toJson())]);
    final exp = ttl ?? defaultTtl;
    await redis.send(['PEXPIRE', _k(taskId), '${exp.inMilliseconds}']);
  }

  @override
  Future<TaskStatus?> get(String taskId) async {
    final s = await redis.send(['GET', _k(taskId)]);
    if (s == null) return null;
    final j = jsonDecode(s as String) as Map<String, dynamic>;
    return TaskStatus(
      j['id'],
      TaskState.values.firstWhere((e) => e.name == j['state']),
      j['result'],
      j['error'],
      j['attempt'],
      DateTime.parse(j['updatedAt']),
    );
  }
}

4) Beat (periodic scheduler) on ZSET (lib/beat.dart)

// lib/beat.dart
import 'dart:async';
import 'dart:convert';
import 'core.dart';
import 'redis_broker.dart';

class ScheduleEntry {
  final String id;
  final String taskName;
  final Map<String, dynamic> args;
  final String spec;     // "every:5m" for MVP. (Extend with cron later.)
  final String queue;
  final bool enabled;
  final Duration? jitter;

  ScheduleEntry({
    required this.id,
    required this.taskName,
    this.args = const {},
    required this.spec,
    this.queue = 'default',
    this.enabled = true,
    this.jitter,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'taskName': taskName,
    'args': args,
    'spec': spec,
    'queue': queue,
    'enabled': enabled,
    'jitterMs': jitter?.inMilliseconds,
  };

  static ScheduleEntry fromJson(Map<String, dynamic> j) => ScheduleEntry(
    id: j['id'],
    taskName: j['taskName'],
    args: (j['args'] as Map).cast<String, dynamic>(),
    spec: j['spec'],
    queue: j['queue'] ?? 'default',
    enabled: j['enabled'] ?? true,
    jitter: j['jitterMs'] != null ? Duration(milliseconds: j['jitterMs']) : null,
  );
}

class Beat {
  final RedisCommands redis;
  final Broker broker; // to publish
  final String namespace;
  final Duration tick;
  Timer? _timer;

  Beat(this.redis, this.broker, {this.namespace = 'stem', this.tick = const Duration(seconds: 1)});

  String get _kSchedule => '$namespace:schedules';     // ZSET of <nextAtMs, entry.id>
  String _kEntry(String id) => '$namespace:schedule:$id';
  String _kLock(String id)  => '$namespace:beatlock:$id';

  Future<void> upsert(ScheduleEntry e, {DateTime? nextAt}) async {
    final now = DateTime.now();
    final first = nextAt ?? _nextFromSpec(e.spec, now, jitter: e.jitter);
    await redis.send(['SET', _kEntry(e.id), jsonEncode(e.toJson())]);
    await redis.send(['ZADD', _kSchedule, '${first.millisecondsSinceEpoch}', e.id]);
  }

  Future<void> remove(String id) async {
    await redis.send(['DEL', _kEntry(id)]);
    await redis.send(['ZREM', _kSchedule, id]);
  }

  Future<void> run() async {
    _timer = Timer.periodic(tick, (_) => _tick());
  }

  Future<void> _tick() async {
    final now = DateTime.now().millisecondsSinceEpoch.toString();
    final due = await redis.send(['ZRANGEBYSCORE', _kSchedule, '-inf', now, 'LIMIT', '0', '100']);
    if (due is! List || due.isEmpty) return;

    for (final id in due.cast<String>()) {
      // Acquire short lock so multiple beats don't double fire: SET key val NX PX 5000
      final lock = await redis.send(['SET', _kLock(id), '1', 'NX', 'PX', '5000']);
      if (lock == null) continue;

      final raw = await redis.send(['GET', _kEntry(id)]);
      if (raw == null) {
        await redis.send(['ZREM', _kSchedule, id]);
        continue;
      }
      final entry = ScheduleEntry.fromJson(jsonDecode(raw as String));

      // Fire if enabled
      if (entry.enabled) {
        final env = Envelope(
          id: 'sch-$id-${DateTime.now().microsecondsSinceEpoch}',
          name: entry.taskName,
          args: entry.args,
          notBefore: null,
          queue: entry.queue,
        );
        await broker.publish(env.copyWith(queue: entry.queue));
      }

      // Re-schedule
      final next = _nextFromSpec(entry.spec, DateTime.now(), jitter: entry.jitter);
      await redis.send(['ZADD', _kSchedule, '${next.millisecondsSinceEpoch}', id]);
      await redis.send(['ZREM', _kSchedule, id]);
    }
  }

  DateTime _nextFromSpec(String spec, DateTime from, {Duration? jitter}) {
    // MVP: "every:5m" | "every:30s" | "every:2h"
    // TODO: add cron parser later.
    Duration d = const Duration(minutes: 1);
    if (spec.startsWith('every:')) {
      final s = spec.substring(6);
      if (s.endsWith('ms')) d = Duration(milliseconds: int.parse(s.replaceAll('ms','')));
      else if (s.endsWith('s')) d = Duration(seconds: int.parse(s.replaceAll('s','')));
      else if (s.endsWith('m')) d = Duration(minutes: int.parse(s.replaceAll('m','')));
      else if (s.endsWith('h')) d = Duration(hours: int.parse(s.replaceAll('h','')));
      else if (s.endsWith('d')) d = Duration(days: int.parse(s.replaceAll('d','')));
    }
    var next = from.add(d);
    if (jitter != null && jitter > Duration.zero) {
      final ms = jitter.inMilliseconds;
      final j = (DateTime.now().microsecondsSinceEpoch % (ms + 1));
      next = next.add(Duration(milliseconds: j));
    }
    return next;
  }
}

5) Worker (consume, execute, retry, DLQ) (lib/worker.dart)

// lib/worker.dart
import 'dart:async';

import 'core.dart';
import 'redis_broker.dart';

class Worker {
  final Broker broker;
  final ResultBackend backend;
  final TaskRegistry registry;
  final String queue;
  final String consumerGroup;
  final String consumerName;
  final int prefetch;
  final RetryStrategy retry;
  final bool stopOnEmpty;

  Worker({
    required this.broker,
    required this.backend,
    required this.registry,
    this.queue = 'default',
    String? consumerGroup,
    String? consumerName,
    this.prefetch = 10,
    RetryStrategy? retry,
    this.stopOnEmpty = false,
  }) : consumerGroup = consumerGroup ?? 'stem:$queue',
       consumerName = consumerName ?? 'w-${DateTime.now().millisecondsSinceEpoch}',
       retry = retry ?? ExponentialJitterRetry();

  Future<void> run() async {
    await for (final d in broker.consume(queue, prefetch: prefetch, consumerGroup: consumerGroup, consumerName: consumerName)) {
      unawaited(_handle(d));
    }
  }

  Future<void> _handle(Delivery d) async {
    final env = d.message;
    final handler = registry.resolve(env.name);
    if (handler == null) {
      await broker.deadLetter(d, reason: 'unknown-task');
      return;
    }

    // Mark running
    await backend.set(env.id, TaskState.running, attempt: env.attempt);

    final ctx = TaskContext(
      id: env.id,
      attempt: env.attempt,
      heartbeat: () {}, // attach to metrics/logs if you like
      extendLease: (_) async {}, // no-op for Redis Streams
      progress: (_, {data}) async {}, // wire to a channel if you like
    );

    try {
      // NOTE: For hard time limits, spawn in a separate isolate and kill if overdue (TODO).
      final soft = handler.options.softTimeLimit;
      final hard = handler.options.hardTimeLimit;
      final exec = handler.call(ctx, env.args);

      final result = await (hard != null
        ? exec.timeout(hard, onTimeout: () { throw TimeoutException('hard time limit exceeded'); })
        : exec);

      // If we want soft TL, we could wrap the handler to check deadlines cooperatively (out of scope here).

      await broker.ack(d);
      await backend.set(env.id, TaskState.succeeded, result: result, attempt: env.attempt);
    } catch (e, _) {
      if (env.attempt < (env.maxRetries)) {
        final delay = retry.nextDelay(env.attempt, e);
        final next = env.copyWith(
          attempt: env.attempt + 1,
          notBefore: DateTime.now().add(delay),
          // Optionally: new id per attempt (choose policy). Keeping id can simplify traceability.
        );
        await broker.ack(d);        // Finish current delivery
        await broker.publish(next); // Re-enqueue retry
        await backend.set(env.id, TaskState.retried, error: e, attempt: env.attempt);
      } else {
        await broker.deadLetter(d, reason: 'max-retries-reached');
        await backend.set(env.id, TaskState.failed, error: e, attempt: env.attempt);
      }
    }
  }
}

    Why ack+re‑enqueue on retry?
    In Redis Streams, leaving a message pending until retry makes recovery messy. Acking the current delivery and creating a fresh message is simpler and aligns with typical retry patterns (DLQ when maxed).

6) Example task(s) (lib/tasks.dart)

// lib/tasks.dart
import 'core.dart';

class SendEmailTask implements TaskHandler<void> {
  @override
  String get name => 'email.send';

  @override
  TaskOptions get options => const TaskOptions(
    queue: 'emails',
    maxRetries: 5,
    softTimeLimit: Duration(seconds: 20),
    hardTimeLimit: Duration(seconds: 30),
    acksLate: true,
  );

  @override
  Future<void> call(TaskContext ctx, Map<String, dynamic> args) async {
    final to = args['to'] as String;
    final subject = args['subject'] as String? ?? '(no subject)';
    final body = args['body'] as String? ?? '';
    // TODO: call your email provider; add heartbeats/progress as you like
    // ctx.heartbeat();
    // await ctx.progress(0.5);
    print('Sending email to $to: $subject');
  }
}

7) Wire it together (examples in bin/)

A) Implement your Redis client adapter (one-time)

// lib/redis_dartis_adapter.dart (example shape) -- PSEUDO; adapt to your client
import 'redis_broker.dart';
// import 'package:dartis/dartis.dart' as dartis;

class DartisRedis implements RedisCommands {
  // final dartis.Client client;
  // final dartis.Commands<String, String> cmd;
  DartisRedis(/*this.client, this.cmd*/);

  @override
  Future<dynamic> send(List<String> args) async {
    // If your client supports raw commands:
    // return await cmd.send(args.first, args.skip(1).toList());
    throw UnimplementedError('Wire to your Redis client here.');
  }

  @override
  Future<void> multi(List<List<String>> batched) async {
    // Wrap batched commands in MULTI/EXEC if your client supports it.
    for (final a in batched) { await send(a); }
  }
}

B) Worker entrypoint

// bin/worker_example.dart
import 'package:stem/core.dart';
import 'package:stem/redis_broker.dart';
import 'package:stem/redis_backend.dart';
import 'package:stem/worker.dart';
import 'package:stem/tasks.dart';
// import 'package:stem/redis_dartis_adapter.dart';

Future<void> main() async {
  // final redis = DartisRedis(...); // TODO: create real client
  final redis = throw UnimplementedError('Provide RedisCommands implementation');

  final broker = RedisBroker(redis, namespace: 'stem');
  final backend = RedisResultBackend(redis, namespace: 'stem');

  final reg = SimpleTaskRegistry()..register(SendEmailTask());

  final w = Worker(
    broker: broker,
    backend: backend,
    registry: reg,
    queue: 'emails',
    prefetch: 10,
  );

  await w.run(); // runs indefinitely
}

C) Beat entrypoint

// bin/beat_example.dart
import 'package:stem/beat.dart';
import 'package:stem/redis_broker.dart';
// import 'package:stem/redis_dartis_adapter.dart';

Future<void> main() async {
  // final redis = DartisRedis(...);
  final redis = throw UnimplementedError('Provide RedisCommands implementation');

  final broker = RedisBroker(redis, namespace: 'stem');
  final beat = Beat(redis, broker, namespace: 'stem');

  // Example: run a cleanup task every 5 minutes with up to 30s jitter
  await beat.upsert(ScheduleEntry(
    id: 'cleanup-invoices',
    taskName: 'billing.cleanup',
    spec: 'every:5m',
    queue: 'maintenance',
    jitter: Duration(seconds: 30),
  ));

  await beat.run();
}

D) Enqueue example

// bin/enqueue_example.dart
import 'package:stem/core.dart';
import 'package:stem/redis_broker.dart';
// import 'package:stem/redis_dartis_adapter.dart';

Future<void> main() async {
  // final redis = DartisRedis(...);
  final redis = throw UnimplementedError('Provide RedisCommands implementation');

  final broker = RedisBroker(redis, namespace: 'stem');
  final stem = Stem(broker);

  await stem.enqueue(
    'email.send',
    {'to': 'user@example.com', 'subject': 'Welcome', 'body': 'Hello!'},
    options: const TaskOptions(queue: 'emails', maxRetries: 3),
  );
}

8) Notes, trade‑offs, and next TODOs (so you can extend confidently)

    Delayed jobs: Implemented via ZSET stem:delayed:<queue> → mover periodically XADDs due items. (Workers call _drainDelayed every poll; you can also run a tiny “queue-scheduler” sidecar.)

    Retries: We ack + re-enqueue with a new notBefore, tracked with attempt. When attempt > maxRetries, we DLQ the envelope to LPUSH stem:dead:<queue>.

    Visibility/leases: Redis Streams doesn’t have visibility timeouts like SQS. Recovery is via pending entry claim (you can add XAUTOCLAIM loop later to reclaim messages idle for reclaimAfter). extendLease is a no‑op for Redis Streams by design.

    Time limits: The code uses Future.timeout for a hard limit surface. For a true hard kill, run the task in a spawned Isolate and isolate.kill() when the timer expires (recommended for CPU/blocked work).

    Idempotency: Before side effects, check your own idempotency keys (e.g., headers['idempotency-key']) using Redis locks or a DB outbox table. The skeleton leaves this to the task author for now.

    Rate limiting: Add a Redis token‑bucket (INCR + TTL per window) keyed by taskName to enforce "5/s" / "300/m". Wire it in Worker._handle before execution.

    Canvas (chains/groups/chords): Add a tiny “group result” record in the result backend, and a chord aggregator that watches completion and enqueues the callback — easy to layer on this base.

9) How to try this quickly

    Start Redis

    docker run --rm -p 6379:6379 redis:7

    Wire RedisCommands to your preferred package (keep the command arrays the same as in the comments).

    Run Beat (bin/beat_example.dart) and Worker (bin/worker_example.dart) in separate terminals.

    Enqueue (bin/enqueue_example.dart) and watch the worker log.

10) Production‑readiness checklist (applied to this skeleton)

    Correctness

Add XAUTOCLAIM reclaimer loop (periodically claim idle > reclaimAfter).

Make retry policy and DLQ configurable per task/queue.

    Provide idempotency helpers (unique job lock + outbox docs).

Performance

Prefetch tuning, backpressure (cap concurrent in‑flight per worker).

    Benchmarks: p95 execute time, throughput vs. concurrency.

Reliability

Graceful shutdown: stop polling, drain inflight (ack or requeue).

    Chaos tests: kill worker mid‑task; verify retry/claim path.

Security

TLS Redis; creds via env/secret.

    Optionally sign/encrypt payloads.

Observability

OpenTelemetry spans (enqueue → consume → execute).

Metrics: queue depth, pending, retries, DLQ size, task durations.

    Admin UI (Flutter Web): queues, workers, schedules, DLQ replay.

Ops

CLI: stem worker, stem beat, stem admin (dlq, purge, move).

        Docs: broker trade‑offs, tuning, K8s deployment.

If you want, I can add the XAUTOCLAIM reclaimer loop and a minimal isolate-based hard timeout runner next, plus a small DLQ replay CLI snippet — just say the word and I’ll drop the code.


ChatGPT can make mistakes. Check important info.
