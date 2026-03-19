import 'package:stem/src/core/payload_codec.dart';

/// Typed reference to a workflow resume event topic.
///
/// This bundles the durable topic name with an optional payload codec so
/// callers do not need to repeat a raw topic string and separate codec across
/// wait and emit sites.
class WorkflowEventRef<T> {
  /// Creates a typed workflow event reference.
  const WorkflowEventRef({
    required this.topic,
    this.codec,
  });

  /// Durable topic name used to suspend and resume workflow runs.
  final String topic;

  /// Optional codec for encoding and decoding event payloads.
  final PayloadCodec<T>? codec;
}
