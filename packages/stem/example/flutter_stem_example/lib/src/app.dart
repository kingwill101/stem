import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:stem/observability.dart' show stemLogger;
import 'package:stem_flutter_sqlite/stem_flutter_sqlite.dart';

import 'demo_config.dart';
import 'demo_runtime.dart';
import 'demo_workers.dart';
import 'photo_batch.dart';
import 'queue_debug_controller.dart';
import 'queue_monitor_page.dart';
import 'workflow_workbench_controller.dart';
import 'workflow_workbench_page.dart';
import 'worker_workbench_controller.dart';
import 'worker_workbench_page.dart';

export 'demo_runtime.dart' show closeDemoRuntime, createDemoApp;

class StemFlutterExampleApp extends StatefulWidget {
  const StemFlutterExampleApp({
    super.key,
    this.createApp = createDemoApp,
    this.attachWorkflows,
    this.createAdditionalWorkers,
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

  /// Optional workflow layer, attached before worker startup. It borrows the
  /// task app; the root owns both lifecycles. Tests can inject an in-memory layer.
  final Future<StemWorkflowApp> Function(StemApp)? attachWorkflows;

  /// Normal additional Stem runtimes, started only in foreground mode. In
  /// Android mode the headless callback creates the configured workers instead.
  final Future<List<DemoWorkerRuntime>> Function()? createAdditionalWorkers;

  /// Ownership transfers to this widget, including apps injected by tests.
  final Future<StemApp> Function() createApp;

  @override
  State<StemFlutterExampleApp> createState() => _StemFlutterExampleAppState();
}

class _StemFlutterExampleAppState extends State<StemFlutterExampleApp>
    with WidgetsBindingObserver {
  StemApp? _app;
  StemWorkflowApp? _workflows;
  WorkflowWorkbenchController? _workflowMonitor;
  WorkerWorkbenchController? _workerMonitor;
  List<DemoWorkerRuntime> _additionalWorkers = [];
  PhotoBatchProducer? _producer;
  QueueDebugController? _monitor;
  String? _bootError;
  bool _isBooting = true;
  int _section = 0;
  Future<void>? _startupReconciliation;
  late final Future<void> _boot;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot = _bootstrap();
  }

  int get _workflowIndex => widget.attachWorkflows == null ? -1 : 1;
  bool get _hasWorkbench =>
      widget.attachWorkflows != null || widget.createAdditionalWorkers != null;
  int get _workerIndex => widget.createAdditionalWorkers == null
      ? -1
      : widget.attachWorkflows == null
      ? 1
      : 2;

  bool _pageVisible(int index) {
    final state = WidgetsBinding.instance.lifecycleState;
    return index >= 0 &&
        _section == index &&
        (state == null || state == AppLifecycleState.resumed);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _workflowMonitor?.setVisible(
      _section == _workflowIndex && state == AppLifecycleState.resumed,
    );
    _workerMonitor?.setVisible(
      _section == _workerIndex && state == AppLifecycleState.resumed,
    );
  }

  Future<void> _bootstrap() async {
    try {
      _app = await widget.createApp();
      if (!mounted) return;
      if (widget.attachWorkflows != null) {
        _workflows = await widget.attachWorkflows!(_app!);
        if (!mounted) return;
        _workflowMonitor = WorkflowWorkbenchController(
          _workflows!,
          requestWakeup: widget.requestWakeup,
        );
        _workflowMonitor!.setVisible(_pageVisible(_workflowIndex));
        await _workflowMonitor!.refresh();
        if (!mounted) return;
      }
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
      if (widget.runLocalWorker) {
        if (widget.createAdditionalWorkers != null) {
          _additionalWorkers = await widget.createAdditionalWorkers!();
          if (!mounted) return;
        }
        await Future.wait([
          () async {
            await _workflows?.startRuntime();
            await _app!.start();
          }(),
          for (final worker in _additionalWorkers) worker.start(),
        ]);
      }
      if (!mounted) return;
      if (widget.createAdditionalWorkers != null) {
        _workerMonitor = WorkerWorkbenchController(
          _app!,
          localApps: widget.runLocalWorker
              ? [_app!, ..._additionalWorkers.map((worker) => worker.app)]
              : const [],
          requestWakeup: widget.requestWakeup,
        );
        _workerMonitor!.setVisible(_pageVisible(_workerIndex));
        await _workerMonitor!.refresh();
        if (!mounted) return;
      }
      _monitor = QueueDebugController(_app!, queueName: queueName);
      await _monitor!.start();
      _monitor!.setPageVisible(_section == 0);
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
    final workflows = _workflows;
    final workflowMonitor = _workflowMonitor;
    final workerMonitor = _workerMonitor;
    final additionalWorkers = _additionalWorkers;
    final producer = _producer;
    _monitor = null;
    _app = null;
    _workflows = null;
    _workflowMonitor = null;
    _workerMonitor = null;
    _additionalWorkers = [];
    _producer = null;
    try {
      // These owners can stop independently. Join all of them, including error
      // paths, before releasing any store their pending work might still use.
      await Future.wait([
        if (producer != null) producer.dispose(),
        if (workflowMonitor != null) workflowMonitor.dispose(),
        if (workerMonitor != null) workerMonitor.dispose(),
        if (monitor != null) monitor.dispose(),
      ]);
    } finally {
      await Future.wait([
        if (app != null) closeDemoRuntime(app, workflows: workflows),
        for (final worker in additionalWorkers) worker.close(),
      ]);
    }
  }

  Future<void> _shutdown() async {
    // Creation/start can still be awaiting plugins when the root is removed.
    await _boot;
    await _closeResources();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  Widget _buildTasks() => QueueMonitorPage(
    app: _app,
    producer: _producer,
    workload: widget.workload,
    monitor: _monitor,
    isBooting: _isBooting,
    bootError: _bootError,
    startupWakeup: widget.startupWakeup == null
        ? null
        : () => _startupReconciliation ??= Future<void>.sync(
            widget.startupWakeup!,
          ),
    requestWakeup: widget.requestWakeup,
    cancelWakeups: widget.cancelWakeups,
    requestNotificationPermission: widget.requestNotificationPermission,
  );

  Widget _buildStartupState(String component) => Center(
    child: _bootError == null
        ? const CircularProgressIndicator()
        : Text('$component startup failed: $_bootError'),
  );

  Widget _buildSelectedPage() {
    if (_section == 0) return _buildTasks();
    if (_section == _workerIndex) {
      final monitor = _workerMonitor;
      if (monitor == null) return _buildStartupState('Worker');
      return SafeArea(
        child: WorkerWorkbenchPage(
          controller: monitor,
          backgroundMode: !widget.runLocalWorker,
        ),
      );
    }
    final monitor = _workflowMonitor;
    if (monitor == null) return _buildStartupState('Workflow');
    return WorkflowWorkbenchPage(
      controller: monitor,
      backgroundMode: !widget.runLocalWorker,
    );
  }

  void _selectSection(int index) {
    setState(() => _section = index);
    _monitor?.setPageVisible(index == 0);
    _workflowMonitor?.setVisible(_pageVisible(_workflowIndex));
    _workerMonitor?.setVisible(_pageVisible(_workerIndex));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: _hasWorkbench ? 'Stem Workbench' : 'Stem Photo Lab',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          brightness: Brightness.light,
        ),
      ),
      home: _hasWorkbench
          ? Scaffold(
              body: _buildSelectedPage(),
              bottomNavigationBar: NavigationBar(
                selectedIndex: _section,
                onDestinationSelected: _selectSection,
                destinations: [
                  const NavigationDestination(
                    icon: Icon(Icons.photo_library_outlined),
                    label: 'Tasks',
                  ),
                  if (widget.attachWorkflows != null)
                    const NavigationDestination(
                      icon: Icon(Icons.account_tree_outlined),
                      label: 'Workflows',
                    ),
                  if (widget.createAdditionalWorkers != null)
                    const NavigationDestination(
                      icon: Icon(Icons.dns_outlined),
                      label: 'Workers',
                    ),
                ],
              ),
            )
          : _buildTasks(),
    );
  }
}
