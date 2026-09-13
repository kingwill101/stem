---
title: Getting Started
sidebar_position: 0
slug: /getting-started
---

Choose the path that matches the thing you are building:

- **A hosted workflow** — a typed, long-running process with checkpoints,
  durable waits, and a result handle. Start with [Introduction](./intro.md),
  then [Quick Start](./quick-start.md).
- **A generated task** — a background job submitted to a queue and run by a
  worker. Start with [First Steps](./first-steps.md), then
  [Choosing a backend](./choosing-a-backend.md).

Both paths use the same Stem runtime and can live in one application. Once the
basics work, continue to [Next Steps](./next-steps.md) or the detailed
[Workflows](../workflows/index.md) guide.

## Before you begin

This documentation follows the current source, targeting Dart 3.13 or later.
Published releases can lag behind it. In particular, the hosted quick start
requires a package version that exports `WorkflowHost`; use the matching
release documentation or a local checkout if your resolved version lacks it.
See the [source-vs-published note](./intro.md#source-checkouts-and-published-packages).

```bash
dart --version
dart create my_stem_app
cd my_stem_app
dart pub add stem
```
