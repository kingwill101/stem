## Overview
Stem workers provide fixed concurrency, basic heartbeats, and no remote control surface. To align with Celery’s worker guide we need three pillars:

1. **Control Plane** — Real-time commands (`ping`, `stats`, `active`, `revoke`, `shutdown`) targeting one or many workers. Backed by a routing channel shared with the new routing work (broadcast) so commands reach all workers and replies aggregate back to the coordinator.
2. **Autoscaling** — Dynamic concurrency adjustments reacting to queue depth and inflight workloads, respecting min/max bounds and avoiding thrash.
3. **Lifecycle Guards** — Warm/soft/hard shutdown semantics, `max_tasks_per_child`, `max_memory_per_child`, and persistent revokes to survive restarts.

## Control Plane
- **Transport Abstraction**: Define a `ControlTransport` interface with `sendCommand`, `receiveCommands`, and `sendReply`. Current implementation ships with a broker-backed transport that publishes control envelopes to per-worker queues (`<namespace>.control.worker.<id>`) and replies via `<namespace>.control.reply.<requestId>`. This works across Redis Streams and Postgres without additional infrastructure. The interface leaves room for future transports:
  - `BroadcastControlTransport`: reuse the broadcast routing channel from `add-routing-controls` once available, minimizing per-worker publications.
  - `HttpControlTransport`: expose an internal HTTP endpoint (SSE/WebSocket) for environments where brokers cannot deliver near-real-time control messages.
  - `PollingControlTransport`: allow workers to poll a REST endpoint or shared store (`control.pollInterval`, default 5s) when push transports are unavailable.
  Transports can be chained (e.g., try broadcast, fallback to HTTP, then polling) to fit diverse deployments.
- **Message Schema**:
  ```json
  {
    "requestId": "uuid",
    "type": "ping|stats|list-active|revoke|shutdown|autoscale-config",
    "targets": ["worker-id", "*"],
    "payload": { /* command specific */ },
    "timeoutMs": 5000,
    "auth": { "signature": "...", "keyId": "..." }
  }
  ```
  - `ping`: empty payload.
  - `stats`: may include `includeTasks=true` to fetch active/reserved tasks.
  - `list-active`: optional filters.
  - `revoke`: `{ "taskIds": [...], "terminate": true, "signal": "SIGTERM" }`.
  - `shutdown`: `{ "mode": "warm|soft|hard" }`.
  - `autoscale-config`: update min/max at runtime.
- **Replies**: Workers respond via the active transport (broker reply queue by default) with:
  ```json
  {
    "requestId": "uuid",
    "workerId": "worker-1",
    "status": "ok|error|timeout",
    "payload": { /* command specific */ },
    "error": { "message": "...", "code": "..." }
  }
  ```
  The coordinator aggregates replies and enforces client-side timeouts.
- **Security**: Commands originate from trusted coordinator (Stem CLI or service). We will reuse the signing middleware (HMAC/Ed25519) to sign commands and verify on the worker. Commands lacking valid signatures are rejected and logged. Apply per-worker rate limiting (configurable, default 10 commands/sec) to avoid DoS. For HTTP transports, allow mTLS or token-based auth in addition to signatures.
- **Persistent Revokes**: Introduce a `RevokeStore` abstraction with Redis and Postgres adapters (defaulting to whichever backing service is configured) plus a file-based fallback (`revokes.stem`). On startup workers hydrate their in-memory cache from the store, prune expired records, and sync further updates through control messages. Store entries include monotonic versions so workers can ignore stale updates and revalidate after restarts. The CLI writes through the store before broadcasting control envelopes so durability always precedes visibility.
- **Termination Semantics**: `stem worker revoke --terminate` requests best-effort cancellation. Inline handlers honour revokes the next time they call `heartbeat`, `extendLease`, or `progress` (throwing a `TaskRevokedException`). Isolate-backed tasks respond once they emit those signals; long-running tasks should publish heartbeats or cooperative checkpoints so termination can pre-empt work.

