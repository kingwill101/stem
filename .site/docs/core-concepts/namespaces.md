---
title: Namespaces
sidebar_label: Namespaces
sidebar_position: 6
slug: /core-concepts/namespaces
---

Namespaces provide logical isolation between environments (dev/staging/prod) or
between tenants sharing the same infrastructure. Most Stem components honor the
namespace when naming queues, result keys, and control channels. Unless you pass
an explicit namespace, adapters default to `stem`.

## What uses the namespace

- **Brokers**: queue names and stream keys are prefixed by namespace.
- **Result backends**: task status, group results, and heartbeats are stored
  under namespace-prefixed keys or tables.
- **Schedule & lock stores**: schedules, locks, and leases include namespace
  prefixes so multiple schedulers can share a store safely.
- **Revoke stores**: revocation entries are scoped by namespace.
- **Workflow stores**: workflow runs and topic queues are namespaced.
- **Control plane**: control broadcast channels and reply queues are scoped by
  namespace.
- **CLI**: worker control commands accept `--namespace` to target non-default
  namespaces.

## Configuration options

Stem uses a few namespace-related environment variables. The defaults are
sensible for single-environment deployments; override them when you need
isolation:

| Variable | Purpose | Default |
| --- | --- | --- |
| `STEM_WORKER_NAMESPACE` | Namespace for worker IDs + heartbeats | `stem` |
| `STEM_WORKFLOW_NAMESPACE` | Namespace for workflow store entries | `stem` |
| `STEM_DASHBOARD_NAMESPACE` | Namespace the dashboard reads | `stem` |

Most adapter namespaces are set when you construct the broker/backend/store,
for example:

```dart
final broker = await RedisStreamsBroker.connect(
  'redis://localhost:6379',
  namespace: 'staging',
);
final backend = await RedisResultBackend.connect(
  'redis://localhost:6379/1',
  namespace: 'staging',
);
final scheduleStore = await RedisScheduleStore.connect(
  'redis://localhost:6379/2',
  namespace: 'staging',
);
```

## CLI usage

When using a non-default namespace, pass it explicitly to worker control
commands:

```bash
stem worker stats --namespace "staging"
stem worker ping --namespace "staging"
```

## Tips

- Keep namespaces consistent across producers, workers, schedulers, and CLI.
- Use per-environment namespaces (e.g., `dev`, `staging`, `prod`) to avoid cross-
  environment interference.
- If the dashboard shows no data, verify `STEM_DASHBOARD_NAMESPACE` matches your
  worker namespace.

## Next steps

- See [Workers](../workers/index.md) for worker namespace variables.
- See [Dashboard](./dashboard.md) for dashboard namespace settings.
