/// Low-level and compatibility APIs for Stem integrations.
///
/// Prefer `package:stem/stable.dart` for application code. This entrypoint
/// exposes the full historical surface for custom transports, instrumentation,
/// signals, and framework integrations that need implementation details.
library;

export 'src/backend/encoding_result_backend.dart';
export 'src/control/control_messages.dart';
export 'src/control/file_revoke_store.dart';
export 'src/control/revoke_store.dart';
export 'src/core/chord_metadata.dart';
export 'src/core/chord_policy.dart';
export 'src/core/clock.dart' hide FakeStemClock;
export 'src/core/config.dart';
export 'src/core/contracts.dart';
export 'src/core/encoder_keys.dart';
export 'src/core/envelope.dart';
export 'src/core/function_task_handler.dart';
export 'src/core/queue_events.dart';
export 'src/core/stem_event.dart';
export 'src/core/task_payload_encoder.dart';
export 'src/core/unique_task_coordinator.dart';
export 'src/observability/config.dart';
export 'src/observability/heartbeat.dart';
export 'src/observability/heartbeat_transport.dart';
export 'src/observability/metrics.dart';
export 'src/observability/snapshots.dart';
export 'src/observability/tracing.dart';
export 'src/routing/routing_registry.dart';
export 'src/scheduler/beat.dart';
export 'src/scheduler/schedule_calculator.dart';
export 'src/scheduler/solar_calculator.dart';
export 'src/security/tls.dart';
export 'src/signals/emitter.dart';
export 'src/signals/middleware.dart';
export 'src/signals/payloads.dart';
export 'src/signals/signal.dart';
export 'src/signals/stem_signals.dart';
export 'stable.dart';
