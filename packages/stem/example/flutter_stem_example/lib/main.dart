import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stem/stem.dart';
import 'package:stem_flutter/stem_flutter.dart';
import 'package:stem_flutter_sqlite/stem_flutter_sqlite.dart';

const String _queueName = 'mobile-demo';
const String _taskName = 'demo.sleep_echo';
const String _workerId = 'mobile-worker';
const Duration _workerHeartbeatInterval = Duration(seconds: 2);
const Duration _monitorPollInterval = Duration(seconds: 1);
const Duration _brokerPollInterval = Duration(milliseconds: 250);
const Duration _brokerSweepInterval = Duration(seconds: 2);
const Duration _brokerVisibilityTimeout = Duration(seconds: 6);
const Duration _producerMaintenanceInterval = Duration.zero;
const Duration _monitorCleanupInterval = Duration(days: 3650);

Future<Object?> _sleepEchoTask(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  final label = args['label'] as String? ?? 'job';
  final delayMs = args['delayMs'] as int? ?? 1500;

  await Future<void>.delayed(Duration(milliseconds: delayMs));

  return 'Completed $label at ${DateTime.now().toIso8601String()}';
}

List<TaskHandler<Object?>> _taskHandlers() {
  return <TaskHandler<Object?>>[
    FunctionTaskHandler<String>.inline(
      name: _taskName,
      entrypoint: _sleepEchoTask,
      options: const TaskOptions(queue: _queueName),
      metadata: const TaskMetadata(
        description: 'SQLite-backed mobile demo task.',
        tags: <String>['flutter', 'sqlite', 'mobile'],
      ),
    ),
  ];
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureStemLogging(
    level: Level.debug,
    format: StemLogFormat.plain,
    enableConsole: true,
  );
  stemLogger.info('Flutter example booting');
  runApp(const StemFlutterExampleApp());
}

class StemFlutterExampleApp extends StatelessWidget {
  const StemFlutterExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stem Flutter Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          brightness: Brightness.light,
        ),
      ),
      home: const QueueMonitorPage(),
    );
  }
}

class QueueMonitorPage extends StatefulWidget {
  const QueueMonitorPage({super.key});

  @override
  State<QueueMonitorPage> createState() => _QueueMonitorPageState();
}

class _QueueMonitorPageState extends State<QueueMonitorPage> {
  StemFlutterSqliteRuntime? _runtime;
  StemFlutterWorkerHost? _workerHost;
  StemFlutterQueueMonitor? _monitor;
  StreamSubscription<StemFlutterQueueSnapshot>? _monitorSub;

  bool _isBooting = true;
  String? _bootError;
  int _jobCounter = 0;
  StemFlutterQueueSnapshot _snapshot = const StemFlutterQueueSnapshot();

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    unawaited(_shutdownResources());
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      stemLogger.info('Resolving mobile storage layout');
      final layout = await StemFlutterStorageLayout.applicationSupport(
        directoryName: 'stem_flutter_example',
      );
      stemLogger.info(
        'Opening producer/runtime stores',
        stemLogContext(
          component: 'flutter_example',
          subsystem: 'bootstrap',
          fields: <String, Object?>{
            'brokerPath': layout.brokerFile.path,
            'backendPath': layout.backendFile.path,
          },
        ),
      );

      final runtime = await StemFlutterSqliteRuntime.open(
        layout: layout,
        tasks: _taskHandlers(),
        brokerVisibilityTimeout: _brokerVisibilityTimeout,
        brokerPollInterval: _brokerPollInterval,
        producerSweeperInterval: _producerMaintenanceInterval,
        backendCleanupInterval: _monitorCleanupInterval,
      );
      stemLogger.info('Producer runtime ready');

      final rootToken = RootIsolateToken.instance;
      if (rootToken == null) {
        throw StateError('RootIsolateToken.instance was null.');
      }

      final workerHost = await StemFlutterSqliteWorkerLauncher.spawn(
        entrypoint: _workerIsolateMain,
        layout: layout,
        rootIsolateToken: rootToken,
        brokerPollInterval: _brokerPollInterval,
        brokerSweeperInterval: _brokerSweepInterval,
        brokerVisibilityTimeout: _brokerVisibilityTimeout,
      );
      stemLogger.info('Worker isolate spawned');

      final monitor = StemFlutterQueueMonitor(
        backend: runtime.backend,
        broker: runtime.broker,
        queueName: _queueName,
        workerId: _workerId,
        pollInterval: _monitorPollInterval,
        heartbeatInterval: _workerHeartbeatInterval,
      );
      await monitor.bindWorkerSignals(workerHost.signals);

      final monitorSub = monitor.snapshots.listen((snapshot) {
        if (!mounted) return;
        setState(() {
          _snapshot = snapshot;
        });
      });

