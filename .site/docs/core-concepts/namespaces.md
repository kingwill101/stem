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

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## What uses the namespace

- **Brokers & backends**: queue streams, task results, heartbeats, and dead
  letters are scoped by the namespace configured on each adapter.
- **Schedule & lock stores**: schedule entries and scheduler locks use
  namespace-prefixed keys/tables so multiple schedulers can share a store.
- **Revoke stores**: revocation entries are scoped by namespace.
- **Workflow stores**: workflow runs and topic queues are namespaced.
- **Control plane**: worker control channels and heartbeat topics use the
  worker namespace.
- **Dashboard**: reads control/observability data using its configured
  namespace.

## Configure namespaces

<Tabs>
<TabItem value="broker" label="Broker + Backend">

```dart title="lib/namespaces.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/namespaces.dart#namespaces-broker-backend

```

</TabItem>
<TabItem value="worker" label="Worker Heartbeats">

```dart title="lib/namespaces.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/namespaces.dart#namespaces-worker

```

</TabItem>
</Tabs>

## Environment variables

Stem does not use a single global namespace variable; instead, namespaces are
configured per adapter or via the worker observability settings. The default is
`stem` when no override is provided.

| Variable | Purpose | Default |
| --- | --- | --- |
| `STEM_WORKER_NAMESPACE` | Worker heartbeat/control namespace when using `ObservabilityConfig.fromEnvironment` | `stem` |
| `STEM_WORKFLOW_NAMESPACE` | Workflow store namespace used by the CLI workflow runner | `stem` |
| `STEM_DASHBOARD_NAMESPACE` | Namespace the dashboard reads | falls back to `STEM_NAMESPACE` or `stem` |
| `STEM_NAMESPACE` | Dashboard fallback namespace value | `stem` |

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
