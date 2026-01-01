---
title: Retry & Backoff
sidebar_label: Retry & Backoff
sidebar_position: 12
slug: /getting-started/retry-backoff
---

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

## Operational checklist

- Monitor retry rates and DLQ volume.
- Alert on sustained retry spikes.
- Requeue only after the root cause is fixed.

## Next steps

- [Tasks & Retries](../core-concepts/tasks.md)
- [Reliability Guide](./reliability.md)
- [Troubleshooting](./troubleshooting.md)
