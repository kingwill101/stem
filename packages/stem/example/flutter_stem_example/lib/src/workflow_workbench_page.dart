import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:stem/stem.dart';

import 'demo_workflows.dart';
import 'workflow_workbench_controller.dart';

/// A read-through view of durable runs. The app owns the controller and worker.
class WorkflowWorkbenchPage extends StatefulWidget {
  const WorkflowWorkbenchPage({
    super.key,
    required this.controller,
    required this.backgroundMode,
  });

  final WorkflowWorkbenchController controller;
  final bool backgroundMode;

  @override
  State<WorkflowWorkbenchPage> createState() => _WorkflowWorkbenchPageState();
}

class _WorkflowWorkbenchPageState extends State<WorkflowWorkbenchPage> {
  StreamSubscription<void>? _subscription;
  WorkbenchWorkflowKind _kind = WorkbenchWorkflowKind.report;
  int _count = 1;
  bool _submitting = false;
  bool _refreshing = false;
  bool _loaded = false;
  String? _error;
  String? _notice;
  final Set<String> _pendingRuns = {};

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _subscription = widget.controller.changes.listen(
      (_) {
        if (mounted) setState(() {});
      },
      onError: (Object error) {
        if (mounted) setState(() => _error = 'Observation failed: $error');
      },
    );
    unawaited(_refresh());
  }

  @override
  void didUpdateWidget(covariant WorkflowWorkbenchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      unawaited(_subscription?.cancel());
      _loaded = false;
      _refreshing = false;
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
      if (mounted && controller == widget.controller) {
        setState(() => _error = null);
      }
    } catch (error) {
      if (mounted && controller == widget.controller) {
        setState(() => _error = 'Could not refresh runs: $error');
      }
    } finally {
      if (mounted && controller == widget.controller) {
        setState(() {
          _refreshing = false;
          _loaded = true;
        });
      }
    }
  }

  Future<void> _launch() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
      _notice = null;
    });
    try {
      final ids = await widget.controller.launch(_kind, count: _count);
      if (mounted) {
        setState(() => _notice = 'Submitted ${ids.length} workflow run(s).');
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error =
              'Launch or wakeup failed: $error. Some runs may already be saved. '
              'Refresh before launching again; Retry wakeup is on the Tasks tab.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _act(WorkflowRunView run, {required bool approve}) async {
    if (_pendingRuns.contains(run.runId)) return;
    if (!approve) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cancel this workflow run?'),
          content: Text(
            'Run ${run.runId} will be cancelled. Its saved checkpoints and '
            'other runs are not deleted.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep run'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cancel run'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _pendingRuns.add(run.runId);
      _error = null;
    });
    try {
      if (approve) {
        await widget.controller.approve(run.runId);
      } else {
        await widget.controller.cancel(run.runId);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not update run ${run.runId}: $error');
      }
    } finally {
      if (mounted) setState(() => _pendingRuns.remove(run.runId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final runs = widget.controller.runs.toList()
      ..sort((a, b) {
        final date = b.createdAt.compareTo(a.createdAt);
        return date != 0 ? date : a.runId.compareTo(b.runId);
      });
    final error = _error ?? widget.controller.observationError?.toString();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workflows'),
        actions: [
          IconButton(
            tooltip: 'Refresh workflows',
            onPressed: _refreshing ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: runs.length + 1,
              itemBuilder: (context, index) {
                if (index != 0) return _runCard(runs[index - 1]);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Durable workflow workbench',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Workflow runs use the configured workers and queues. Launch more '
                      'while earlier runs are queued, running, or suspended.',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.backgroundMode
                          ? 'Android schedules each callback; the callback hosts '
                                'ordinary Stem workers. See Workers for subscriptions.'
                          : 'Foreground mode: the app starts the configured Stem '
                                'workers. See Workers for their queue subscriptions.',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Durable sleeps resume only after a scheduler opportunity; '
                      'the requested delay is not an exact execution time.',
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<WorkbenchWorkflowKind>(
                      key: const Key('workflow-scenario'),
                      initialValue: _kind,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Scenario'),
                      items: [
                        for (final descriptor in demoWorkflowDescriptors)
                          DropdownMenuItem(
                            value: descriptor.kind,
                            child: Text(
                              descriptor.title,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _kind = value);
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(_kind.descriptor.description),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      key: const Key('workflow-count'),
                      initialValue: _count,
                      decoration: const InputDecoration(
                        labelText: 'Number of runs',
                      ),
                      items: [
                        for (var count = 1; count <= 5; count++)
                          DropdownMenuItem(value: count, child: Text('$count')),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _count = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      key: const Key('launch-workflows'),
                      onPressed: _submitting ? null : _launch,
                      icon: const Icon(Icons.play_arrow),
                      label: Text(
                        _submitting ? 'Submitting…' : 'Launch workflows',
                      ),
                    ),
                    if (_notice != null) Text(_notice!),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        error,
                        key: const Key('workflow-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      TextButton(
                        onPressed: _refreshing ? null : _refresh,
                        child: const Text('Retry refresh'),
                      ),
                    ],
                    if (!_loaded && _refreshing)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Loading workflow runs…'),
                      ),
                    const SizedBox(height: 24),
                    Text(
                      'Runs (${runs.length})',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (_loaded && runs.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'No workflow runs yet. Choose a scenario and launch '
                          'one or more runs to inspect saved checkpoints.',
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _runCard(WorkflowRunView run) {
    final detail = widget.controller.details[run.runId];
    final terminal =
        run.status == WorkflowStatus.completed ||
        run.status == WorkflowStatus.failed ||
        run.status == WorkflowStatus.cancelled;
    final waitingApproval =
        run.status == WorkflowStatus.suspended &&
        run.workflow == WorkbenchWorkflowKind.approval.descriptor.name &&
        run.suspensionData?['topic'] == workflowApprovalTopic(run.runId);
    final pending = _pendingRuns.contains(run.runId);
    final checkpoints = detail?.checkpoints.toList()
      ?..sort((a, b) => a.position.compareTo(b.position));
    return Card(
      key: ValueKey('workflow-run-${run.runId}'),
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(run.workflow, style: Theme.of(context).textTheme.titleMedium),
            SelectableText('Run ${run.runId}'),
            Text('Status: ${run.status.name}'),
            Text('Cursor: ${run.cursor}'),
            Text(
              checkpoints == null
                  ? 'Checkpoints unavailable. Refresh to retry.'
                  : 'Persisted checkpoints: ${checkpoints.length}',
            ),
            if (run.suspensionData?.isNotEmpty ?? false)
              Text('Suspension: ${_payload(run.suspensionData)}'),
            if (waitingApproval)
              const Text('Waiting for approval for this run.'),
            if (run.lastError?.isNotEmpty ?? false)
              Text('Run error: ${_payload(run.lastError)}'),
            if (run.result != null)
              SelectableText('Result: ${_payload(run.result)}'),
            if (checkpoints != null && checkpoints.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Saved checkpoints'),
                children: [
                  for (final checkpoint in checkpoints)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(
                          '${checkpoint.position}: ${checkpoint.checkpointName}\n'
                          '${_payload(checkpoint.value)}',
                        ),
                      ),
                    ),
                ],
              ),
            Wrap(
              spacing: 8,
              children: [
                if (waitingApproval)
                  FilledButton(
                    key: ValueKey('approve-${run.runId}'),
                    onPressed: pending ? null : () => _act(run, approve: true),
                    child: const Text('Approve'),
                  ),
                if (!terminal)
                  TextButton(
                    key: ValueKey('cancel-${run.runId}'),
                    onPressed: pending ? null : () => _act(run, approve: false),
                    child: const Text('Cancel'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _payload(Object? value) {
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return value.toString();
    }
  }
}
