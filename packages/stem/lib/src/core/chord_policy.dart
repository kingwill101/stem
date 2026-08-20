import 'package:meta/meta.dart';
import 'package:stem/src/core/contracts.dart';

/// Determines when a chord callback may run.
enum ChordPolicyKind {
  /// Require every body task to succeed.
  allOrFail,

  /// Wait for every body task to reach a terminal state and collect failures.
  collectTerminalResults,

  /// Wait for every body task and require at least [ChordPolicy.minSuccessful]
  /// successful results.
  allowPartial,
}

/// Failure policy for a Canvas chord.
@immutable
class ChordPolicy {
  /// Requires every body task to succeed. This is the default policy.
  const ChordPolicy.allOrFail()
    : kind = ChordPolicyKind.allOrFail,
      minSuccessful = null;

  /// Runs the callback after all body tasks are terminal, including failures.
  const ChordPolicy.collectTerminalResults()
    : kind = ChordPolicyKind.collectTerminalResults,
      minSuccessful = null;

  /// Runs the callback after all body tasks are terminal when at least
  /// [minSuccessful] tasks succeeded.
  const ChordPolicy.allowPartial({required int minSuccessful})
    : assert(minSuccessful > 0, 'minSuccessful must be positive'),
      kind = ChordPolicyKind.allowPartial,
      minSuccessful = minSuccessful;

  /// Reconstructs a policy persisted in group metadata.
  factory ChordPolicy.fromJson(Object? value) {
    if (value is! Map) return const ChordPolicy.allOrFail();
    final kind = switch (value['kind']?.toString()) {
      'collectTerminalResults' => ChordPolicyKind.collectTerminalResults,
      'allowPartial' => ChordPolicyKind.allowPartial,
      _ => ChordPolicyKind.allOrFail,
    };
    if (kind == ChordPolicyKind.allowPartial) {
      final minimum = (value['minSuccessful'] as num?)?.toInt();
      if (minimum != null && minimum > 0) {
        return ChordPolicy.allowPartial(minSuccessful: minimum);
      }
      return const ChordPolicy.allOrFail();
    }
    return switch (kind) {
      ChordPolicyKind.collectTerminalResults =>
        const ChordPolicy.collectTerminalResults(),
      ChordPolicyKind.allOrFail => const ChordPolicy.allOrFail(),
      ChordPolicyKind.allowPartial => const ChordPolicy.allOrFail(),
    };
  }

  /// The policy behavior.
  final ChordPolicyKind kind;

  /// Minimum successful body tasks for [ChordPolicyKind.allowPartial].
  final int? minSuccessful;

  /// Serializes this policy for durable group metadata.
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    if (minSuccessful != null) 'minSuccessful': minSuccessful,
  };

  /// Whether this status is eligible to dispatch the callback.
  bool shouldDispatch(GroupStatus status) {
    if (!status.isComplete) return false;
    final successful = status.results.values
        .where((result) => result.state == TaskState.succeeded)
        .length;
    return switch (kind) {
      ChordPolicyKind.allOrFail => successful == status.expected,
      ChordPolicyKind.collectTerminalResults => true,
      ChordPolicyKind.allowPartial => successful >= minSuccessful!,
    };
  }

  /// Whether the chord has reached a terminal failure under this policy.
  bool shouldFail(GroupStatus status) {
    final hasFailure = status.results.values.any(
      (result) =>
          result.state == TaskState.failed ||
          result.state == TaskState.cancelled,
    );
    if (kind == ChordPolicyKind.allOrFail && hasFailure) return true;
    return status.isComplete && !shouldDispatch(status);
  }

  @override
  bool operator ==(Object other) =>
      other is ChordPolicy &&
      other.kind == kind &&
      other.minSuccessful == minSuccessful;

  @override
  int get hashCode => Object.hash(kind, minSuccessful);
}
