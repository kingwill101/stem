---
title: CLI & Control Plane
sidebar_label: CLI & Control
sidebar_position: 8
slug: /core-concepts/cli-control
---

The `stem` CLI complements the programmatic APIs—use it to inspect state,
manage workers, and operate schedules and routing.

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

Many CLI commands that reference task names need a registry. The default CLI
context does not load one automatically, so wire it via `runStemCli` with a
`contextBuilder` that sets `CliContext.registry`. For multi-binary deployments,
ensure the CLI and workers share the same registry entrypoint so task names,
encoders, and routing rules stay consistent.

If a command needs a registry and none is available, it will exit with an error
or fall back to raw task metadata (depending on the subcommand).

## List registered tasks

```bash
stem tasks ls
```

Expected output:

```text
NAME            DESCRIPTION        IDEMPOTENT  TAGS
email.send      Sends an email     yes         notifications
```

## Observe queues, workers, and schedules

```bash
stem observe queues
stem observe workers
stem observe dlq
stem observe schedules
```

Expected output:

```text
Queue     | Pending | Inflight
Worker    | Active  | Last Heartbeat
Queue     | Task ID                        | Reason
Summary: due=... overdue=...
```

Requirements:

- `stem observe queues` and `stem observe dlq` need a broker.
- `stem observe workers` requires a result backend.
- `stem observe schedules` reads from `STEM_SCHEDULE_STORE_URL` or a schedule file.

## Worker control commands

```bash
stem worker ping
stem worker stats
stem worker revoke --task <id>
stem worker shutdown --mode warm
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
  --yes

stem schedule list
stem schedule dry-run --spec "every:5m"
```

Run Beat from a Dart entrypoint wired to your schedule store:

```dart title="lib/scheduler.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/scheduler.dart#beat-redis

```

Requirements:

- `stem schedule apply/list/dry-run` use `STEM_SCHEDULE_STORE_URL` when set,
  otherwise they operate on local schedule files.
- Beat needs a broker, schedule store, and (for HA) a lock store.

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
  --backend "$STEM_RESULT_BACKEND_URL"
```

The command exits non-zero when connectivity, TLS, or signing checks fail—ideal
for CI/CD gates.

## Backend requirements by command

Use this table to sanity-check which connection strings are required:

| Command | Broker | Result backend | Schedule store | Revoke store | Registry |
| --- | --- | --- | --- | --- | --- |
| `stem tasks ls` | ❌ | ❌ | ❌ | ❌ | ✅ |
| `stem observe queues` | ✅ | ❌ | ❌ | ❌ | ❌ |
| `stem observe workers` | ❌ | ✅ | ❌ | ❌ | ❌ |
| `stem observe dlq` | ✅ | ❌ | ❌ | ❌ | ❌ |
| `stem observe schedules` | ❌ | ❌ | ✅ | ❌ | ❌ |
| `stem worker ping/stats/inspect` | ✅ | ❌ | ❌ | ❌ | ❌ |
| `stem worker status` | optional (follow) | optional (snapshot) | ❌ | ❌ | ❌ |
| `stem worker revoke` | ✅ | optional | ❌ | optional | ❌ |
| `stem worker shutdown` | ✅ | ❌ | ❌ | ❌ | ❌ |
| `stem schedule apply/list/dry-run` | ❌ | ❌ | ✅ | ❌ | ❌ |
| `stem health` | ✅ | optional | ❌ | ❌ | ❌ |

Notes:

- The CLI resolves URLs from `STEM_BROKER_URL`, `STEM_RESULT_BACKEND_URL`,
  `STEM_SCHEDULE_STORE_URL`, and `STEM_REVOKE_STORE_URL`.
- When a backend is “optional”, the command still runs but will skip that
  slice of data (for example, worker heartbeats without a result backend).
- Schedule commands fall back to local schedule files when no schedule store
  is configured.

Keep the CLI handy when iterating on the code examples in the feature guides.