      if (!mounted) {
        await monitorSub.cancel();
        await monitor.dispose();
        await workerHost.dispose();
        await runtime.close();
        return;
      }

      await monitor.start();

      if (!mounted) {
        await monitorSub.cancel();
        await monitor.dispose();
        await workerHost.dispose();
        await runtime.close();
        return;
      }

      setState(() {
        _runtime = runtime;
        _workerHost = workerHost;
        _monitor = monitor;
        _monitorSub = monitorSub;
        _isBooting = false;
      });
    } catch (error, stackTrace) {
      stemLogger.error('Flutter example bootstrap failed: $error', stackTrace);
      if (!mounted) return;
      setState(() {
        _bootError = '$error\n$stackTrace';
        _isBooting = false;
      });
    }
  }

  Future<void> _shutdownResources() async {
    await _monitorSub?.cancel();
    await _monitor?.dispose();
    await _workerHost?.dispose();
    await _runtime?.close();

    _workerHost = null;
    _monitor = null;
    _runtime = null;
    _monitorSub = null;
  }

  Future<void> _enqueueJob() async {
    final producer = _runtime?.stem;
    if (producer == null) return;

    final nextJobNumber = _jobCounter + 1;
    final label = 'Job $nextJobNumber';

    setState(() {
      _jobCounter = nextJobNumber;
    });

    final taskId = await producer.enqueue(
      _taskName,
      args: <String, Object?>{
        'label': label,
        'delayMs': 1200 + (nextJobNumber % 3) * 600,
      },
      meta: <String, Object?>{'label': label},
      options: const TaskOptions(queue: _queueName),
    );
    stemLogger.info(
      'Queued demo task',
      stemLogContext(
        component: 'flutter_example',
        subsystem: 'producer',
        fields: <String, Object?>{'taskId': taskId, 'label': label},
      ),
    );

    await _monitor?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final workerDetail = _snapshot.workerDetailPreview;

    return Scaffold(
      appBar: AppBar(title: const Text('Stem Queue Monitor')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF99F6E4)),
                ),
                child: Column(
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'Worker',
                                style: textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                workerDetail == null || workerDetail.isEmpty
                                    ? 'Waiting for worker updates'
                                    : workerDetail,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF475569),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        _WorkerStateChip(state: _snapshot.workerStatus),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        _MetricTile(
                          label: 'pending',
                          value: '${_snapshot.pendingCount ?? 0}',
                        ),
                        _MetricTile(
                          label: 'inflight',
                          value: '${_snapshot.inflightCount ?? 0}',
                        ),
                        _MetricTile(
                          label: 'tracked',
                          value: '${_snapshot.jobs.length}',
                        ),
                        _MetricTile(
                          label: 'heartbeat',
                          value: _formatTimestamp(_snapshot.lastHeartbeatAt),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _runtime == null || _isBooting
                      ? null
                      : _enqueueJob,
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('Push Job'),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Recent jobs',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              if (_isBooting)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_bootError != null)
                Expanded(
                  child: SingleChildScrollView(
                    child: SelectableText(_bootError!),
                  ),
                )
              else if (_snapshot.jobs.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      (_snapshot.pendingCount ?? 0) > 0 ||
                              (_snapshot.inflightCount ?? 0) > 0
                          ? 'Waiting for the worker to publish job status...'
                          : 'No jobs queued yet.',
                      style: textTheme.titleMedium,
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: _snapshot.jobs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (BuildContext context, int index) {
                      final job = _snapshot.jobs[index];
                      return _JobCard(job: job);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _workerIsolateMain(Map<String, Object?> config) async {
  final bootstrap = StemFlutterSqliteWorkerBootstrap.fromMessage(config);

  StreamSubscription<WorkerEvent>? eventsSub;
  Worker? worker;
  StemFlutterSqliteWorkerStores? stores;
  ReceivePort? commands;
  var workerStarted = false;

  try {
    configureStemLogging(
      level: Level.debug,
      format: StemLogFormat.plain,
      enableConsole: true,
    );
    stemLogger.info('Worker isolate bootstrap starting');
    bootstrap.sendPort.send(
      const StemFlutterWorkerSignal.status(
        status: StemFlutterWorkerStatus.starting,
        detail: 'Initializing background isolate',
      ).toMessage(),
    );

    await bootstrap.initializeBackgroundDependencies();
    stemLogger.info('Worker isolate dependencies initialized');

    stores = await StemFlutterSqliteWorkerStores.open(bootstrap);
    stemLogger.info(
      'Worker stores ready',
      stemLogContext(
        component: 'flutter_example',
        subsystem: 'worker',
        fields: <String, Object?>{
          'brokerPath': bootstrap.brokerPath,
          'backendPath': bootstrap.backendPath,
        },
      ),
    );

    worker = Worker(
      broker: stores.broker,
      backend: stores.backend,
      tasks: _taskHandlers(),
      queue: _queueName,
      consumerName: _workerId,
      concurrency: 1,
      prefetch: 1,
      heartbeatInterval: _workerHeartbeatInterval,
      workerHeartbeatInterval: _workerHeartbeatInterval,
    );
    commands = ReceivePort();
    eventsSub = worker.events.listen((event) {
      stemLogger.info(
        'Worker event ${event.type.name}',
        stemLogContext(
          component: 'flutter_example',
          subsystem: 'worker_event',
          fields: <String, Object?>{
            'envelopeId': event.envelopeId,
            'error': event.error?.toString(),
          },
        ),
      );
      if (event.type == WorkerEventType.error ||
          event.type == WorkerEventType.timeout) {
        bootstrap.sendPort.send(
          StemFlutterWorkerSignal.warning(
            event.error?.toString() ?? event.type.name,
          ).toMessage(),
        );
      }
    });

    await worker.start();
    workerStarted = true;
    stemLogger.info('Worker started');
    bootstrap.sendPort.send(
      StemFlutterWorkerSignal.ready(
        commandPort: commands.sendPort,
        detail: 'Worker isolate ready.',
      ).toMessage(),
    );

    await for (final dynamic message in commands) {
      if (message is Map && message['type'] == 'shutdown') {
        stemLogger.info('Worker isolate received shutdown request');
        break;
      }
    }
  } catch (error, stackTrace) {
    stemLogger.error('Worker isolate bootstrap failed: $error', stackTrace);
    bootstrap.sendPort.send(
      StemFlutterWorkerSignal.fatal('$error\n$stackTrace').toMessage(),
    );
  } finally {
    await eventsSub?.cancel();
    if (worker != null && workerStarted) {
      await worker.shutdown(mode: WorkerShutdownMode.warm);
    }
    await stores?.close();
    commands?.close();
    stemLogger.warning('Worker isolate shutting down');
  }
}

String _formatTimestamp(DateTime? value) {
  if (value == null) return 'none';
  final local = value.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${twoDigits(local.hour)}:${twoDigits(local.minute)}:${twoDigits(local.second)}';
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job});

  final StemFlutterTrackedJob job;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = job.errorMessage ?? job.result;
    final isError = job.errorMessage != null;
    final accent = switch (job.state) {
      TaskState.queued => const Color(0xFF0EA5E9),
      TaskState.running => const Color(0xFFF59E0B),
      TaskState.succeeded => const Color(0xFF22C55E),
      TaskState.failed => const Color(0xFFEF4444),
      TaskState.retried => const Color(0xFFA855F7),
      TaskState.cancelled => const Color(0xFF64748B),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x110F172A),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 4,
            height: 72,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        job.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusChip(state: job.state),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'updated ${_formatTimestamp(job.updatedAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  job.taskId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF475569),
                  ),
                ),
                if (preview != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isError
                          ? theme.colorScheme.error
                          : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkerStateChip extends StatelessWidget {
  const _WorkerStateChip({required this.state});

  final StemFlutterWorkerStatus state;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, label) = switch (state) {
      StemFlutterWorkerStatus.running => (
        const Color(0xFFDCFCE7),
        const Color(0xFF166534),
        'running',
      ),
      StemFlutterWorkerStatus.waiting => (
        const Color(0xFFFEF3C7),
        const Color(0xFF92400E),
        'waiting',
      ),
      StemFlutterWorkerStatus.starting => (
        const Color(0xFFE0F2FE),
        const Color(0xFF075985),
        'starting',
      ),
      StemFlutterWorkerStatus.error => (
        const Color(0xFFFEE2E2),
        const Color(0xFF991B1B),
        'error',
      ),
      StemFlutterWorkerStatus.stopped => (
        const Color(0xFFE5E7EB),
        const Color(0xFF374151),
        'stopped',
      ),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Text(
          label,
          style: TextStyle(color: foreground, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 84),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFCCFBF1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: textTheme.labelSmall?.copyWith(
              color: const Color(0xFF0F766E),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.state});

  final TaskState state;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, label) = switch (state) {
      TaskState.queued => (
        const Color(0xFFE0F2FE),
        const Color(0xFF075985),
        'queued',
      ),
      TaskState.running => (
        const Color(0xFFFEF3C7),
        const Color(0xFF92400E),
        'running',
      ),
      TaskState.succeeded => (
        const Color(0xFFDCFCE7),
        const Color(0xFF166534),
        'succeeded',
      ),
      TaskState.failed => (
        const Color(0xFFFEE2E2),
        const Color(0xFF991B1B),
        'failed',
      ),
      TaskState.retried => (
        const Color(0xFFF3E8FF),
        const Color(0xFF6B21A8),
        'retried',
      ),
      TaskState.cancelled => (
        const Color(0xFFE5E7EB),
        const Color(0xFF374151),
        'cancelled',
      ),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          label,
          style: TextStyle(color: foreground, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
