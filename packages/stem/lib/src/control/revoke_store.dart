import 'dart:async';
import 'dart:convert';

/// Represents a persisted revoke entry for a task.
class RevokeEntry {
  /// Creates a revoke entry snapshot.
  const RevokeEntry({
    required this.namespace,
    required this.taskId,
    required this.version,
    required this.issuedAt,
    this.terminate = false,
    this.reason,
    this.requestedBy,
    this.expiresAt,
  });

  /// Creates a [RevokeEntry] from a JSON map.
  factory RevokeEntry.fromJson(Map<String, Object?> json) {
    return RevokeEntry(
      namespace: json['namespace']! as String,
      taskId: json['taskId']! as String,
      version: (json['version']! as num).toInt(),
      issuedAt: DateTime.parse(json['issuedAt']! as String),
      terminate: json['terminate'] == true,
      reason: json['reason'] as String?,
      requestedBy: json['requestedBy'] as String?,
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt']! as String)
          : null,
    );
  }

  /// Logical namespace the revoke applies to.
  final String namespace;

  /// Identifier of the task to revoke.
  final String taskId;

  /// Monotonic version used to order revoke updates.
  final int version;

  /// When the revoke was issued.
  final DateTime issuedAt;

  /// Whether the task should be forcefully terminated if running.
  final bool terminate;

  /// Optional human-readable reason.
  final String? reason;

  /// Optional identifier for the requester.
  final String? requestedBy;

  /// Optional expiration for the revoke.
  final DateTime? expiresAt;

  /// Returns `true` when the revoke has an expiry and is past due.
  bool isExpired(DateTime clock) =>
      expiresAt != null && !expiresAt!.isAfter(clock);

  /// Serialises this entry to a JSON-compatible map.
  Map<String, Object?> toJson() => {
    'namespace': namespace,
    'taskId': taskId,
    'version': version,
    'issuedAt': issuedAt.toIso8601String(),
    'terminate': terminate,
    if (reason != null) 'reason': reason,
    if (requestedBy != null) 'requestedBy': requestedBy,
    if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
  };

  /// Returns a copy of this entry with the provided overrides.
  RevokeEntry copyWith({
    String? namespace,
    String? taskId,
    int? version,
    DateTime? issuedAt,
    bool? terminate,
    String? reason,
    String? requestedBy,
    DateTime? expiresAt,
  }) {
    return RevokeEntry(
      namespace: namespace ?? this.namespace,
      taskId: taskId ?? this.taskId,
      version: version ?? this.version,
      issuedAt: issuedAt ?? this.issuedAt,
      terminate: terminate ?? this.terminate,
      reason: reason ?? this.reason,
      requestedBy: requestedBy ?? this.requestedBy,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  @override
  String toString() => jsonEncode(toJson());
}

/// Storage abstraction for task revocations.
abstract class RevokeStore {
  /// Persists or updates the provided revoke [entries].
  ///
  /// Implementations MUST only update existing records when the entry version
  /// is greater than the stored value to maintain monotonic ordering.
  Future<List<RevokeEntry>> upsertAll(List<RevokeEntry> entries);

  /// Lists revoke entries for the given [namespace]. Implementations should
  /// include expired entries; callers can run [pruneExpired] to clean them up.
  Future<List<RevokeEntry>> list(String namespace);

  /// Removes expired entries and returns the number of records purged.
  Future<int> pruneExpired(String namespace, DateTime clock);

  /// Disposes underlying resources.
  Future<void> close();
}

/// Generates a monotonically increasing revoke version based on UTC time.
///
/// Useful for ordering revocation updates across distributed callers.
int generateRevokeVersion() => DateTime.now().toUtc().microsecondsSinceEpoch;
