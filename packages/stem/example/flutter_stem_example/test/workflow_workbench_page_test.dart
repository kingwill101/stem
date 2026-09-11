import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_stem_example/src/demo_workflows.dart';
import 'package:flutter_stem_example/src/workflow_workbench_controller.dart';
import 'package:flutter_stem_example/src/workflow_workbench_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stem/stem.dart';

void main() {
  testWidgets('launch remains available with existing queued runs', (
    tester,
  ) async {
    final workflows = (await tester.runAsync(
      () => StemWorkflowApp.inMemory(
        scripts: createDemoWorkflowScripts(),
        workerConfig: const StemWorkerConfig(queue: 'mobile-demo'),
      ),
    ))!;
    final controller = WorkflowWorkbenchController(workflows);
    var closed = false;
    Future<void> close() async {
      if (closed) return;
      closed = true;
      await tester.runAsync(() async {
        await controller.dispose();
        await workflows.app.worker.shutdown();
        await workflows.close();
      });
    }

    addTearDown(() async {
      await close();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: WorkflowWorkbenchPage(
          controller: controller,
          backgroundMode: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('No runs on this history page'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('No runs on this history page'), findsOneWidget);
    final launch = find.byKey(const Key('launch-workflows'));
    await tester.ensureVisible(launch);
    await tester.tap(launch);
    await tester.pumpAndSettle();
    expect(controller.runs, hasLength(1));
    expect(tester.widget<FilledButton>(launch).onPressed, isNotNull);
    await tester.tap(launch);
    await tester.pumpAndSettle();
    expect(controller.runs, hasLength(2));
    await tester.pumpWidget(const SizedBox());
    // Removing the page does not dispose its app-owned controller.
    await controller.refresh();
    // testWidgets checks pending fake timers before addTearDown runs.
    await close();
  });

  testWidgets('only submission disables launch and failures can be retried', (
    tester,
  ) async {
    final controller = _TestController();
    addTearDown(controller.dispose);
    controller.submission = Completer<List<String>>();
    await _show(tester, controller);
    final launch = find.byKey(const Key('launch-workflows'));
    await tester.ensureVisible(launch);
    await tester.tap(launch);
    await tester.pump();
    expect(tester.widget<FilledButton>(launch).onPressed, isNull);
    controller.submission!.completeError(StateError('injected submission'));
    await tester.pumpAndSettle();
    expect(find.textContaining('injected submission'), findsOneWidget);
    expect(tester.widget<FilledButton>(launch).onPressed, isNotNull);
    controller.submission = null;
    await tester.tap(launch);
    await tester.pumpAndSettle();
    expect(find.textContaining('Submitted 1 workflow'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(controller.events.hasListener, isFalse);
    expect(controller.disposed, isFalse);
  });

  for (final width in [320.0, 360.0]) {
    testWidgets('scrollable at $width with large text', (tester) async {
      tester.view.physicalSize = Size(width, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = _TestController();
      addTearDown(controller.dispose);
      await _show(tester, controller, scale: 2);
      final count = find.byKey(const Key('workflow-count'));
      await tester.ensureVisible(count);
      await tester.pumpAndSettle();
      await tester.tap(count);
      await tester.pumpAndSettle();
      await tester.tap(find.text('5').last);
      await tester.pumpAndSettle();
      final launch = find.byKey(const Key('launch-workflows'));
      await tester.ensureVisible(launch);
      await tester.pumpAndSettle();
      await tester.tap(launch);
      await tester.pumpAndSettle();
      expect(controller.lastCount, 5);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('empty persisted diagnostic maps are not shown as errors', (
    tester,
  ) async {
    final controller = _TestController()
      ..runs = [
        WorkflowRunView(
          runId: 'finished',
          workflow: 'demo.report',
          status: WorkflowStatus.completed,
          cursor: 3,
          createdAt: DateTime.utc(2026),
          params: const {},
          runtime: const {},
          lastError: const {},
          suspensionData: const {},
          result: const {'total': 35},
        ),
      ];
    addTearDown(controller.dispose);
    await _show(tester, controller);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('workflow-run-finished')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Status: completed'), findsOneWidget);
    expect(find.textContaining('Run error:'), findsNothing);
    expect(find.textContaining('Suspension:'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('refresh errors have a retry path', (tester) async {
    final controller = _TestController()..refreshError = StateError('offline');
    addTearDown(controller.dispose);
    await _show(tester, controller);
    expect(find.textContaining('offline'), findsOneWidget);
    controller.refreshError = null;
    await tester.ensureVisible(find.text('Retry refresh'));
    await tester.tap(find.text('Retry refresh'));
    await tester.pumpAndSettle();
    expect(find.textContaining('offline'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('approval targets its waiting run and displays saved progress', (
    tester,
  ) async {
    final controller = _TestController();
    addTearDown(controller.dispose);
    final run = WorkflowRunView(
      runId: 'approval-1',
      workflow: WorkbenchWorkflowKind.approval.descriptor.name,
      status: WorkflowStatus.suspended,
      cursor: 1,
      createdAt: DateTime.utc(2026),
      params: const {},
      runtime: const {},
      suspensionData: {'topic': workflowApprovalTopic('approval-1')},
    );
    controller.runs.add(run);
    controller.details[run.runId] = WorkflowRunDetailView(
      run: run,
      checkpoints: [
        WorkflowCheckpointView(
          runId: run.runId,
          workflow: run.workflow,
          checkpointName: 'prepare',
          baseCheckpointName: 'prepare',
          position: 0,
          value: const {'prepared': true},
        ),
      ],
    );
    await _show(tester, controller);
    final approve = find.byKey(const ValueKey('approve-approval-1'));
    await tester.scrollUntilVisible(
      approve,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Persisted checkpoints: 1'), findsOneWidget);
    expect(find.text('Cursor: 1'), findsOneWidget);
    await tester.tap(approve);
    await tester.pumpAndSettle();
    expect(controller.approved, 'approval-1');
    expect(controller.detailLoads, 0);
    await tester.tap(find.text('Saved checkpoints'));
    await tester.pumpAndSettle();
    expect(controller.detailLoads, 1);
    expect(find.textContaining('"prepared": true'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('history controls explicitly navigate pages and status', (
    tester,
  ) async {
    final controller = _TestController()..hasNextPage = true;
    addTearDown(controller.dispose);
    await _show(tester, controller);
    await tester.scrollUntilVisible(
      find.text('Next page'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next page'));
    await tester.pumpAndSettle();
    expect(controller.historyPage, 1);
    expect(find.text('History page 2'), findsOneWidget);
    await tester.tap(find.text('Previous page'));
    await tester.pumpAndSettle();
    expect(controller.historyPage, 0);
    await tester.ensureVisible(find.text('All statuses'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All statuses'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('suspended').last);
    await tester.pumpAndSettle();
    expect(controller.historyStatus, WorkflowStatus.suspended);
    expect(controller.historyPage, 0);
    expect(find.textContaining('not all active runs'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

Future<void> _show(
  WidgetTester tester,
  WorkflowWorkbenchController controller, {
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: WorkflowWorkbenchPage(controller: controller, backgroundMode: true),
    ),
  );
  await tester.pumpAndSettle();
}

/// Fault injection at the controller boundary without inventing run models.
class _TestController implements WorkflowWorkbenchController {
  final events = StreamController<void>.broadcast();
  Completer<List<String>>? submission;
  Object? refreshError;
  int? lastCount;
  bool disposed = false;
  String? approved;
  @override
  WorkbenchWorkflowKind historyWorkflow = WorkbenchWorkflowKind.report;
  @override
  WorkflowStatus? historyStatus;
  @override
  int historyPage = 0;
  @override
  bool hasNextPage = false;
  int detailLoads = 0;

  @override
  Future<void> selectHistory({
    required WorkbenchWorkflowKind workflow,
    WorkflowStatus? status,
  }) async {
    historyWorkflow = workflow;
    historyStatus = status;
    historyPage = 0;
  }

  @override
  Future<void> nextPage() async => historyPage++;
  @override
  Future<void> previousPage() async => historyPage--;
  @override
  Future<void> loadDetail(String runId) async => detailLoads++;

  @override
  Stream<void> get changes => events.stream;
  @override
  List<WorkflowRunView> runs = [];
  @override
  Map<String, WorkflowRunDetailView> details = {};
  @override
  Object? observationError;
  @override
  DateTime? updatedAt;
  @override
  StemWorkflowApp get workflows =>
      throw UnsupportedError('The view does not access the runtime directly.');
  @override
  Future<void> Function()? get requestWakeup => null;
  @override
  Future<void> refresh() async {
    if (refreshError != null) throw refreshError!;
  }

  @override
  Future<List<String>> launch(
    WorkbenchWorkflowKind kind, {
    int count = 1,
  }) async {
    lastCount = count;
    return submission == null ? ['submitted'] : await submission!.future;
  }

  @override
  Future<void> approve(String runId) async {
    approved = runId;
  }

  @override
  Future<void> cancel(String runId) async {}
  @override
  void setVisible(bool visible) {}
  @override
  Future<void> dispose() async {
    disposed = true;
    await events.close();
  }
}
