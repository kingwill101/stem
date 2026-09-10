import 'dart:io';

import 'package:flutter/material.dart';
import 'package:stem/observability.dart';
import 'package:workmanager/workmanager.dart';

import 'src/android_background.dart';
import 'src/app.dart';
import 'src/android_status_notifications.dart';

void _configureLogging() {
  configureStemLogging(
    level: StemLogLevel.debug,
    format: StemLogFormat.plain,
    enableConsole: true,
  );
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  _configureLogging();
  Workmanager().executeTask((task, inputData) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('This example supports Android Workmanager only.');
    }
    return executeDemoBackgroundTask(task);
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _configureLogging();
  if (!Platform.isAndroid) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'Workmanager mode is Android-only. Use lib/main.dart here.',
            ),
          ),
        ),
      ),
    );
    return;
  }
  // Initialization is retried by the UI wakeup action if it fails. Booting the
  // producer does not depend on OS scheduling being available.
  Future<void> initializeAndReconcile() async {
    await Workmanager().initialize(callbackDispatcher);
    await reconcileQueueWakeups();
  }

  Future<void> initializeAndResume() async {
    await Workmanager().initialize(callbackDispatcher);
    await resumeQueueWakeups();
  }

  runApp(
    StemFlutterExampleApp(
      runLocalWorker: false,
      startupWakeup: initializeAndReconcile,
      requestWakeup: initializeAndResume,
      cancelWakeups: cancelQueueWakeups,
      requestNotificationPermission:
          AndroidStatusNotifications.instance.requestPermission,
      onPhotosCommitted: AndroidStatusNotifications.instance.queued,
    ),
  );
}
