import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stem/stem.dart';
import 'package:stem_flutter/stem_flutter.dart';
import 'package:stem_flutter_sqlite/stem_flutter_sqlite.dart';

import 'demo_config.dart';
import 'demo_tasks.dart';
import 'utils/time_format.dart';
import 'widgets/job_card.dart';
import 'widgets/metric_tile.dart';
import 'widgets/worker_state_chip.dart';
import 'worker/worker_isolate.dart';

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
        tasks: createTaskHandlers(),
        brokerVisibilityTimeout: brokerVisibilityTimeout,
        brokerPollInterval: brokerPollInterval,
        producerSweeperInterval: producerMaintenanceInterval,
        backendCleanupInterval: monitorCleanupInterval,
      );
      stemLogger.info('Producer runtime ready');

      final rootToken = RootIsolateToken.instance;
      if (rootToken == null) {
        throw StateError('RootIsolateToken.instance was null.');
      }

      final workerHost = await StemFlutterSqliteWorkerLauncher.spawn(
        entrypoint: workerIsolateMain,
        layout: layout,
        rootIsolateToken: rootToken,
        brokerPollInterval: brokerPollInterval,
        brokerSweeperInterval: brokerSweepInterval,
        brokerVisibilityTimeout: brokerVisibilityTimeout,
      );
      stemLogger.info('Worker isolate spawned');

      final monitor = StemFlutterQueueMonitor(
        backend: runtime.backend,
        broker: runtime.broker,
        queueName: queueName,
        workerId: workerId,
        pollInterval: monitorPollInterval,
        heartbeatInterval: workerHeartbeatInterval,
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
      taskName,
      args: <String, Object?>{
        'label': label,
        'delayMs': 1200 + (nextJobNumber % 3) * 600,
      },
      meta: <String, Object?>{'label': label},
      options: const TaskOptions(queue: queueName),
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
                        WorkerStateChip(state: _snapshot.workerStatus),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        MetricTile(
                          label: 'pending',
                          value: '${_snapshot.pendingCount ?? 0}',
                        ),
                        MetricTile(
                          label: 'inflight',
                          value: '${_snapshot.inflightCount ?? 0}',
                        ),
                        MetricTile(
                          label: 'tracked',
                          value: '${_snapshot.jobs.length}',
                        ),
                        MetricTile(
                          label: 'heartbeat',
                          value: formatTimestamp(_snapshot.lastHeartbeatAt),
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
                      return JobCard(job: job);
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
