/// Stable, high-level Stem API.
///
/// New applications should prefer this library. The historical
/// `package:stem/stem.dart` barrel remains available for compatibility, while
/// low-level transport, signal, and instrumentation APIs are collected under
/// `package:stem/advanced.dart`.
library;

export 'src/bootstrap/factories.dart';
export 'src/bootstrap/stem_app.dart';
export 'src/bootstrap/stem_client.dart';
export 'src/bootstrap/stem_module.dart';
export 'src/bootstrap/stem_stack.dart';
export 'src/bootstrap/workflow_app.dart';
export 'src/canvas/canvas.dart';
export 'src/core/contracts.dart'
    hide
        InMemoryTaskRegistry,
        TaskArgsEncoder,
        TaskEnqueuer,
        TaskEnqueuerBuilderExtension,
        TaskHandler,
        TaskInputContext,
        TaskInputContextArgs,
        TaskRegistrationEvent,
        TaskRegistry;
export 'src/core/payload_codec.dart';
export 'src/core/payload_map.dart';
export 'src/core/retry.dart';
export 'src/core/stem.dart';
export 'src/core/task_invocation.dart';
export 'src/core/task_result.dart';
export 'src/routing/routing_config.dart';
export 'src/scheduler/schedule_spec.dart';
export 'src/security/signing.dart';
export 'src/worker/worker.dart';
export 'src/worker/worker_config.dart';
export 'src/workflow/workflow.dart';
