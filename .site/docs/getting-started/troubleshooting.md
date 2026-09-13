---
title: Troubleshooting
sidebar_label: Troubleshooting
sidebar_position: 7
slug: /getting-started/troubleshooting
---

Start with the symptom, then check the component that owns that state. The
optional `stem_cli` package must be configured with the application's adapter
context.

## Producer succeeds, but no worker runs the task

**Check:** compare broker connection, namespace, queue, routing, task name, and
serialization/registry configuration in both processes. Check worker
heartbeats and broker connectivity.

**Remedy:** use the same configuration and register the task in the worker.
With the CLI, run `stem worker ping`, `stem worker status`, and
`stem observe queues` after configuring its context.

## Tasks are repeatedly retried

**Check:** inspect the exception and `task-retry` signal. Determine whether the
failure is transient or permanent, and check the task retry policy and count.

**Remedy:** repair transient dependencies; otherwise bound the retry budget or
let the task reach the DLQ. Make external effects idempotent because delivery
is at least once.

## A task is in the DLQ

**Check:** inspect payload, task name/version, decode/signature error, and the
first failure. Malformed bytes are not repaired by retrying them.

**Remedy:** deploy a compatible handler or correct the producer, then replay a
small verified sample. Use `stem dlq list` and `stem dlq show`; confirm replay
or purge flags with the installed CLI's `--help`.

## A workflow is waiting or does not resume

**Check:** inspect the run and waiter topic. The emitted topic must exactly
match the topic passed to `awaitEvent`; verify the run is still waiting and the
payload is serializable.

**Remedy:** emit the matching event through the workflow API/CLI, or cancel the
run according to its policy. A suspended workflow is not necessarily failed.
See [workflow troubleshooting](../workflows/troubleshooting.md).

## A worker is redelivering or duplicates appear

**Check:** compare broker visibility timeout, worker lease duration, renewal
cadence, handler duration, and shutdown mode. Look for lease-renewal failures
and process crashes.

**Remedy:** size leases for the operation, keep renewal ahead of expiry, and
make side effects idempotent. Built-in terminal-result arbitration cannot make
an external HTTP call, email, or mobile execution exactly once.

## TLS or signing fails

**Check:** verify certificate paths and hostname validation, then verify
`STEM_SIGNING_ALGORITHM`, active key, and matching HMAC/Ed25519 key sets.

**Remedy:** deploy CA/public keys to verifiers and rotate with overlap. Use
`STEM_TLS_ALLOW_INSECURE=true` only for short local diagnosis, then remove it.
Never print secrets while debugging.

## Namespace or backend state is missing

**Check:** compare namespace and adapter endpoint exactly, including database
and schema. Confirm durable stores are reachable and migrated.

**Remedy:** correct shared configuration and run the adapter's documented
migrations. Missing telemetry does not imply missing task state.
