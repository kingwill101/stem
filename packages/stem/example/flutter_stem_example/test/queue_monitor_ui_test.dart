import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_stem_example/src/demo_tasks.dart';
import 'package:flutter_stem_example/src/photo_batch.dart';
import 'package:flutter_stem_example/src/queue_debug_controller.dart';
import 'package:flutter_stem_example/src/queue_monitor_page.dart';
import 'package:flutter_stem_example/src/widgets/job_card.dart';
import 'package:stem_flutter/stem_flutter.dart';

class RecordingMonitor extends QueueDebugController {
  RecordingMonitor(super.app) : super(queueName: 'mobile-demo');
  final visibility = <bool>[];

  @override
  void setVisible(bool visible) => visibility.add(visible);
}

TaskStatusRecord photo(String id, DateTime createdAt, Object? payload) =>
    TaskStatusRecord(
      status: TaskStatus(
        id: id,
        state: TaskState.succeeded,
        attempt: 1,
        meta: {'batchId': id, 'label': id},
        payload: payload,
      ),
      createdAt: createdAt,
      updatedAt: createdAt,
    );

void main() {
  testWidgets('additional batches and single photos remain available', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = await StemApp.inMemory(module: demoModule);
    final monitor = RecordingMonitor(app);
    final wakeup = Completer<void>();
    final producer = PhotoBatchProducer(
      app,
      outputDirectory: '/unused',
      requestWakeup: () => wakeup.future,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: QueueMonitorPage(
          app: app,
          monitor: monitor,
          producer: producer,
          isBooting: false,
        ),
      ),
    );
    final batch = find.byKey(const ValueKey('push-job'));
    final single = find.byKey(const ValueKey('push-single-photo'));
    await tester.tap(batch);
    await tester.pump();
    expect(tester.widget<FilledButton>(batch).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(single).onPressed, isNull);
    wakeup.complete();
    await tester.pumpAndSettle();
    expect(monitor.pendingCount, 6);
    expect(tester.widget<FilledButton>(batch).onPressed, isNotNull);
    expect(tester.widget<OutlinedButton>(single).onPressed, isNotNull);
    await tester.tap(single);
    await tester.pumpAndSettle();
    expect(monitor.pendingCount, 7);
    expect(find.text('Single photo · 0 / 1 finished'), findsOneWidget);
    expect(find.text('Standard · 0 / 6 finished'), findsOneWidget);
    await tester.tap(batch);
    await tester.pumpAndSettle();
    expect(monitor.pendingCount, 13);
    expect(PhotoBatchSummary.fromJobs(monitor.jobs), hasLength(3));
    expect(find.textContaining('Workers sharing a queue'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await producer.dispose();
    await monitor.dispose();
    await app.shutdown();
  });

  testWidgets('mount, remount and replacement respect current lifecycle', (
    tester,
  ) async {
    final app = await StemApp.inMemory(module: demoModule);
    final first = RecordingMonitor(app);
    final second = RecordingMonitor(app);
    Future<void> mount(RecordingMonitor monitor) => tester.pumpWidget(
      MaterialApp(
        home: QueueMonitorPage(app: app, monitor: monitor, isBooting: false),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await mount(first);
    expect(first.visibility, [true]);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(first.visibility.last, isFalse);
    await mount(first);
    expect(first.visibility.last, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await mount(second);
    expect(first.visibility.last, isFalse);
    expect(second.visibility, [false]);
    await tester.pumpWidget(const SizedBox.shrink());
    await mount(first);
    expect(first.visibility.last, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await first.dispose();
    await second.dispose();
    await app.shutdown();
  });

  testWidgets('permission is single flight, recoverable and independent', (
    tester,
  ) async {
    final app = await StemApp.inMemory(module: demoModule);
    final permission = Completer<bool>();
    var requests = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: QueueMonitorPage(
          app: app,
          monitor: null,
          isBooting: false,
          producer: PhotoBatchProducer(app, outputDirectory: '/unused'),
          requestNotificationPermission: () {
            requests++;
            return requests == 1 ? permission.future : Future.value(true);
          },
        ),
      ),
    );
    final button = find.widgetWithText(
      TextButton,
      'Enable status notifications',
    );
    final action = tester.widget<TextButton>(button).onPressed!;
    action();
    action(); // A second event before the disabled button rebuilds.
    await tester.pump();
    expect(requests, 1);
    expect(tester.widget<TextButton>(button).onPressed, isNull);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('push-job')))
          .onPressed,
      isNotNull,
    );
    permission.completeError(StateError('permission unavailable'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Notification permission failed:'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    tester.widget<TextButton>(button).onPressed!();
    await tester.pumpAndSettle();
    expect(requests, 2);
    expect(find.textContaining('Status notifications enabled'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await app.shutdown();
  });

  testWidgets('batch cards use creation time then id rather than input order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = await StemApp.inMemory(module: demoModule);
    final monitor = RecordingMonitor(app);
    final now = DateTime(2026);
    final records = [
      photo('a', now, null),
      photo('old', now.subtract(const Duration(days: 1)), null),
      photo('z', now, null),
    ];
    for (final jobs in [records, records.reversed.toList()]) {
      monitor.jobs = jobs;
      await tester.pumpWidget(
        MaterialApp(
          home: QueueMonitorPage(app: app, monitor: monitor, isBooting: false),
        ),
      );
      final labels = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .whereType<String>()
          .where((text) => text.endsWith('finished'))
          .toList();
      expect(labels, [
        'z · 1 / 1 finished',
        'a · 1 / 1 finished',
        'old · 1 / 1 finished',
      ]);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await monitor.dispose();
    await app.shutdown();
  });

  testWidgets('photo metadata omits invalid fields independently', (
    tester,
  ) async {
    final cases = <Map<String, Object?>, String?>{
      {'width': 96, 'height': 64, 'elapsedMs': 0}: '96 × 64 · 0 ms',
      {'width': 96, 'height': 64}: '96 × 64',
      {'width': 96, 'elapsedMs': 5}: '5 ms',
      {'width': -1, 'height': 64, 'elapsedMs': double.nan}: null,
      {'width': '96', 'height': 64, 'elapsedMs': -1}: null,
      {'elapsedMs': double.infinity}: null,
      {'thumbnailPath': null}: null,
    };
    for (final entry in cases.entries) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: JobCard(job: photo('test', DateTime(2026), entry.key)),
          ),
        ),
      );
      expect(find.textContaining('null'), findsNothing);
      final details = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .whereType<String>()
          .where((text) => text.contains(' × ') || text.endsWith(' ms'));
      expect(details, entry.value == null ? isEmpty : [entry.value]);
      expect(tester.takeException(), isNull);
    }
  });
}
