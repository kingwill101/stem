---
title: Retry & Backoff
sidebar_label: Retry & Backoff
sidebar_position: 12
slug: /getting-started/retry-backoff
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

Retries keep transient failures from becoming outages. Use backoff to prevent
retry storms.

## Principles

- Treat transient errors as retryable.
- Fail fast on permanent errors (bad input, missing resources).
- Add jitter to spread retries over time.

## When to retry

- Network timeouts
- Rate-limited downstream APIs
- Temporary resource exhaustion

Avoid retrying when:

- Validation fails
- Authorization fails
- The task is not idempotent

## Backoff strategy

- Start with a short delay, then increase gradually.
- Cap the maximum delay.
- Add random jitter to avoid spikes.

## Stem defaults

Workers use `ExponentialJitterRetryStrategy` by default:

- `base`: 2 seconds
- `max`: 5 minutes

Retries are scheduled by publishing a new envelope with `notBefore` set to the
next retry time. Each retry increments the attempt counter until
`TaskOptions.maxRetries` is exhausted.

## Task options

Use `maxRetries` on task handlers to cap retries:

```dart title="lib/retry_backoff.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/retry_backoff.dart#retry-backoff-task-options

```

## Custom strategies

Provide a custom `RetryStrategy` to the worker when you need fixed delays,
linear backoff, or bespoke logic:

<Tabs>
<TabItem value="strategy" label="Strategy config">

```dart title="lib/retry_backoff.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/retry_backoff.dart#retry-backoff-strategy

```

</TabItem>
<TabItem value="worker" label="StemApp worker config">

```dart title="lib/retry_backoff.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/retry_backoff.dart#retry-backoff-worker

```

</TabItem>
<TabItem value="custom" label="Custom strategy">

```dart title="lib/retry_backoff.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/retry_backoff.dart#retry-backoff-custom-strategy

```

</TabItem>
<TabItem value="fixed-delay" label="Fixed-delay worker">

```dart title="lib/retry_backoff.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/retry_backoff.dart#retry-backoff-custom-worker

```

</TabItem>
</Tabs>

You can also implement your own strategy by conforming to the `RetryStrategy`
interface and returning the desired delay for each attempt.

## Observability cues

Watch these signals and metrics to verify retry behavior:

- `StemSignals.taskRetry` includes the next retry timestamp.
- `stem.tasks.retried` and `stem.tasks.failed` counters highlight spikes.
- DLQ volume indicates retries are exhausting or errors are permanent.

```dart title="lib/retry_backoff.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/retry_backoff.dart#retry-backoff-signals

```

## Operational checklist

- Monitor retry rates and DLQ volume.
- Alert on sustained retry spikes.
- Requeue only after the root cause is fixed.

## Next steps

- [Tasks & Retries](../core-concepts/tasks.md)
- [Reliability Guide](./reliability.md)
- [Troubleshooting](./troubleshooting.md)
