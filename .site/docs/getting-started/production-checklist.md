---
title: Prepare for Production
sidebar_label: Production Checklist
sidebar_position: 5
slug: /getting-started/production-checklist
---

This checklist is about deployment decisions, not guarantees. Stem task
delivery is at least once; handlers must make external effects idempotent.
There is no exactly-once guarantee for a process, a broker acknowledgement, or
a mobile application whose process is suspended or killed.

Paths beginning with `packages/` refer to a Stem source checkout. A published
package may not include repository examples, templates, or test services; use
the files in the version you actually publish.

## Before the first deployment

- Pin `stem`, its broker adapter, and `stem_cli` versions together.
- Run `dart format --output=none --set-exit-if-changed .`, `dart analyze`, and
  the package tests in CI. Include adapter integration tests when services are
  available.
- Use durable broker, result, and workflow stores in production. In-memory
  implementations are for tests and do not survive process restarts.
- Give producers and workers the same queue, namespace, registration, routing,
  and serialization configuration.
- Size broker visibility and worker/workflow leases for the longest operation,
  with renewal enabled. Expiry can cause redelivery while a handler runs.

## Protect payloads and connections

Stem supports HMAC-SHA256 and Ed25519 payload signing. Configure every producer
and worker using the variables documented in
[Payload Signing](../core-concepts/signing.md):

```bash
export STEM_SIGNING_ALGORITHM=hmac-sha256
export STEM_SIGNING_KEYS="v1:<base64-secret>"
export STEM_SIGNING_ACTIVE_KEY=v1
```

During rotation, deploy readers with both keys, switch
`STEM_SIGNING_ACTIVE_KEY`, then remove the retired key after old envelopes are
drained. Never put real keys in source control or logs.

For TLS, use the adapter's TLS options and Stem's certificate variables:

```bash
export STEM_TLS_CA_CERT=/etc/stem/ca.pem
export STEM_TLS_CLIENT_CERT=/etc/stem/client.pem
export STEM_TLS_CLIENT_KEY=/etc/stem/client-key.pem
```

Treat `STEM_TLS_ALLOW_INSECURE=true` as a temporary diagnostic switch, never a
production setting. Confirm URL schemes and certificate behavior with the
adapter documentation.

## Supervise and recover

Run workers under the service manager or container supervisor used by your
platform. Configure graceful shutdown, resource limits, log collection, and a
health check. Optional systemd/sysv templates are in
`packages/stem/templates/`; verify their assumptions against your image.

Keep an operator runbook for task/run IDs, draining and revoking work, DLQ
inspection and replay, store restoration, and credential rotation. Replay only
after fixing the cause.

## Release gate

In staging, exercise enqueue-to-completion, a handler retry, worker restart
during a task, and workflow restart at a checkpoint. Check alerts for backlog,
failed tasks, missing heartbeats, and DLQ growth. Record versions,
configuration, migrations, and rollback steps.

See [Reliability](./reliability.md), [Observe & Operate](./observability-and-ops.md),
and [Troubleshooting](./troubleshooting.md).
