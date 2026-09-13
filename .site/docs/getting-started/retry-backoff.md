---
title: Retry & Backoff
sidebar_label: Retry & Backoff
sidebar_position: 12
slug: /getting-started/retry-backoff
---

Task delivery/handler retries are separate from the durable retry journal used
by workflow checkpoints and compensation. Neither makes external effects
exactly once. Stem delivery is at least once, so use idempotency keys or
idempotent writes for external effects.

## Task retries

`TaskRetryPolicy` is attached through `TaskOptions.retryPolicy` or
`TaskEnqueueOptions.retryPolicy`. `maxRetries` is a retry budget, not the total
number of attempts. The policy also supports `defaultDelay`, `backoff`,
`backoffMax`, `jitter`, `autoRetryFor`, and `dontAutoRetryFor`.

The worker `RetryStrategy` calculates task retry delays. The default is
`ExponentialJitterRetryStrategy`, whose defaults are a two-second base and a
five-minute cap:

```dart
import 'package:stem/stem.dart';

final strategy = ExponentialJitterRetryStrategy(
  base: const Duration(seconds: 2),
  max: const Duration(minutes: 5),
);
```

Retry transient failures such as timeouts, temporary overload, and rate
limits. Avoid retrying invalid input or authorization failures. Bound retries
and add jitter to avoid a retry storm.

## Workflow journal retries

`WorkflowRetryPolicy.maxAttempts` includes the first logical checkpoint
attempt. `delayAfter(attempt)` is persisted policy backoff, not the task retry
budget. Queue redelivery after a crash does not reset the journal budget. Step
and compensation journals are separate:

- `WorkflowStepRetryExhausted` means a checkpoint exhausted its attempts.
- `WorkflowCompensationRetryExhausted` means reverse-order cleanup exhausted
  its independent attempts and needs intervention.

When a workflow task is redelivered, determine whether the failure is queue
delivery or a journaled step failure. Adjust the task and journal policies
independently; do not repair a poisoned workflow by replaying its queue task.

See [Reliability](./reliability.md) and
[workflow troubleshooting](../workflows/troubleshooting.md).
