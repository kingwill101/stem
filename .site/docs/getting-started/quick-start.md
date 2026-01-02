---
title: Quick Start
sidebar_label: Quick Start
sidebar_position: 2
slug: /getting-started/quick-start
---

Spin up Stem in minutes with nothing but Dart installed. This walkthrough stays
fully in-memory so you can focus on the core pipeline: enqueueing, retries,
delays, priorities, and chaining work together.

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## 1. Create a Demo Project

```bash
dart create stem_quickstart
cd stem_quickstart

# Add Stem as a dependency and activate the CLI.
dart pub add stem
dart pub global activate stem
```

Add the Dart pub cache to your `PATH` so the `stem` CLI is reachable:

```bash
export PATH="$HOME/.pub-cache/bin:$PATH"
stem --version
```

## 2. Register Tasks with Options

Replace the generated `bin/stem_quickstart.dart` with the script built from the
snippets below. The full, runnable version lives at
`packages/stem/example/docs_snippets/lib/quick_start.dart` in the repository.

### Define task handlers

Each task declares its name and retry/timeout options.

<Tabs>
<TabItem value="resize" label="Image resize task">

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/quick_start.dart#quickstart-task-resize

```

</TabItem>
<TabItem value="email" label="Email receipt task">

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/quick_start.dart#quickstart-task-email

```

</TabItem>
</Tabs>

### Bootstrap worker + Stem

Use `StemApp` to wire tasks, the in-memory broker/backend, and the worker:

<Tabs>
<TabItem value="bootstrap" label="Registry + runtime bootstrap">

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/quick_start.dart#quickstart-bootstrap

```

</TabItem>
</Tabs>

### Enqueue tasks

Publish an immediate task plus a delayed task with custom metadata:

<Tabs>
<TabItem value="enqueue" label="Immediate + delayed enqueues">

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/quick_start.dart#quickstart-enqueue

```

</TabItem>
</Tabs>

Run the script:

```bash
dart run bin/stem_quickstart.dart
```

Stem handles retries, time limits, rate limiting, and priority ordering even
with the in-memory adapters—great for tests and local demos.

## 3. Compose Work with Canvas

Stem’s canvas API lets you chain, group, or create chords of tasks. Add this
helper to the bottom of the file above to try a chain:

<Tabs>
<TabItem value="canvas-helper" label="Canvas chain helper">

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/quick_start.dart#quickstart-canvas-example

```

</TabItem>
</Tabs>

Then call it from `main` once the worker has started:

<Tabs>
<TabItem value="canvas-call" label="Invoke the canvas helper">

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/quick_start.dart#quickstart-canvas-call

```

</TabItem>
</Tabs>

Finally, inspect the result state before shutting down:

<Tabs>
<TabItem value="inspect" label="Inspect task result">

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/quick_start.dart#quickstart-inspect

```

</TabItem>
</Tabs>

Each step records progress in the result backend, and failures trigger retries
or DLQ placement according to `TaskOptions`.

## 4. Peek at Retries and DLQ

Force a failure to see retry behaviour:

<Tabs>
<TabItem value="failure" label="Simulate retry + DLQ">

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/quick_start_failure.dart#quickstart-email-failure

```

</TabItem>
</Tabs>

The retry pipeline and DLQ logic are built into the worker. When the task
exceeds `maxRetries`, the envelope moves to the DLQ; you’ll learn how to inspect
and replay those entries in the next guide.

## 5. Where to Next

- Connect Stem to Redis/Postgres, try broadcast routing, and run Beat in
  [Connect to Infrastructure](./developer-environment.md).
- Explore worker control commands, DLQ tooling, and OpenTelemetry export in
  [Observe & Operate](./observability-and-ops.md).
- Keep the script—you’ll reuse the tasks and app bootstrap in later steps.
