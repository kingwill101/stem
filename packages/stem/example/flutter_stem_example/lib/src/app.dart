import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:stem/observability.dart' show stemLogger;
import 'package:stem_flutter_sqlite/stem_flutter_sqlite.dart';

import 'demo_config.dart';
import 'demo_tasks.dart';
import 'photo_batch.dart';
import 'queue_debug_controller.dart';
import 'queue_monitor_page.dart';

Future<StemApp> createDemoApp({
  StemFlutterStorageLayout? layout,
}) => StemFlutterSqlite.createApp(
  module: demoModule,
  layout: layout,
  workerConfig: const StemWorkerConfig(
    concurrency: 1,
    prefetchMultiplier: 1,
    lifecycle: WorkerLifecycleConfig(
      installSignalHandlers: false,
      // Image processing allocates large temporary buffers. Retire the
      // task isolate between photos rather than retain its heap for a batch.
      // This is not a hard memory limit or protection against OS kills.
      maxTasksPerIsolate: 1,
    ),
  ),
);

class StemFlutterExampleApp extends StatefulWidget {
  const StemFlutterExampleApp({
    super.key,
    this.createApp = createDemoApp,
    this.runLocalWorker = true,
    this.startupWakeup,
    this.requestWakeup,
    this.cancelWakeups,
    this.requestNotificationPermission,
    this.onPhotosCommitted,
    this.outputDirectory,
    this.workload,
  });

  final String? outputDirectory;
  final PhotoWorkload? workload;
  final bool runLocalWorker;
  final Future<void> Function()? startupWakeup;
  final Future<void> Function()? requestWakeup;
  final Future<void> Function()? cancelWakeups;
  final Future<bool> Function()? requestNotificationPermission;
  final Future<void> Function(StemApp)? onPhotosCommitted;

  /// Ownership transfers to this widget, including apps injected by tests.
  final Future<StemApp> Function() createApp;

  @override
  State<StemFlutterExampleApp> createState() => _StemFlutterExampleAppState();
}

class _StemFlutterExampleAppState extends State<StemFlutterExampleApp> {
  StemApp? _app;
  PhotoBatchProducer? _producer;
  QueueDebugController? _monitor;
  String? _bootError;
  bool _isBooting = true;
  late final Future<void> _boot;

  @override
  void initState() {
    super.initState();
    _boot = _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      _app = await widget.createApp();
      if (!mounted) return;
      final outputDirectory =
          widget.outputDirectory ??
          '${(await StemFlutterStorageLayout.applicationSupport()).root.path}'
              '${Platform.pathSeparator}photos';
      if (!mounted) return;
      _producer = PhotoBatchProducer(
        _app!,
        outputDirectory: outputDirectory,
        requestWakeup: widget.requestWakeup,
        onCommitted: widget.onPhotosCommitted,
      );
      if (widget.runLocalWorker) await _app!.start();
      if (!mounted) return;
      _monitor = QueueDebugController(_app!, queueName: queueName);
      await _monitor!.start();
    } catch (error, stackTrace) {
      stemLogger.error(
        'Flutter example bootstrap failed: $error',
        stackTrace: stackTrace,
      );
      await _closeResources();
      _bootError = '$error\n$stackTrace';
    }
    if (!mounted) return;
    setState(() => _isBooting = false);
  }

  Future<void> _closeResources() async {
    // Dashboard reads must finish before the app closes its stores.
    final monitor = _monitor;
    final app = _app;
    _monitor = null;
    _app = null;
    try {
      await _producer?.dispose();
      _producer = null;
      await monitor?.dispose();
    } finally {
      await app?.close();
    }
  }

  Future<void> _shutdown() async {
    // Creation/start can still be awaiting plugins when the root is removed.
    await _boot;
    await _closeResources();
  }

  @override
  void dispose() {
    _producer?.stopPublishing();
    unawaited(
      _shutdown().catchError((Object error, StackTrace stackTrace) {
        stemLogger.error(
          'Flutter example shutdown failed: $error',
          stackTrace: stackTrace,
        );
      }),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stem Photo Lab',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          brightness: Brightness.light,
        ),
      ),
      home: QueueMonitorPage(
        app: _app,
        producer: _producer,
        workload: widget.workload,
        monitor: _monitor,
        isBooting: _isBooting,
        bootError: _bootError,
        startupWakeup: widget.startupWakeup,
        requestWakeup: widget.requestWakeup,
        cancelWakeups: widget.cancelWakeups,
        requestNotificationPermission: widget.requestNotificationPermission,
      ),
    );
  }
}
