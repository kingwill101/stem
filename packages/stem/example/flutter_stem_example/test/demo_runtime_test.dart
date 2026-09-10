import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_stem_example/src/app.dart';
import 'package:flutter_stem_example/src/demo_tasks.dart';
import 'package:stem/advanced.dart' show StemSignals;
import 'package:stem_flutter_sqlite/stem_flutter_sqlite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('photo interruption recovery uses a finite task retry budget', () {
    expect(
      preparePhoto.defaultOptions.recoveryPolicy,
      TaskRecoveryPolicy.retry,
    );
    expect(preparePhoto.defaultOptions.maxRetries, 3);
    expect(preparePhoto.metadata.idempotent, isTrue);
  });

  test('photo runtime retires task isolates between durable photos', () async {
    final directory = await Directory.systemTemp.createTemp(
      'stem-photo-runtime-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final layout = await StemFlutterStorageLayout.forRoot(directory);
    final app = await createDemoApp(layout: layout);
    addTearDown(app.close);
    final spawned = <int>{};
    final disposed = <int>{};
    final init = StemSignals.workerChildInit.connect((payload, _) {
      spawned.add(payload.isolateId);
    });
    final shutdown = StemSignals.workerChildShutdown.connect((payload, _) {
      disposed.add(payload.isolateId);
    });
    addTearDown(init.cancel);
    addTearDown(shutdown.cancel);
    final ids = <String>[];
    for (var index = 0; index < 2; index++) {
      ids.add(
        await app.enqueueCall(
          preparePhoto.buildCall(
            PhotoTaskArgs(
              outputDirectory: '${directory.path}/photos',
              batchId: 'runtime-test',
              index: index,
              width: 96,
              height: 64,
            ),
          ),
        ),
      );
    }
    final outcome = await app.runUntilIdle(budget: const Duration(seconds: 30));
    expect(outcome.reason, WorkerRunStopReason.idle);
    expect(outcome.deliveriesProcessed, 2);
    expect(spawned.length, greaterThanOrEqualTo(2));
    expect(disposed, unorderedEquals(spawned));

    final observer = await createDemoApp(layout: layout);
    addTearDown(observer.close);
    for (final id in ids) {
      expect((await observer.getTaskStatus(id))?.state, TaskState.succeeded);
    }
  });
}
