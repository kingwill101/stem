import 'dart:async';

import 'package:flutter/material.dart';
import 'package:stem/stem.dart';

import 'photo_batch.dart';
import 'queue_debug_controller.dart';
import 'widgets/job_card.dart';
import 'widgets/metric_tile.dart';

class QueueMonitorPage extends StatefulWidget {
  const QueueMonitorPage({
    super.key,
    required this.app,
    required this.monitor,
    required this.isBooting,
    this.producer,
    this.workload,
    this.bootError,
    this.startupWakeup,
    this.requestWakeup,
    this.cancelWakeups,
    this.requestNotificationPermission,
  });
  final StemApp? app;
  final QueueDebugController? monitor;
  final PhotoBatchProducer? producer;
  final PhotoWorkload? workload;
  final bool isBooting;
  final String? bootError;
  final Future<void> Function()? startupWakeup;
  final Future<void> Function()? requestWakeup;
  final Future<void> Function()? cancelWakeups;
  final Future<bool> Function()? requestNotificationPermission;

  @override
  State<QueueMonitorPage> createState() => _QueueMonitorPageState();
}

class _QueueMonitorPageState extends State<QueueMonitorPage> {
  StreamSubscription<void>? _monitorSub;
  PhotoWorkload _selection = PhotoWorkload.standard;
  bool _publishing = false;
  bool _waking = false;
  String? _actionMessage;

  @override
  void initState() {
    super.initState();
    _subscribe();
    if (widget.startupWakeup != null) {
      unawaited(_requestWakeup(startup: true));
    }
  }

