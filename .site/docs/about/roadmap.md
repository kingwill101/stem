---
title: Roadmap
sidebar_label: Roadmap
slug: /about/roadmap
sidebar_position: 1
---

## Direction

The next release cycle is a hardening cycle. Stem already has a broad set of
queue, worker, scheduler, workflow and adapter features; the priority is to
narrow the public surface, make release artifacts reproducible and prove
failure behaviour before expanding the platform.

## Delivered foundations

These capabilities exist in the repository and are covered by package tests,
adapter contract tests or integration tests as applicable:

- Typed task definitions, DTO codecs and generated task/workflow definitions.
- Redis, Postgres, SQLite and in-memory broker/backend implementations.
- Explicit worker lifecycle, isolate execution and documented timeout modes.
- Retries, leases, acknowledgements, uniqueness coordination and revocation.
- Durable workflow checkpoints, suspension/resumption and external events.
- Scheduler time zones, jitter, persistence, leases and CLI control commands.
- OpenTelemetry context propagation and task/result instrumentation.
- Redis/Postgres distributed rate-limiter implementations and a Postgres
  transactional outbox integration.
- Adapter contract suites, standalone package staging and workspace example
  checks in CI.
- Atomic terminal-result arbitration in the built-in result backends, with
  worker tests covering lease-loss redelivery and late cross-worker
  completion.
- SQLite workflow persistence now has a restart-recovery integration test that
  reopens the store and resumes a checkpoint with replacement runtime and
  broker instances.
- SQLite and Postgres migration suites now cover current adapters reading
  legacy-shaped queue or lock records after upgrade.
- Core in-memory and SQLite file-backed throughput benchmarks now have checked
  minimum baselines and scheduled CI regression gates.

The existence of a feature does not mean that every adapter offers identical
guarantees. Read the broker and backend caveats before choosing a deployment.

## Current hardening

Work in this phase is focused on evidence and boundaries:

1. Exercise crash, lease-loss, duplicate-delivery, retry-storm and shutdown
   interleavings with failure-injection and soak tests.
2. Test schema upgrades, mixed-version workers and standalone package
   resolution without workspace dependency overrides.
3. Stabilise the public entrypoints and keep low-level compatibility APIs out
   of the recommended onboarding path.
4. Publish reproducible benchmark baselines for queue throughput, SQLite
   contention, workflow checkpoints and adapter recovery.
5. Document adapter-specific delivery, lease, delay, priority and recovery
   guarantees.

## Deliberately deferred

The following are not release priorities while the reliability work is in
progress:

- Compensation/saga primitives for workflows.
- Additional broker integrations.
- A broader dashboard product; the current dashboard remains experimental.
- Exactly-once execution claims for external side effects.
- More Canvas policies or composition features beyond the semantics already
  implemented.

## Contribution gate

Before proposing a release-facing change, run the package checks relevant to
the change, including:

```sh
dart run tool/check_examples.dart --skip-diff
dart run tool/publish.dart --plan
```

For package-level work, also run `dart format`, `dart analyze --fatal-infos`
and the package test suite. Changes to generated definitions must leave the
working tree clean after generation.

## Status language

Stem should be described as experimental until the project has accumulated
long-running fault-test evidence, compatibility guarantees, migration stories
and recovery reports for the supported adapters.
