import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_stem_example/src/worker_workbench_controller.dart';
import 'package:flutter_stem_example/src/worker_workbench_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stem/stem.dart';

void main() {
  testWidgets(
    'queue/count controls allow more work without assigning a worker',
    (tester) async {
      final controller = _TestController();
      addTearDown(controller.dispose);
      await _show(tester, controller);
      final queue = find.byKey(const Key('probe-queue'));
      await tester.scrollUntilVisible(queue, 250);
      await tester.tap(queue);
      await tester.pumpAndSettle();
      await tester.tap(find.text('mobile-routing').last);
      await tester.pumpAndSettle();
      final count = find.byKey(const Key('probe-count'));
      await tester.ensureVisible(count);
      await tester.tap(count);
      await tester.pumpAndSettle();
      await tester.tap(find.text('2').last);
      await tester.pumpAndSettle();
      final launch = find.widgetWithText(FilledButton, 'Launch probes');
      await tester.ensureVisible(launch);
      await tester.tap(launch);
      await tester.pumpAndSettle();
      expect(controller.lastQueue, 'mobile-routing');
      expect(controller.lastCount, 2);
      expect(tester.widget<FilledButton>(launch).onPressed, isNotNull);
      await tester.tap(launch);
      await tester.pumpAndSettle();
      expect(controller.launches, 2);
      await tester.scrollUntilVisible(
        find.text('Persisted worker: not yet recorded'),
        300,
      );
      expect(find.text('Persisted worker: not yet recorded'), findsOneWidget);
      expect(find.text('Persisted worker: general-a'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(controller.events.hasListener, isFalse);
      expect(controller.disposed, isFalse);
    },
  );

  testWidgets('submission busy and error states permit retry', (tester) async {
    final controller = _TestController()
      ..submission = Completer<List<String>>();
    addTearDown(controller.dispose);
    await _show(tester, controller);
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Launch probes'),
      250,
    );
    await tester.tap(find.text('Launch probes'));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    controller.submission!.completeError(StateError('injected wakeup failure'));
    await tester.pumpAndSettle();
    expect(find.textContaining('injected wakeup failure'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    '320px large text shows unknown headless health and real metadata',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = _TestController();
      controller.records = [_record(worker: 'general-b', succeeded: true)];
      addTearDown(controller.dispose);
      await _show(tester, controller, scale: 2);
      await tester.scrollUntilVisible(
        find.textContaining('Headless worker health: unknown'),
        250,
      );
      expect(
        find.textContaining('Headless worker health: unknown'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('Local app snapshot: started'),
        250,
      );
      expect(find.text('Local app snapshot: started'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Observed completed probes: 1'),
        250,
      );
      expect(find.text('Observed completed probes: 1'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('probe-queue')),
        250,
      );
      await tester.tap(find.byKey(const Key('probe-queue')));
      await tester.pumpAndSettle();
      expect(find.text('mobile-routing'), findsWidgets);
      await tester.tap(find.text('mobile-routing').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Persisted worker: general-b'),
        250,
      );
      expect(find.text('Persisted worker: general-b'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('"checksum":"actual-result"'),
        250,
      );
      expect(find.textContaining('"checksum":"actual-result"'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

Future<void> _show(
  WidgetTester tester,
  WorkerWorkbenchController controller, {
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
      home: Scaffold(
        body: WorkerWorkbenchPage(controller: controller, backgroundMode: true),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

TaskStatusRecord _record({String? worker, bool succeeded = false}) {
  final now = DateTime.utc(2026);
  return TaskStatusRecord(
    status: TaskStatus(
      id: 'probe-1',
      attempt: 0,
      state: succeeded ? TaskState.succeeded : TaskState.queued,
      meta: {
        'probeBatchId': 'batch-1',
        'queue': 'mobile-routing',
        'worker': ?worker,
      },
      payload: succeeded ? {'checksum': 'actual-result'} : null,
    ),
    createdAt: now,
    updatedAt: now,
  );
}

class _TestController implements WorkerWorkbenchController {
  final events = StreamController<void>.broadcast();
  Completer<List<String>>? submission;
  String? lastQueue;
  int? lastCount;
  int launches = 0;
  bool disposed = false;

  @override
  Stream<void> get changes => events.stream;
  @override
  List<TaskStatusRecord> records = [_record()];
  @override
  Object? observationError;
  @override
  DateTime? updatedAt;
  @override
  Map<String, bool> get localStarted => {'general-a': true};
  @override
  List<StemApp> get localApps => const [];
  @override
  StemApp get app => throw UnsupportedError('View does not access runtime.');
  @override
  Future<void> Function()? get requestWakeup => null;
  @override
  Future<void> refresh() async {}
  @override
  void setVisible(bool visible) {}
  @override
  Future<List<String>> enqueue(String queue, {int count = 6}) async {
    lastQueue = queue;
    lastCount = count;
    launches++;
    return submission == null ? ['probe-1'] : await submission!.future;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await events.close();
  }
}
