import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:stem/stem.dart';

import 'demo_workers.dart';
import 'worker_workbench_controller.dart';

/// Displays durable observations. The app owns controller and worker lifetimes.
class WorkerWorkbenchPage extends StatefulWidget {
  const WorkerWorkbenchPage({
    super.key,
    required this.controller,
    required this.backgroundMode,
  });

  final WorkerWorkbenchController controller;
  final bool backgroundMode;

  @override
  State<WorkerWorkbenchPage> createState() => _WorkerWorkbenchPageState();
}

class _WorkerWorkbenchPageState extends State<WorkerWorkbenchPage> {
  StreamSubscription<void>? _subscription;
  late String _queue = demoWorkerSpecs.first.queues.first;
  int _count = 6;
  bool _submitting = false;
  bool _refreshing = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _subscription = widget.controller.changes.listen((_) {
      if (mounted) setState(() {});
    });
    unawaited(_refresh());
  }

  @override
  void didUpdateWidget(covariant WorkerWorkbenchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      unawaited(_subscription?.cancel());
      _refreshing = false;
      _submitting = false;
      _error = null;
      _notice = null;
      _listen();
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    final controller = widget.controller;
    setState(() => _refreshing = true);
    try {
      await controller.refresh();
    } catch (error) {
      if (mounted && controller == widget.controller) {
        setState(() => _error = 'Refresh failed: $error');
      }
    } finally {
      if (mounted && controller == widget.controller) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _launch() async {
    if (_submitting) return;
    final controller = widget.controller;
    setState(() {
      _submitting = true;
      _error = null;
      _notice = null;
    });
    try {
      final ids = await controller.enqueue(_queue, count: _count);
      if (mounted && controller == widget.controller) {
        setState(() => _notice = 'Published ${ids.length} routing probes.');
      }
    } catch (error) {
      if (mounted && controller == widget.controller) {
        setState(() {
          _error =
              'Publish or wakeup failed: $error. Some probes may already '
              'be saved. Refresh before retrying; Retry wakeup is on Tasks.';
        });
      }
    } finally {
      if (mounted && controller == widget.controller) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final queues = demoWorkerSpecs.expand((spec) => spec.queues).toSet();
    final snapshots = controller.localStarted;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Workers', style: Theme.of(context).textTheme.headlineSmall),
        Text(
          '${demoWorkerSpecs.length} configured workers • '
          '1 isolate slot per worker',
        ),
        const SizedBox(height: 8),
        const Text(
          'Named workers use standard queue routing. Workers subscribed to the '
          'same queue are competing consumers: distribution is not strictly fair. '
          'Configured workers and isolate slots do not guarantee separate native '
          'engines or simultaneous execution.',
        ),
        if (widget.backgroundMode)
          const Text(
            'Headless worker health: unknown. Local app snapshots below describe '
            'this process only, not the background scheduler.',
          ),
        for (final spec in demoWorkerSpecs)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(spec.id, style: Theme.of(context).textTheme.titleMedium),
                  Text('Configured queues: ${spec.queues.join(', ')}'),
                  Text(
                    'Isolate slots: 1 • Workflows: '
                    '${spec.handlesWorkflows ? 'yes' : 'no'}',
                  ),
                  Text(
                    '${widget.backgroundMode ? 'Local app snapshot' : 'Foreground local app'}: '
                    '${snapshots[spec.id] == null
                        ? 'unknown'
                        : snapshots[spec.id]!
                        ? 'started'
                        : 'not started'}',
                  ),
                  Text(
                    'Observed completed probes: ${controller.records.where((r) => r.status.state == TaskState.succeeded && r.status.meta['worker'] == spec.id).length}',
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: const Key('probe-queue'),
          initialValue: _queue,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Target queue'),
          items: [
            for (final queue in queues)
              DropdownMenuItem(value: queue, child: Text(queue)),
          ],
          onChanged: _submitting
              ? null
              : (value) => setState(() => _queue = value!),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          key: const Key('probe-count'),
          initialValue: _count,
          decoration: const InputDecoration(labelText: 'Probe count'),
          items: [
            for (var count = 1; count <= 6; count++)
              DropdownMenuItem(value: count, child: Text('$count')),
          ],
          onChanged: _submitting
              ? null
              : (value) => setState(() => _count = value!),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: _submitting ? null : _launch,
              child: Text(_submitting ? 'Publishing…' : 'Launch probes'),
            ),
            OutlinedButton(
              onPressed: _refreshing ? null : _refresh,
              child: Text(_refreshing ? 'Refreshing…' : 'Refresh'),
            ),
          ],
        ),
        const Text(
          'You can launch another batch while earlier work is queued.',
        ),
        if (_notice != null) Text(_notice!),
        if (_error != null) Text(_error!),
        if (controller.observationError != null)
          Text('Observation failed: ${controller.observationError}'),
        if (controller.updatedAt != null)
          Text('Last observed: ${controller.updatedAt!.toLocal()}'),
        const SizedBox(height: 16),
        Text('Persisted probes', style: Theme.of(context).textTheme.titleLarge),
        if (controller.records.isEmpty)
          const Text('No routing probes observed yet.'),
        for (final record in controller.records) _probe(record),
      ],
    );
  }

  Widget _probe(TaskStatusRecord record) {
    final status = record.status;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Probe ${status.id}'),
            Text('Batch: ${status.meta['probeBatchId']}'),
            Text('Index: ${status.meta['index'] ?? 'unknown'}'),
            Text('State: ${status.state.name} • Attempt: ${status.attempt}'),
            Text('Persisted queue: ${status.meta['queue'] ?? 'unknown'}'),
            Text(
              'Persisted worker: ${status.meta['worker'] ?? 'not yet recorded'}',
            ),
            Text(
              'Result: ${status.payload == null ? 'not yet recorded' : jsonEncode(status.payload)}',
            ),
            if (status.error != null) Text('Error: ${status.error}'),
            Text('Updated: ${record.updatedAt.toLocal()}'),
          ],
        ),
      ),
    );
  }
}
