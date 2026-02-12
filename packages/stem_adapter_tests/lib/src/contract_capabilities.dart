/// Feature capability flags for broker contract tests.
class BrokerContractCapabilities {
  /// Creates broker contract capability flags.
  const BrokerContractCapabilities({
    this.verifyPriorityOrdering = true,
    this.verifyBroadcastFanout = false,
  });

  /// Whether the contract should verify queue priority ordering behavior.
  final bool verifyPriorityOrdering;

  /// Whether the contract should verify broadcast fan-out behavior.
  final bool verifyBroadcastFanout;
}

/// Feature capability flags for result backend contract tests.
class ResultBackendContractCapabilities {
  /// Creates result backend contract capability flags.
  const ResultBackendContractCapabilities({
    this.verifyTaskStatusExpiry = true,
    this.verifyGroupExpiry = true,
    this.verifyChordClaiming = true,
    this.verifyWorkerHeartbeats = true,
    this.verifyHeartbeatExpiry = true,
  });

  /// Whether task status expiration behavior should be verified.
  final bool verifyTaskStatusExpiry;

  /// Whether group expiration behavior should be verified.
  final bool verifyGroupExpiry;

  /// Whether chord-claim semantics should be verified.
  final bool verifyChordClaiming;

  /// Whether worker heartbeat persistence/expiry should be verified.
  final bool verifyWorkerHeartbeats;

  /// Whether worker heartbeat expiry behavior should be verified.
  final bool verifyHeartbeatExpiry;
}

/// Feature capability flags for workflow store contract tests.
class WorkflowStoreContractCapabilities {
  /// Creates workflow store contract capability flags.
  const WorkflowStoreContractCapabilities({
    this.verifyVersionedCheckpoints = true,
    this.verifyRunLeases = true,
    this.verifyWatcherRegistry = true,
    this.verifyRunsWaitingOn = true,
    this.verifyFilteredRunListing = true,
  });

  /// Whether versioned checkpoint behavior should be verified.
  final bool verifyVersionedCheckpoints;

  /// Whether run claiming/lease behavior should be verified.
  final bool verifyRunLeases;

  /// Whether watcher registration/listing behavior should be verified.
  final bool verifyWatcherRegistry;

  /// Whether waiting-topic lookup behavior should be verified.
  final bool verifyRunsWaitingOn;

  /// Whether filtered run listing behavior should be verified.
  final bool verifyFilteredRunListing;
}

/// Feature capability flags for lock store contract tests.
class LockStoreContractCapabilities {
  /// Creates lock store contract capability flags.
  const LockStoreContractCapabilities({
    this.verifyOwnerLookup = true,
    this.verifyRenewSemantics = true,
  });

  /// Whether `ownerOf` behavior should be verified.
  final bool verifyOwnerLookup;

  /// Whether lock renewal behavior should be verified.
  final bool verifyRenewSemantics;
}
