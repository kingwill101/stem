/// Runtime-neutral Stem API for producers and event-driven task execution.
///
/// This entrypoint excludes VM worker lifecycle, process signals, isolate
/// transport, filesystem stores, and host-specific configuration.
library;

export 'src/core/contracts.dart';
export 'src/core/encoder_keys.dart';
export 'src/core/envelope.dart';
export 'src/core/function_task_handler.dart';
export 'src/core/payload_codec.dart';
export 'src/core/payload_map.dart';
export 'src/core/retry.dart';
export 'src/core/stem.dart';
export 'src/core/task_invocation.dart';
export 'src/core/task_payload_encoder.dart';
export 'src/core/task_processor.dart';
export 'src/core/task_result.dart';
export 'src/routing/routing_config.dart';
export 'src/routing/routing_registry.dart';
export 'src/scheduler/schedule_calculator.dart';
export 'src/scheduler/schedule_spec.dart';
export 'src/security/signing.dart';