  @override
  void didUpdateWidget(covariant QueueMonitorPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.monitor != widget.monitor) {
      unawaited(_monitorSub?.cancel());
      _subscribe();
    }
  }

  void _subscribe() {
    _monitorSub = widget.monitor?.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    widget.producer?.stopPublishing();
    widget.monitor?.setVisible(false);
    unawaited(_monitorSub?.cancel());
    super.dispose();
  }

  Future<void> _requestWakeup({bool startup = false}) async {
    if (_waking) return;
    setState(() => _waking = true);
    try {
      await (startup ? widget.startupWakeup : widget.requestWakeup)?.call();
      if (mounted) {
        setState(
          () => _actionMessage = startup
              ? 'Wakeups reconciled; an explicit pause is retained.'
              : 'Wakeup requested. Android decides when work runs.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _actionMessage =
              'Wakeup failed: $error. Retry wakeup does not publish more photos.',
        );
      }
    } finally {
      if (mounted) setState(() => _waking = false);
    }
  }

  Future<void> _cancelWakeups() async {
    setState(() => _waking = true);
    try {
      await widget.cancelWakeups?.call();
      if (mounted) {
        setState(
          () => _actionMessage =
              'Native wakeups cancelled; queued photos retained. '
              'An active callback may finish. Retry wakeup enables scheduling.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _actionMessage = 'Cancel failed: $error');
    } finally {
      if (mounted) setState(() => _waking = false);
    }
  }

  Future<void> _enqueueBatch() async {
    final producer = widget.producer;
    if (producer == null || _publishing) return;
    setState(() => _publishing = true);
    try {
      final message = await producer.publish(widget.workload ?? _selection);
      if (!mounted) return;
      setState(() => _actionMessage = message);
      await widget.monitor?.refresh();
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _enableNotifications() async {
    final granted = await widget.requestNotificationPermission?.call() ?? false;
    if (!mounted) return;
    setState(
      () => _actionMessage = granted
          ? 'Status notifications enabled for future updates.'
          : 'Notifications unavailable or denied. Photo work still runs.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monitor = widget.monitor;
    final jobs = monitor?.jobs ?? const <TaskStatusRecord>[];
    final photos = jobs
        .where((job) => job.status.meta['batchId'] is String)
        .toList(growable: false);
    final batches = PhotoBatchSummary.fromJobs(photos);
    final workload = widget.workload ?? _selection;
    final busy = _publishing || (monitor?.hasUnfinishedWork ?? false);
    final enabled =
        widget.producer != null &&
        !widget.isBooting &&
        !busy &&
        !_waking &&
        monitor?.observationError == null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Photo Lab'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: monitor?.refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your offline photo workbench',
                          style: theme.textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Generate landscapes, encode JPEGs, apply a '
                          'color grade, resize previews and verify files with '
                          'SHA-256. Real CPU work in background isolates. '
                          'No personal photos, permissions or network needed.',
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.requestWakeup != null
                              ? 'Android Workmanager · producer / observer only'
                              : monitor?.isRunning == true
                              ? 'Local worker · isolated photo processing'
                              : 'Worker is not started',
                          style: theme.textTheme.labelLarge,
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final preset
                                in widget.workload == null
                                    ? PhotoWorkload.presets
                                    : [widget.workload!])
                              ChoiceChip(
                                label: Text(
                                  '${preset.label} · ${preset.count}',
                                ),
                                selected: preset == workload,
                                onSelected: busy
                                    ? null
                                    : (_) {
                                        setState(() => _selection = preset);
                                      },
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${workload.count} photos · ${workload.width} × '
                          '${workload.height} pixels each',
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          key: const ValueKey('push-job'),
                          onPressed: enabled ? _enqueueBatch : null,
                          icon: const Icon(Icons.auto_fix_high),
                          label: Text(
                            _publishing
                                ? 'Committing photos…'
                                : 'Prepare ${workload.count} photos',
                          ),
                        ),
                        if (busy)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'Finish the current work before '
                              'starting another batch.',
                            ),
                          ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            MetricTile(
                              label: 'queued',
                              value: '${monitor?.pendingCount ?? 0}',
                            ),
                            MetricTile(
                              label: 'in flight',
                              value: '${monitor?.inflightCount ?? 0}',
                            ),
                            MetricTile(
                              label: 'photos tracked',
                              value: '${photos.length}',
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Progress counts finished photos, not '
                          'estimated time. Counts survive reopening the app.',
                        ),
                        if (photos.length < jobs.length)
                          const Text(
                            'Earlier demo results are retained in storage; '
                            'this gallery shows photo batches only.',
                          ),
                        if (_actionMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              _actionMessage!,
                              key: const ValueKey('action-message'),
                            ),
                          ),
                        if (widget.requestWakeup != null)
                          TextButton.icon(
                            onPressed: _waking || _publishing
                                ? null
                                : _requestWakeup,
                            icon: const Icon(Icons.schedule),
                            label: const Text('Retry wakeup'),
                          ),
                        if (widget.cancelWakeups != null)
                          TextButton(
                            onPressed: _waking || _publishing
                                ? null
                                : _cancelWakeups,
                            child: const Text('Cancel native wakeups'),
                          ),
                        if (widget.requestNotificationPermission != null)
                          TextButton.icon(
                            onPressed: _enableNotifications,
                            icon: const Icon(Icons.notifications_outlined),
                            label: const Text('Enable status notifications'),
                          ),
                        if (monitor?.observationError case final error?)
                          Text(
                            'Could not refresh: $error',
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        if (widget.bootError case final error?)
                          SelectableText(error),
                        if (widget.isBooting)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(),
                          ),
                      ],
                    ),
                  ),
                ),
                SliverList.builder(
                  itemCount: batches.length,
                  itemBuilder: (context, index) {
                    final batch = batches[index];
                    return Card(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${batch.label} · ${batch.completed} / '
                              '${batch.planned} finished',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(value: batch.fraction),
                            const SizedBox(height: 8),
                            Text(
                              '${batch.succeeded} succeeded · '
                              '${batch.failed} failed / cancelled · '
                              '${batch.running} running · '
                              '${batch.queued} queued',
                            ),
                            if (batch.jobs.length < batch.planned)
                              Text(
                                '${batch.jobs.length} of ${batch.planned} '
                                'planned photos recorded. Publication may '
                                'be incomplete.',
                              ),
                            const SizedBox(height: 4),
                            Text(
                              '${(batch.metric('elapsedMs') / 1000).toStringAsFixed(1)} s '
                              'total processing · '
                              '${formatPhotoBytes(batch.metric('sourceBytes'))} source → '
                              '${formatPhotoBytes(batch.metric('outputBytes'))} output',
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      photos.isEmpty
                          ? 'No photos yet. Choose a batch '
                                'to build your local gallery.'
                          : 'Photo artifacts',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverList.builder(
                    itemCount: photos.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: JobCard(job: photos[index]),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
