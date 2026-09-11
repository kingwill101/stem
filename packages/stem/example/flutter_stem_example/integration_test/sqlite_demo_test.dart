import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_stem_example/src/app.dart';
import 'package:flutter_stem_example/src/demo_config.dart';
import 'package:flutter_stem_example/src/photo_batch.dart';
import 'package:flutter_stem_example/src/queue_monitor_page.dart';
import 'package:flutter_stem_example/src/widgets/job_card.dart';
import 'package:integration_test/integration_test.dart';
import 'package:stem_flutter_sqlite/stem_flutter_sqlite.dart';

const _screenKey = ValueKey('demo-screen');
const _pushKey = ValueKey('push-job');

Future<void> _waitUntil(
  WidgetTester tester,
  bool Function() ready, {
  required String reason,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    final pages = find.byType(QueueMonitorPage);
    if (pages.evaluate().isNotEmpty) {
      expect(tester.widget<QueueMonitorPage>(pages).bootError, isNull);
    }
  }
  expect(ready(), isTrue, reason: reason);
}

Future<void> _closeApp(WidgetTester tester, StemApp app) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _waitUntil(
    tester,
    () => !app.isStarted,
    reason: 'Removing the root must initiate its owned app shutdown.',
  );
  // The root has finished its debug reads and initiated shutdown. Join the
  // same idempotent future before reopening the database files.
  await app.shutdown().timeout(const Duration(seconds: 10));
}

Future<void> _saveScreenshot(WidgetTester tester) async {
  const path = String.fromEnvironment('STEM_DEMO_SCREENSHOT');
  if (path.isEmpty) return;
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_screenKey),
  );
  final image = await boundary.toImage();
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(path).writeAsBytes(bytes!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;

  testWidgets('scheduler failure leaves a durable job without a UI consumer', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp('stem_wakeup_e2e_');
    final layout = await StemFlutterStorageLayout.forRoot(directory);
    final app = await createDemoApp(layout: layout);
    var wakeupAttempts = 0;
    try {
      await tester.pumpWidget(
        StemFlutterExampleApp(
          createApp: () async => app,
          outputDirectory: '${directory.path}/photos',
          workload: const PhotoWorkload(
            label: 'Test',
            count: 2,
            width: 96,
            height: 64,
          ),
          runLocalWorker: false,
          requestWakeup: () async {
            wakeupAttempts++;
            throw StateError('scheduler unavailable');
          },
        ),
      );
      await _waitUntil(
        tester,
        () =>
            find.byKey(_pushKey).evaluate().isNotEmpty &&
            tester.widget<FilledButton>(find.byKey(_pushKey)).onPressed != null,
        reason: 'Scheduling failure must not prevent durable publication.',
      );
      await tester.tap(find.byKey(_pushKey));
      await _waitUntil(
        tester,
        () =>
            find.textContaining('is queued, but wakeup').evaluate().isNotEmpty,
        reason: 'The committed task and failed wakeup must be distinguished.',
      );
      expect(app.isStarted, isFalse);
      expect(await app.broker.pendingCount(queueName), 2);
      final attemptsBeforeRetry = wakeupAttempts;
      await tester.ensureVisible(find.text('Retry wakeup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry wakeup'));
      await tester.pumpAndSettle();
      expect(wakeupAttempts, attemptsBeforeRetry + 1);
      expect(await app.broker.pendingCount(queueName), 2);
      await _closeApp(tester, app);
      final reopened = await createDemoApp(layout: layout);
      try {
        expect(reopened.isStarted, isFalse);
        expect(await reopened.broker.pendingCount(queueName), 2);
      } finally {
        await reopened.shutdown();
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await app.shutdown();
      await directory.delete(recursive: true);
    }
  });

  testWidgets('SQLite demo executes a job and restores it after reopening', (
    tester,
  ) async {
    // Exercise the production factory and native SQLite without touching the
    // developer's existing demo database in application support.
    final directory = await Directory.systemTemp.createTemp('stem_demo_e2e_');
    final layout = await StemFlutterStorageLayout.forRoot(directory);
    StemApp? activeApp;

    Future<void> openDemo() async {
      await tester.pumpWidget(
        RepaintBoundary(
          key: _screenKey,
          child: StemFlutterExampleApp(
            outputDirectory: '${directory.path}/photos',
            workload: const PhotoWorkload(
              label: 'Test',
              count: 1,
              width: 96,
              height: 64,
            ),
            createApp: () async {
              final app = await createDemoApp(layout: layout);
              activeApp = app;
              return app;
            },
          ),
        ),
      );
      await _waitUntil(
        tester,
        () =>
            activeApp?.isStarted == true &&
            find.byKey(_pushKey).evaluate().isNotEmpty &&
            tester.widget<FilledButton>(find.byKey(_pushKey)).onPressed != null,
        reason: 'The real SQLite app should start and enable task submission.',
      );
    }

    try {
      await openDemo();
      expect(await layout.brokerFile.exists(), isTrue);
      expect(await layout.backendFile.exists(), isTrue);
      expect(find.byType(JobCard), findsNothing);

      await tester.tap(find.byKey(_pushKey));
      await _waitUntil(
        tester,
        () => tester
            .widget<QueueMonitorPage>(find.byType(QueueMonitorPage))
            .monitor!
            .jobs
            .any((job) => job.status.state == TaskState.succeeded),
        reason: 'Push Job should execute and display its persisted result.',
      );
      final status = tester
          .widget<QueueMonitorPage>(find.byType(QueueMonitorPage))
          .monitor!
          .jobs
          .single
          .status;
      expect(status.meta['label'], 'Test');
      final payload = status.payload! as Map;
      for (final key in ['sourcePath', 'previewPath', 'thumbnailPath']) {
        expect(await File(payload[key] as String).exists(), isTrue);
        expect(await File(payload[key] as String).length(), greaterThan(0));
      }
      expect(
        (await activeApp!.waitForTask<Map<String, Object?>>(status.id))?.value,
        status.payload,
      );
      expect(await activeApp!.broker.pendingCount(queueName), 0);
      expect(await activeApp!.broker.inflightCount(queueName), 0);

      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byType(JobCard), 250);
      await _saveScreenshot(tester);
      await _closeApp(tester, activeApp!);
      activeApp = null;

      await openDemo();
      await _waitUntil(
        tester,
        () =>
            tester
                .widget<QueueMonitorPage>(find.byType(QueueMonitorPage))
                .monitor!
                .jobs
                .length ==
            1,
        reason:
            'A new app should display the result saved by the previous app.',
      );
      final restored = tester
          .widget<QueueMonitorPage>(find.byType(QueueMonitorPage))
          .monitor!
          .jobs
          .single
          .status;
      expect(restored.id, status.id);
      expect(restored.state, TaskState.succeeded);
      expect(restored.payload, status.payload);
      expect(tester.takeException(), isNull);
    } finally {
      if (activeApp case final app?) {
        await _closeApp(tester, app);
      } else {
        await tester.pumpWidget(const SizedBox.shrink());
      }
      await directory.delete(recursive: true);
    }
  });
}
