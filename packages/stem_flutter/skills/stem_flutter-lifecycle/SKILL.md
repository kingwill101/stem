---
name: stem_flutter-lifecycle
description: >-
  Use when hosting StemApp or WorkflowHost in Flutter, wiring task registration
  and workflow observation to app lifecycle, or deciding what workers can do in the
  foreground and background.
---

# Stem Flutter lifecycle

## Rules

- Call `StemFlutter.createApp` after Flutter binding initialization (the method
  ensures it) and retain the returned app above individual screens.
- `createApp` does not start consumption. Start explicitly after registration
  and after the app has established the resources it needs.
- Call `app.shutdown()` exactly once during orderly teardown. Do not close the
  app from a transient widget unless that widget owns the whole runtime.
- The worker runs in the calling isolate. Inline asynchronous handlers may use
  Flutter plugins; CPU-heavy handlers need an isolate-capable task design.
- `StemFlutter.defaultWorkerConfig` disables desktop process signal handlers and
  defaults local concurrency/prefetch to one. Override deliberately and test
  the selected configuration on the target platform.
- Flutter lifecycle callbacks are not an OS scheduler. Paused/terminated apps
  may not execute Dart code; use platform-approved background facilities and
  reopen/recover persisted work when the platform invokes the app.
- Persistence, retries, and lease recovery do not make external side effects
  exactly once. Handlers must be idempotent.

## Workflow host ownership

- Use `WorkflowHostController(factory: ...)` for an owned host or
  `WorkflowHostController(host: ...)` for a borrowed host.
- `WorkflowHostScope` borrows its controller. Removing the widget does not
  dispose the controller; the application owner must close/dispose it.
- The factory is responsible for mobile-safe worker and storage configuration.
  The controller does not reconfigure the host returned by the factory.
- Startup and foreground resume coalesce bounded recovery scans. Inspect
  `controller.recoveryReport.errors` as well as `controller.error`; a completed
  scan may still report individual run failures.
- Pausing does not cancel workflows. Closing an owned controller closes its
  host, not persisted workflow runs. A borrowed host remains caller-owned.
- `HostedRunBuilder<R>` renders `WorkflowRunView` snapshots, not decoded
  results or every lifecycle event. Use `run.result` for the typed result.
- Prefer `await controller.close()` before disposing the controller during
  awaited teardown; never assume the OS will allow a final teardown callback.

## Example

```dart
import 'package:flutter/widgets.dart';
import 'package:stem_flutter/stem_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final app = await StemFlutter.createApp();
  await app.start();
  runApp(const Placeholder());

  // Tie this to the owner of the runtime, not an individual task screen:
  // await app.shutdown();
}
```

Pass registered handlers or a generated `StemModule` to `createApp` in a real
application; the empty call above only shows the lifecycle boundary. In
production, keep the app in a service/provider and dispose it when that owner
is destroyed.

## Validation checklist

1. Test cold start, hot restart, pause/resume, and orderly shutdown.
2. Verify plugins used by handlers are legal in the isolate and lifecycle where
   they run.
3. Verify the platform background mechanism separately; Stem does not grant
   background execution.
