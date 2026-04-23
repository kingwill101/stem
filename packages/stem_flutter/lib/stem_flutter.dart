/// Flutter coordination helpers for hosting and observing Stem workers.
///
/// This library contains the Flutter-facing pieces that are independent of any
/// specific broker or backend adapter. Use `StemFlutterWorkerHost` to
/// supervise a worker isolate, `StemFlutterQueueMonitor` to poll queue and
/// heartbeat state, and `StemFlutterQueueSnapshot` to drive compact UI views.
library;

export 'src/monitor/stem_flutter_queue_monitor.dart'
    show StemFlutterQueueMonitor;
export 'src/monitor/stem_flutter_queue_snapshot.dart'
    show StemFlutterQueueSnapshot, StemFlutterTrackedJob;
export 'src/runtime/stem_flutter_dependency_bootstrap.dart'
    show
        ensureStemFlutterDependenciesInitialized,
        initializeStemFlutterBackgroundDependencies,
        preloadStemFlutterDependencyAssets;
export 'src/runtime/stem_flutter_worker_host.dart' show StemFlutterWorkerHost;
export 'src/runtime/stem_flutter_worker_signal.dart'
    show
        StemFlutterWorkerSignal,
        StemFlutterWorkerSignalType,
        StemFlutterWorkerStatus;
