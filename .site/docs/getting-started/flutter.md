---
title: Flutter workflows
sidebar_label: Flutter
sidebar_position: 6
slug: /getting-started/flutter
---

Use `stem_flutter` when a Flutter UI needs to observe a hosted workflow.
`WorkflowHostController` owns or receives a core `WorkflowHost`, and
`WorkflowHostScope` makes it available to descendant widgets.

This setup fragment belongs to an application-level owner. It is not a complete
Flutter app; pass your workflow screen to `workflowArea` from the widget tree.

```dart
import 'package:flutter/material.dart';
import 'package:stem_flutter/stem_flutter.dart';

final workflow = HostedWorkflow<String, String>(
  name: 'mobile.greeting',
  run: (context, name) =>
      context.step('greet', () => 'Hello, $name!'),
);

final controller = WorkflowHostController(
  factory: () => WorkflowHost.create(
    workflows: [workflow],
    createApp: (definitions) => StemWorkflowApp.inMemory(
      workflows: definitions,
      workerConfig: StemFlutter.defaultWorkerConfig,
    ),
  ),
);

Widget workflowArea(Widget child) => WorkflowHostScope(
  controller: controller,
  loadingBuilder: (_) => const CircularProgressIndicator(),
  errorBuilder: (_, error, stack) => Text('Could not start workflows: $error'),
  child: child,
);
```

The scope starts its controller and triggers bounded recovery on foreground
resume. It does **not** own the controller: await `controller.close()` during
awaited teardown and dispose the controller when its application owner ends.
For a borrowed host, that host remains the caller's responsibility. Do not
create a new controller every time a screen builds.

Treat this as a foreground observation boundary: closing the controller or
host stops local observation, not a persisted workflow. Use a persistent core
host for restart durability and keep external effects idempotent because
workflow execution is at least once.

## Add local persistence

`stem_flutter` is adapter-neutral. Use
[`stem_flutter_sqlite`](https://pub.dev/packages/stem_flutter_sqlite) for
managed local task storage and database asset initialization. Workflow
persistence additionally requires a workflow store; keeping only task results
in SQLite is not enough. Follow that package's workflow-store setup for the
release you use.

## Background execution is a separate decision

Foreground lifecycle recovery does not grant execution while the OS suspends
or terminates your app. Keep Android/iOS scheduling and permissions in the
application. In an OS-granted callback, a fresh task app can use
`runUntilIdle` with an explicit time budget; it does not force arbitrary
inline work to stop or extend the OS deadline.

See the [`stem_flutter` package documentation](https://pub.dev/packages/stem_flutter)
for the release-specific widget lifecycle and controller API.
