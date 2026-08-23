import 'package:stem/src/core/chord_policy.dart';

/// Metadata keys used for chord coordination.
class ChordMetadata {
  const ChordMetadata._();

  /// Serialized callback envelope stored on the group descriptor.
  static const String callbackEnvelope = 'stem.chord.callbackEnvelope';

  /// Timestamp recorded when the callback is dispatched.
  static const String dispatchedAt = 'stem.chord.dispatchedAt';

  /// Identifier of the callback task associated with the chord.
  static const String callbackTaskId = 'stem.chord.callbackTaskId';

  /// Serialized [ChordPolicy] stored on the group descriptor.
  static const String policy = 'stem.chord.policy';

  /// Failure summaries passed to callbacks for non-failing policies.
  static const String failures = 'stem.chord.failures';
}
