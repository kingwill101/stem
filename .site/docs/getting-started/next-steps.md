---
title: Next Steps
sidebar_label: Next Steps
sidebar_position: 8
slug: /getting-started/next-steps
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

Use this page as a jump table once you’ve finished the first walkthroughs.

## Calling tasks

- [Producer API](../core-concepts/producer.md)
- [Tasks & Retries](../core-concepts/tasks.md)
- [Retry & Backoff](./retry-backoff.md)

<Tabs>
<TabItem value="producer" label="Producer enqueue">

```dart title="lib/producer.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/producer.dart#producer-redis

```

</TabItem>
<TabItem value="task" label="Task handler">

```dart title="lib/tasks.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/tasks.dart#tasks-register-redis

```

</TabItem>
</Tabs>

## Canvas/Workflows

- [Canvas Patterns](../core-concepts/canvas.md)
- [Workflows](../core-concepts/workflows.md)

```dart title="lib/canvas_chain.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/canvas_chain.dart#canvas-chain

```

## Routing

- [Routing](../core-concepts/routing.md)

```dart title="lib/routing.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/routing.dart#routing-inline

```

## Remote control

- [CLI & Control](../core-concepts/cli-control.md)
- [Worker Control CLI](../workers/worker-control.md)

```dart title="lib/worker_control.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/worker_control.dart#worker-control-autoscale

```

## Observability & ops

- [Observability](../core-concepts/observability.md)
- [Dashboard](../core-concepts/dashboard.md)
- [Production Checklist](./production-checklist.md)

```dart title="lib/observability.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/observability.dart#observability-metrics

```

## Timezone

- [Scheduler](../scheduler/index.md)
- [Beat Scheduler Guide](../scheduler/beat-guide.md)

```dart title="lib/scheduler.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/scheduler.dart#beat-specs

```

## Optimization

- [Rate Limiting](../core-concepts/rate-limiting.md)
- [Uniqueness](../core-concepts/uniqueness.md)
- [Payload Signing](../core-concepts/signing.md)

```dart title="lib/rate_limiting.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/rate_limiting.dart#rate-limit-task

```