### Current Control/Telemetry Surface (Audit)
- Worker heartbeats are published via `HeartbeatTransport` every `workerHeartbeatInterval` (default 10s) and persisted through the result backend (`setWorkerHeartbeat`). The payload already includes worker id, namespace, inflight counts, queues, and extras such as host/prefetch.
- The CLI currently exposes a `stem worker status` command that reads heartbeat snapshots (JSON) and filters by `--worker` identifiers. There is no live control channel: status relies on observing stored heartbeats only.
- Task-level middleware hooks exist (`onEnqueue/onConsume/onExecute/onError`) but there is no single entry-point for pushing remote commands down to active workers.
- Shutdown today is a single path (`Worker.shutdown`) invoked by process signals or CLI stop commands; there is no differentiation between warm/soft/hard semantics.

## Autoscaling
- **Metrics Source**: Use worker heartbeats (already include inflight counts) plus broker metrics (queue depth via lightweight query per worker or aggregated coordinator poll). Heartbeats will be augmented with `queueDepth` snapshot to avoid extra broker hits when possible.
- **Evaluation Loop**: `Autoscaler` runs every `autoscale.tick` (default 2s) and computes desired concurrency:
  ```
  desired = clamp(
      min + ceil( (queueDepth / prefetchPerIsolate) ),
      min,
      max
  )
  ```
  - `prefetchPerIsolate = prefetch / currentIsolates` (falls back to multiplier if dynamic prefetch disabled).
  - If `inflight == 0` and `queueDepth == 0` for `idleSeconds`, decrement isolates by `scaleDownStep`.
  - Scale-up occurs when `queueDepth >= currentIsolates * prefetchMultiplier * scaleUpTrigger` (default trigger = 1.0) and at least `scaleUpCoolDown` seconds since last scale-up.
  - Scale-down occurs when idle and `currentIsolates - scaleDownStep >= min`.
- **Implementation**: For isolate-based worker, spawn additional isolates asynchronously (warm them before assigning tasks) up to `max`. When downscaling, mark isolates as draining; they stop fetching new tasks and terminate after finishing current work.
- **Configurables**:
  ```yaml
  autoscale:
    enabled: false
    min: 2
    max: 12
    scaleUpStep: 2
    scaleDownStep: 1
    idleSeconds: 30
    tick: 2s
    scaleUpCoolDown: 5s
    scaleDownCoolDown: 10s
  ```
  Autoscaling is opt-in; defaults preserve current fixed concurrency.

## Lifecycle Controls
- **Signals/CLI**: Map OS signals (`SIGTERM`, `SIGQUIT`, `SIGINT`) to warm/soft/hard shutdown flows. Provide CLI `stem worker shutdown --mode=warm|cold|force` which publishes control messages.
- **Max Tasks per Isolate**: Track tasks executed per isolate; once threshold reached, mark isolate for recycle after completing current task.
- **Max Memory**: Periodically sample isolate memory usage (using `Isolate.loadPort` metrics). If above threshold, recycle isolate or trigger control action.
- **Connection Loss Recovery**: On broker reconnect reduce prefetch multiplier until running tasks complete (mirroring Celery’s behaviour).

## CLI & Observability
- Refactor CLI using structured `CommandRunner` subclasses so each worker command (`ping`, `inspect`, `active`, `revoke`, `autoscale`, `shutdown`) has well-defined usage, help text, and argument parsing. Group related commands under `stem worker control ...`.
- Extend CLI with new subcommands and ensure they leverage the new control transport abstraction (falling back gracefully when transports unavailable).
- `stem observe workers` shows control metrics (uptime, concurrency, autoscale state, revoked tasks count).

## Compatibility
- Defaults keep current behaviour: control plane optional, autoscaling disabled, warm shutdown semantics adopt existing `shutdown` method. Config toggles via YAML or CLI flags.
- Ensure routing proposal lands first; this design depends on broadcast channels for control traffic.
