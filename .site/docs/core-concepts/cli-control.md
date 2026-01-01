---
title: CLI & Control Plane
sidebar_label: CLI & Control
sidebar_position: 8
slug: /core-concepts/cli-control
---

The `stem` CLI complements the programmatic APIs—use it to enqueue test jobs,
inspect state, and manage workers.

## Inspect vs control

- **Inspect** commands read state (`stem observe ...`, `stem worker stats`) and
  are safe to run frequently.
- **Control** commands mutate worker state (`stem worker revoke`, `stem worker shutdown`)
  and should be restricted to operators.
- Broadcast commands (like `stem worker ping`) fan out to all workers unless you
  target a specific worker ID.
- Use `--namespace` to ensure the CLI targets the same namespace as your workers.

## Remote control primer

The worker control commands (`ping`, `stats`, `inspect`, `revoke`, `shutdown`)
publish control messages into the broker. Each command uses a request id and
waits for replies on a per-request reply queue.

Targeting rules:

- **Broadcast** (default): omit `--worker` to broadcast to every worker in the
  namespace.
- **Targeted**: pass one or more `--worker` values to address specific worker
  ids only.

Inspect vs control semantics:

- **Inspect** (`ping`, `stats`, `inspect`) returns snapshots and does not
  mutate worker state.
- **Control** (`revoke`, `shutdown`) persists intent and asks workers to change
  behavior (terminate tasks or shut down).

Payload highlights (as sent by the CLI):

- `ping`/`stats`: command `type` with a `targets` list (defaults to `*`).
- `inspect`: includes `includeRevoked` and the control `namespace`.
- `revoke`: includes `revocations` plus `requester` and `namespace`.
- `shutdown`: includes `mode` (`warm`, `soft`, `hard`).

Example usage:

```bash
# Broadcast to all workers
stem worker ping

# Target a single worker by id
stem worker stats --worker worker-a
```

## Registry resolution

Many CLI commands that reference task names need a registry. By default, the
CLI uses `--registry` when provided, otherwise it relies on the registry wired
into the CLI context (for example, a `runStemCli(..., contextBuilder: ...)`
wrapper that sets `CliContext.registry`). For multi-binary deployments, point
the CLI at the same registry entrypoint you use for workers so task names,
encoders, and routing rules stay consistent.

Use a Dart entrypoint that registers tasks, for example:

```bash
--registry lib/main.dart
```

If a command needs a registry and none is available, it will exit with an error
or fall back to raw task metadata (depending on the subcommand).

## Enqueue tasks

```bash
stem enqueue hello.print \
  --args '{"name":"CLI"}' \
  --registry lib/main.dart \
  --broker redis://localhost:6379
```

Expected output:

```text
taskId=... queue=default
```

## Observe tasks and groups

```bash
stem observe tasks list --broker "$STEM_BROKER_URL"
stem observe groups --backend "$STEM_RESULT_BACKEND_URL"
```

Expected output:

```text
tasks: [id=..., state=..., attempt=...]
groups: [id=..., completed=..., expected=...]
```

Requirements:

- `stem observe tasks` needs a broker.
- `stem observe groups` requires a result backend.

## Worker control commands

```bash
stem worker ping --broker "$STEM_BROKER_URL"
stem worker stats --broker "$STEM_BROKER_URL"
stem worker revoke --broker "$STEM_BROKER_URL" --task-id <id>
stem worker shutdown --broker "$STEM_BROKER_URL" --mode warm
```

Expected output:

```text
ping: ok
stats: workers=... queues=...
```

Combine with programmatic signals for richer telemetry (see
[Worker Control CLI](../workers/worker-control.md)).

## Scheduler

```bash
stem schedule apply \
  --file config/schedules.yaml \
  --store "$STEM_SCHEDULE_STORE_URL"

stem beat start \
  --store "$STEM_SCHEDULE_STORE_URL" \
  --broker "$STEM_BROKER_URL" \
  --registry lib/main.dart
```

Requirements:

- `stem schedule apply` and `stem beat start` require a schedule store.
- `stem beat start` also needs a broker and registry.

Expected output (schedule list):

```text
ID        | Task           | Queue    | Spec             | Next Run                | Last Run                | Jitter  | Enabled
----------+----------------+----------+------------------+------------------------+------------------------+---------+---------
cleanup   | maintenance... | default  | every:5m         | 2025-01-01T00:05:00Z    | 2025-01-01T00:00:00Z    | 0ms     | yes
```

## Health checks

```bash
stem health \
  --broker "$STEM_BROKER_URL" \
  --backend "$STEM_RESULT_BACKEND_URL" \
  --schedule-store "$STEM_SCHEDULE_STORE_URL"
```

The command exits non-zero when connectivity, TLS, or signing checks fail—ideal
for CI/CD gates.

## Backend requirements by command

Use this table to sanity-check which connection strings are required:

| Command | Broker | Result backend | Schedule store | Revoke store | Registry |
| --- | --- | --- | --- | --- | --- |
| `stem enqueue` | ✅ | optional | ❌ | ❌ | ✅ |
| `stem observe tasks` | ✅ | ❌ | ❌ | ❌ | ❌ |
| `stem observe groups` | ❌ | ✅ | ❌ | ❌ | ❌ |
| `stem observe queues` | ✅ | optional | ❌ | ❌ | ❌ |
| `stem observe workers` | ❌ | ✅ | ❌ | ❌ | ❌ |
| `stem observe schedules` | ❌ | ❌ | ✅ | ❌ | ❌ |
| `stem worker ping/stats/status` | ✅ | optional | ❌ | ❌ | ❌ |
| `stem worker revoke` | ✅ | optional | ❌ | ✅ | ❌ |
| `stem worker shutdown` | ✅ | ❌ | ❌ | ❌ | ❌ |
| `stem schedule apply/list/dry-run` | ❌ | ❌ | ✅ | ❌ | ❌ |
| `stem beat start` | ✅ | optional | ✅ | ❌ | ✅ |
| `stem health` | ✅ | optional | optional | ❌ | ❌ |

Notes:

- The CLI resolves URLs from `STEM_BROKER_URL`, `STEM_RESULT_BACKEND_URL`,
  `STEM_SCHEDULE_STORE_URL`, and `STEM_REVOKE_STORE_URL`.
- When a backend is “optional”, the command still runs but will skip that
  slice of data (for example, worker heartbeats without a result backend).

Keep the CLI handy when iterating on the code examples in the feature guides.
