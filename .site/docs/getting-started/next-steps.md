---
title: Next Steps
sidebar_label: Next Steps
sidebar_position: 8
slug: /getting-started/next-steps
---

## Hosted workflows

Read [Workflow getting started](../workflows/getting-started.md), then:

- [Flows and Scripts](../workflows/flows-and-scripts.md)
- [Starting and Waiting](../workflows/starting-and-waiting.md)
- [Suspensions and Events](../workflows/suspensions-and-events.md)
- [Errors, Retries, and Idempotency](../workflows/errors-retries-and-idempotency.md)
- [Context and Serialization](../workflows/context-and-serialization.md)

`WorkflowHost.inMemory` is process-local. For production, use
`WorkflowHost.create`, configure a persistent adapter, save run IDs, and
re-register compatible definitions after restart. `recover()` re-enqueues a
bounded batch of runnable runs; it is not exactly-once dispatch and does not
force-resume a future timer or event wait.

## Generated tasks

- [Tasks](../core-concepts/tasks.md) and [Producer API](../core-concepts/producer.md)
- [Routing](../core-concepts/routing.md), [retry and backoff](./retry-backoff.md),
  and [uniqueness](../core-concepts/uniqueness.md)
- [Observability](../core-concepts/observability.md) and the
  [production checklist](./production-checklist.md)

Tasks and workflow handlers both have at-least-once effects. A successful
checkpoint does not make an external API call transactional.

## Flutter and AI

For a Flutter foreground host, use `stem_flutter`'s
`WorkflowHostController` and `WorkflowHostScope`; see the
[`stem_flutter` package README](https://pub.dev/packages/stem_flutter).

For AI-assisted authoring, [AI skills](./ai-skills.md) explains the official
Dart package-skills installation flow and the skills included in Stem's source.
Older pub.dev releases may not include them.
