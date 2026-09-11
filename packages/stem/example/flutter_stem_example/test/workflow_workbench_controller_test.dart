import 'dart:async';

import 'package:flutter_stem_example/src/demo_workflows.dart';
import 'package:flutter_stem_example/src/workflow_workbench_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stem/stem.dart';

void main() {
  late _ObservedWorkflows workflows;
  late WorkflowWorkbenchController controller;
  setUp(() {
    workflows = _ObservedWorkflows();
    controller = WorkflowWorkbenchController(workflows)..setVisible(false);
  });
  tearDown(() => controller.dispose());

  test('large history uses one bounded query and explicit pages', () async {
    await controller.refresh();
    expect(workflows.requests, [(21, 0)]);
    expect(controller.runs, hasLength(20));
    expect(controller.hasNextPage, isTrue);
    expect(workflows.detailReads, 0);
    await controller.refresh();
    expect(workflows.requests, [(21, 0), (21, 0)]);
    await controller.nextPage();
    expect(workflows.requests.last, (21, 20));
    expect(controller.historyPage, 1);
    expect(controller.runs.first.runId, 'run-20');
    await controller.previousPage();
    expect(workflows.requests.last, (21, 0));
    await controller.selectHistory(
      workflow: WorkbenchWorkflowKind.approval,
      status: WorkflowStatus.suspended,
    );
    expect(controller.historyPage, 0);
    expect(workflows.workflow, WorkbenchWorkflowKind.approval.descriptor.name);
    expect(workflows.status, WorkflowStatus.suspended);
    expect(workflows.detailReads, 0);
  });

  test(
    'unchanged refresh retains lazy details without checkpoint N+1',
    () async {
      await controller.refresh();
      await controller.loadDetail('run-0');
      final detail = controller.details['run-0'];
      expect(detail, isNotNull);
      for (var i = 0; i < 5; i++) {
        await controller.refresh();
        expect(identical(controller.details['run-0'], detail), isTrue);
      }
      expect(workflows.detailReads, 1);
      workflows.revision++;
      await controller.refresh();
      expect(controller.details, isEmpty);
      expect(workflows.detailReads, 1);
      await controller.loadDetail('run-0');
      expect(controller.details['run-0']!.run.cursor, 1);
      expect(workflows.detailReads, 2);
      await controller.loadDetail('run-0');
      expect(
        workflows.detailReads,
        3,
        reason: 'Explicit reload is always fresh',
      );
      await controller.nextPage();
      expect(controller.details, isEmpty);
      await controller.loadDetail('run-0');
      expect(workflows.detailReads, 3, reason: 'Off-page requests are ignored');
    },
  );

  test('last page disables forward navigation', () async {
    workflows.total = 21;
    await controller.refresh();
    await controller.nextPage();
    expect(controller.runs, hasLength(1));
    expect(controller.hasNextPage, isFalse);
    final reads = workflows.requests.length;
    await controller.nextPage();
    expect(workflows.requests, hasLength(reads));
  });

  test('dispose joins in-flight detail and queued refresh', () async {
    await controller.refresh();
    workflows.detailGate = Completer<void>();
    workflows.detailEntered = Completer<void>();
    final loading = controller.loadDetail('run-0');
    await workflows.detailEntered!.future;
    final refreshing = controller.refresh();
    var disposed = false;
    final closing = controller.dispose().then((_) => disposed = true);
    await Future<void>.delayed(Duration.zero);
    expect(disposed, isFalse);
    workflows.detailGate!.complete();
    await loading;
    await refreshing;
    await closing;
    expect(workflows.requests, hasLength(2));
    await expectLater(controller.loadDetail('run-0'), throwsStateError);
  });
}

/// Counts the actual app observation API calls without involving worker timing.
class _ObservedWorkflows implements StemWorkflowApp {
  final requests = <(int, int)>[];
  int detailReads = 0;
  int revision = 0;
  int total = 10000;
  String? workflow;
  WorkflowStatus? status;
  Completer<void>? detailGate;
  Completer<void>? detailEntered;

  WorkflowRunView run(int index) => WorkflowRunView(
    runId: 'run-$index',
    workflow: workflow ?? WorkbenchWorkflowKind.report.descriptor.name,
    status: status ?? WorkflowStatus.running,
    cursor: revision,
    createdAt: DateTime.utc(2026).subtract(Duration(seconds: index)),
    updatedAt: DateTime.utc(2026).add(Duration(seconds: revision)),
    params: const {},
    runtime: const {},
  );

  @override
  Future<List<WorkflowRunView>> listRunViews({
    String? workflow,
    WorkflowStatus? status,
    int limit = 50,
    int offset = 0,
  }) async {
    this.workflow = workflow;
    this.status = status;
    requests.add((limit, offset));
    return [for (var i = offset; i < total && i < offset + limit; i++) run(i)];
  }

  @override
  Future<WorkflowRunDetailView?> viewRunDetail(String runId) async {
    detailReads++;
    detailEntered?.complete();
    await detailGate?.future;
    return WorkflowRunDetailView(
      run: run(int.parse(runId.substring(4))),
      checkpoints: const [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
