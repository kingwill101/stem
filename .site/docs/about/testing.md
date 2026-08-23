---
title: Testing and Quality Gates
sidebar_label: Testing
sidebar_position: 2
slug: /about/testing
---

Stem treats tests as evidence for runtime guarantees, not as a substitute for
adapter-specific operational validation. Run the checks relevant to the
package and behavior you changed.

## Core development loop

From the repository root:

```sh
dart pub get
dart run tool/check_examples.dart --skip-diff
```

Then run the core package gates:

```sh
cd packages/stem
dart format lib test --set-exit-if-changed
dart analyze --fatal-infos
dart test --exclude-tags soak --fail-fast
```

Examples are part of the user-facing API. The example checker discovers every
example under the root workspace packages, resolves its dependencies, runs
code generation where needed and analyzes the result.

## Package and adapter validation

Run `dart format`, `dart analyze --fatal-infos` and the test suite for every
package affected by a change. Adapter changes should include the shared
contract tests and, when infrastructure is available, the real Redis or
Postgres integration tests.

The adapters do not all provide identical delivery, lease, delay or priority
guarantees. Read the broker caveats and test the selected deployment rather
than treating an in-memory pass as proof of distributed recovery.

## Reliability tests

Soak tests are tagged and excluded from the normal fast suite:

```sh
cd packages/stem
dart test --tags soak
```

Failure-oriented tests should cover duplicate delivery, acknowledgement
failure, lease loss, retry storms, worker shutdown, checkpoint recovery and
broker restart. Changes to persistence or scheduling should also run migration
upgrade and lease/fencing tests.

## Release gate

The release planner derives the package graph from workspace manifests and
checks package metadata, generated output, standalone resolution and publish
archives:

```sh
dart run tool/publish.dart --plan
```

A real release requires a clean tree and the exact commit used to produce the
artifacts. The aggregate CI workflow repeats package checks on Linux, Windows
and macOS, tests standalone source staging, and checks workspace examples.
