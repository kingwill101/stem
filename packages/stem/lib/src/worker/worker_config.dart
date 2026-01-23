/// Configuration classes for worker behavior and lifecycle.
///
/// This library provides configuration options for:
/// - **Autoscaling**: Dynamically adjust worker concurrency based on load
/// - **Lifecycle**: Control shutdown behavior and isolate recycling
///
/// ## Autoscaling Configuration
///
/// [WorkerAutoscaleConfig] allows the worker to automatically scale its
/// isolate pool based on queue backlog and idle time:
///
/// ```dart
/// final worker = Worker(
///   // ... other params
///   autoscale: WorkerAutoscaleConfig(
///     enabled: true,
///     minConcurrency: 2,
///     maxConcurrency: 16,
///     backlogPerIsolate: 2.0,  // Scale up when backlog > 2 per isolate
///     idlePeriod: Duration(seconds: 60),  // Scale down after 60s idle
///   ),
/// );
/// ```
///
/// ## Lifecycle Configuration
///
/// [WorkerLifecycleConfig] controls shutdown behavior and isolate recycling:
///
/// ```dart
/// final worker = Worker(
///   // ... other params
///   lifecycle: WorkerLifecycleConfig(
///     installSignalHandlers: true,  // Handle SIGTERM/SIGINT
///     softGracePeriod: Duration(seconds: 30),
///     maxTasksPerIsolate: 1000,  // Recycle after 1000 tasks
///     maxMemoryPerIsolateBytes: 256 * 1024 * 1024,  // 256MB limit
///   ),
/// );
/// ```
///
/// See also:
/// - `Worker` for the main worker class that uses these configurations
/// - `TaskIsolatePool` for the isolate pool that implements recycling
library;

/// Autoscaling configuration for worker concurrency.
///
/// Controls how the worker dynamically adjusts its isolate pool size based
/// on queue backlog and idle time. When enabled, the worker will:
///
/// 1. **Scale Up**: When queue backlog exceeds [backlogPerIsolate] per isolate
/// 2. **Scale Down**: When idle for longer than [idlePeriod]
///
/// Cooldown periods ([scaleUpCooldown], [scaleDownCooldown]) prevent rapid
/// oscillation between sizes.
///
/// ## Example
///
/// ```dart
/// // Aggressive scaling for bursty workloads
/// WorkerAutoscaleConfig(
///   enabled: true,
///   minConcurrency: 1,
///   maxConcurrency: 32,
///   scaleUpStep: 4,
///   scaleDownStep: 2,
///   backlogPerIsolate: 1.0,
///   scaleUpCooldown: Duration(seconds: 2),
/// )
/// ```
class WorkerAutoscaleConfig {
  /// Creates an autoscaling configuration.
  const WorkerAutoscaleConfig({
    this.enabled = false,
    int? minConcurrency,
    this.maxConcurrency,
    this.scaleUpStep = 1,
    this.scaleDownStep = 1,
    this.backlogPerIsolate = 1.0,
    this.idlePeriod = const Duration(seconds: 30),
    this.tick = const Duration(seconds: 2),
    this.scaleUpCooldown = const Duration(seconds: 5),
    this.scaleDownCooldown = const Duration(seconds: 10),
  }) : minConcurrency = minConcurrency != null && minConcurrency > 0
           ? minConcurrency
           : 1;

  /// Disabled autoscaling profile.
  const WorkerAutoscaleConfig.disabled()
    : enabled = false,
      minConcurrency = 1,
      maxConcurrency = null,
      scaleUpStep = 1,
      scaleDownStep = 1,
      backlogPerIsolate = 1.0,
      idlePeriod = const Duration(seconds: 30),
      tick = const Duration(seconds: 2),
      scaleUpCooldown = const Duration(seconds: 5),
      scaleDownCooldown = const Duration(seconds: 10);

  /// Whether autoscaling is active.
  final bool enabled;

  /// Minimum number of isolates to keep running when autoscaling.
  final int minConcurrency;

  /// Maximum isolate concurrency allowed while autoscaling. When `null`, the
  /// worker's configured concurrency is used.
  final int? maxConcurrency;

  /// Number of isolates to add when scaling up.
  final int scaleUpStep;

  /// Number of isolates to remove when scaling down.
  final int scaleDownStep;

  /// Queue backlog required per isolate before scaling up.
  final double backlogPerIsolate;

  /// Idle period before scaling down.
  final Duration idlePeriod;

  /// Evaluation interval for autoscaler decisions.
  final Duration tick;

  /// Cooldown period between scale-up actions.
  final Duration scaleUpCooldown;

  /// Cooldown period between scale-down actions.
  final Duration scaleDownCooldown;

