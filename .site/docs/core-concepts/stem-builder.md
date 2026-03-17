---
title: stem_builder
sidebar_label: stem_builder
sidebar_position: 15
slug: /core-concepts/stem-builder
---

`stem_builder` generates workflow/task registries and typed workflow starters
from annotations, so you can avoid stringly-typed wiring.

## Install

```bash
dart pub add stem
dart pub add --dev build_runner stem_builder
```

## Define Annotated Workflows and Tasks

```dart
import 'package:stem/stem.dart';

part 'workflow_defs.stem.g.dart';

@WorkflowDefn(
  name: 'commerce.user_signup',
  kind: WorkflowKind.script,
  starterName: 'UserSignup',
)
class UserSignupWorkflow {
  Future<Map<String, Object?>> run(String email) async {
    final user = await createUser(email);
    await sendWelcomeEmail(email);
    return {'userId': user['id'], 'status': 'done'};
  }

  @WorkflowStep(name: 'create-user')
  Future<Map<String, Object?>> createUser(String email) async {
    return {'id': 'usr-$email'};
  }

  @WorkflowStep(name: 'send-welcome-email')
  Future<void> sendWelcomeEmail(String email) async {}
}

@TaskDefn(name: 'commerce.audit.log', runInIsolate: false)
Future<void> logAudit(TaskInvocationContext ctx, String event, String id) async {
  ctx.progress(1.0, data: {'event': event, 'id': id});
}
```

## Generate

```bash
dart run build_runner build --delete-conflicting-outputs
```

Generated output (`workflow_defs.stem.g.dart`) includes:

- `stemScripts`, `stemFlows`, `stemTasks`
- `registerStemDefinitions(...)`
- typed starters like `workflowApp.startUserSignup(...)`
- `StemWorkflowNames` constants
- convenience helpers such as `createStemGeneratedWorkflowApp(...)`

## Wire Into StemWorkflowApp

Use the generated registries directly with `StemWorkflowApp`:

```dart
final workflowApp = await StemWorkflowApp.fromUrl(
  'memory://',
  scripts: stemScripts,
  flows: stemFlows,
  tasks: stemTasks,
);

await workflowApp.start();
final runId = await workflowApp.startUserSignup(email: 'user@example.com');
```

If you already manage a `StemApp` for a larger service, reuse it instead of
bootstrapping a second app:

```dart
final stemApp = await StemApp.fromUrl(
  'redis://localhost:6379',
  adapters: const [StemRedisAdapter()],
  tasks: stemTasks,
);

final workflowApp = await StemWorkflowApp.create(
  stemApp: stemApp,
  scripts: stemScripts,
  flows: stemFlows,
  tasks: stemTasks,
);
```

## Parameter and Signature Rules

- Parameters after context must be required positional serializable values.
- Script workflow `run(...)` can be plain (no annotation required).
- `@WorkflowRun` is still supported for explicit run entrypoints.
- Step methods use `@WorkflowStep`.

