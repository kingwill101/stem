import 'dart:async';
import 'dart:convert';

import 'package:stem/src/core/payload_codec_registry.dart';
import 'package:stem/src/workflow/core/workflow_compensation.dart';
import 'package:stem/src/workflow/core/workflow_journal.dart';

/// Registration boundary for heterogeneous named compensation handlers.
abstract interface class HostedCompensationDefinition {
  /// Stable handler ID persisted with successful checkpoints.
  String get name;

  /// Reconstructs executable cleanup using a host codec snapshot.
  WorkflowCompensationHandler bind(PayloadCodecRegistry codecs);
}

/// A named, result-aware compensation registered when a host is constructed.
///
/// Registrations must be supplied again after restart. Completed-step inputs
/// are encoded snapshots, not serialized closures or mutable captures.
final class HostedCompensation<T> implements HostedCompensationDefinition {
  /// Creates a typed cleanup handler and its independent retry policy.
  const HostedCompensation({
    required this.name,
    required this.run,
    this.codec,
    this.retryPolicy = const WorkflowRetryPolicy(),
  });

  @override
  final String name;

  /// Decodes the successful result snapshot supplied to [run].
  final Codec<T, Object?>? codec;

  /// Independent cleanup attempt budget; first attempt is included.
  final WorkflowRetryPolicy retryPolicy;

  /// Cleanup operation invoked with the completed step's decoded value.
  final FutureOr<void> Function(WorkflowCompensationContext context, T value)
  run;

  @override
  WorkflowCompensationHandler bind(PayloadCodecRegistry codecs) {
    retryPolicy.validate();
    final selected = codec ?? codecs.codecFor<T>();
    return (context, input) => run(context, selected.decode(input));
  }
}