  /// Returns a copy of this config with the provided overrides.
  WorkerAutoscaleConfig copyWith({
    bool? enabled,
    int? minConcurrency,
    int? maxConcurrency,
    int? scaleUpStep,
    int? scaleDownStep,
    double? backlogPerIsolate,
    Duration? idlePeriod,
    Duration? tick,
    Duration? scaleUpCooldown,
    Duration? scaleDownCooldown,
  }) {
    return WorkerAutoscaleConfig(
      enabled: enabled ?? this.enabled,
      minConcurrency: minConcurrency ?? this.minConcurrency,
      maxConcurrency: maxConcurrency ?? this.maxConcurrency,
      scaleUpStep: scaleUpStep ?? this.scaleUpStep,
      scaleDownStep: scaleDownStep ?? this.scaleDownStep,
      backlogPerIsolate: backlogPerIsolate ?? this.backlogPerIsolate,
      idlePeriod: idlePeriod ?? this.idlePeriod,
      tick: tick ?? this.tick,
      scaleUpCooldown: scaleUpCooldown ?? this.scaleUpCooldown,
      scaleDownCooldown: scaleDownCooldown ?? this.scaleDownCooldown,
    );
  }
}

/// Lifecycle guard configuration for worker isolates and shutdown semantics.
///
/// Controls how the worker handles:
/// - **Process Signals**: SIGTERM, SIGINT, SIGQUIT handling
/// - **Shutdown Behavior**: Grace periods and forced termination
/// - **Isolate Recycling**: When to recycle isolates based on usage
///
/// ## Shutdown Modes
///
/// When [installSignalHandlers] is `true` (default), the worker installs
/// signal handlers that trigger graceful shutdown:
///
/// | Signal | Default Behavior |
/// |--------|-----------------|
/// | SIGTERM | Soft shutdown |
/// | SIGINT | Soft shutdown |
/// | SIGQUIT | Hard shutdown |
///
/// ## Isolate Recycling
///
/// Isolates can be recycled to prevent memory leaks or reset state:
///
/// - [maxTasksPerIsolate]: Recycle after N tasks (prevents memory growth)
/// - [maxMemoryPerIsolateBytes]: Recycle when RSS exceeds threshold
///
/// ## Example
///
/// ```dart
/// // Production configuration with aggressive recycling
/// WorkerLifecycleConfig(
///   installSignalHandlers: true,
///   softGracePeriod: Duration(seconds: 60),
///   forceShutdownAfter: Duration(seconds: 30),
///   maxTasksPerIsolate: 500,
///   maxMemoryPerIsolateBytes: 128 * 1024 * 1024, // 128MB
/// )
/// ```
///
/// See also:
/// - `WorkerShutdownMode` for shutdown mode semantics
/// - `IsolateRecycleReason` for recycling triggers
class WorkerLifecycleConfig {
  /// Creates lifecycle guard configuration for worker shutdown.
  const WorkerLifecycleConfig({
    this.installSignalHandlers = true,
    this.softGracePeriod = const Duration(seconds: 30),
    this.forceShutdownAfter = const Duration(seconds: 10),
    this.maxTasksPerIsolate,
    this.maxMemoryPerIsolateBytes,
  });

  /// Whether to install default signal handlers (SIGTERM/SIGINT/SIGQUIT).
  final bool installSignalHandlers;

  /// Grace period before escalating a soft shutdown to hard termination.
  final Duration softGracePeriod;

  /// Time to wait after issuing a hard shutdown before forcing cancellation.
  final Duration forceShutdownAfter;

  /// Max tasks per isolate before recycling; `null` disables the limit.
  final int? maxTasksPerIsolate;

  /// Memory threshold in bytes before recycling an isolate; `null` disables.
  final int? maxMemoryPerIsolateBytes;

  /// Returns a copy of this config with the provided overrides.
  WorkerLifecycleConfig copyWith({
    bool? installSignalHandlers,
    Duration? softGracePeriod,
    Duration? forceShutdownAfter,
    int? maxTasksPerIsolate,
    int? maxMemoryPerIsolateBytes,
  }) {
    return WorkerLifecycleConfig(
      installSignalHandlers:
          installSignalHandlers ?? this.installSignalHandlers,
      softGracePeriod: softGracePeriod ?? this.softGracePeriod,
      forceShutdownAfter: forceShutdownAfter ?? this.forceShutdownAfter,
      maxTasksPerIsolate: maxTasksPerIsolate ?? this.maxTasksPerIsolate,
      maxMemoryPerIsolateBytes:
          maxMemoryPerIsolateBytes ?? this.maxMemoryPerIsolateBytes,
    );
  }
}
