import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_stem_example/src/wakeup_control.dart';
import 'package:sqlite3/sqlite3.dart';

Future<bool> pauseInIsolate(String path, SendPort signal) =>
    Isolate.run(() async {
      final other = WakeupControl(
        path: path,
        register: () async {},
        cancel: () async {},
      );
      signal.send('attempting');
      await other.pause();
      return other.isPaused();
    });

void main() {
  late Directory directory;
  late String path;
  late List<String> calls;
  late WakeupControl control;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('wakeup-control-');
    path = '${directory.path}/control.sqlite';
    calls = [];
    control = WakeupControl(
      path: path,
      register: () async => calls.add('register'),
      cancel: () async => calls.add('cancel'),
    );
  });
  tearDown(() => directory.delete(recursive: true));

  test('pause survives reopening, automatic requests, and startup', () async {
    await control.pause();
    final reopened = WakeupControl(
      path: path,
      register: () async => calls.add('register'),
      cancel: () async => calls.add('cancel'),
    );
    await reopened.request();
    await reopened.reconcile();
    expect(await reopened.isPaused(), isTrue);
    expect(calls, ['cancel', 'cancel']);
    await reopened.resume();
    await reopened.request();
    expect(await reopened.isPaused(), isFalse);
    expect(calls, ['cancel', 'cancel', 'register', 'register']);
  });

  test(
    'pause is committed before native failure and repaired on startup',
    () async {
      final failing = WakeupControl(
        path: path,
        register: () async {},
        cancel: () async {
          // A separate connection sees committed intent during native effects.
          final db = sqlite3.open(path);
          try {
            expect(
              db.select('SELECT paused FROM wakeup_control').single['paused'],
              1,
            );
          } finally {
            db.close();
          }
          throw StateError('native cancellation failed');
        },
      );
      await expectLater(failing.pause(), throwsStateError);
      expect(await control.isPaused(), isTrue);
      await control.request();
      await control.reconcile();
      expect(calls, ['cancel']);
    },
  );

  test('native calls serialize while lock waits yield to event loop', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final slow = WakeupControl(
      path: path,
      register: () async {
        calls.add('start');
        started.complete();
        await release.future;
        calls.add('end');
      },
      cancel: () async {},
    );
    final registration = slow.request();
    await started.future;
    final cancellation = control.pause();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(calls, ['start']);
    release.complete();
    await registration;
    await cancellation;
    expect(calls, ['start', 'end', 'cancel']);
    expect(await control.isPaused(), isTrue);
  });

  test('another isolate observes durable pause', () async {
    await control.pause();
    final databasePath = path;
    final paused = await Isolate.run(() async {
      final other = WakeupControl(
        path: databasePath,
        register: () => throw StateError('paused isolate registered'),
        cancel: () async {},
      );
      await other.request();
      return other.isPaused();
    });
    expect(paused, isTrue);
  });

  test(
    'stalled registration cannot block durable pause or admission reads',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final repaired = Completer<void>();
      var repairs = 0;
      final stalled = WakeupControl(
        path: path,
        effectWait: const Duration(milliseconds: 50),
        register: () async {
          calls.add('register start');
          entered.complete();
          await release.future;
          calls.add('register end');
        },
        cancel: () async {
          calls.add('repair cancel');
          if (++repairs == 2) repaired.complete();
        },
      );
      final registration = expectLater(
        stalled.request(),
        throwsA(isA<TimeoutException>()),
      );
      await entered.future;
      final pause = expectLater(
        stalled.pause(),
        throwsA(isA<TimeoutException>()),
      );
      await pause;
      await registration;
      expect(await control.isPaused(), isTrue);
      await control.request();
      expect(calls, ['register start']);
      // Caller timeout must not release the native-effect mutex. Once the
      // original native call really finishes, it repairs to the latest pause.
      release.complete();
      await repaired.future;
      await control.reconcile();
      expect(
        calls.indexOf('register end'),
        lessThan(calls.indexOf('repair cancel')),
      );
      expect(await control.isPaused(), isTrue);
    },
  );

  test('late failed cancellation repairs a newer explicit resume', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final registered = Completer<void>();
    var registrations = 0;
    final stalled = WakeupControl(
      path: path,
      effectWait: const Duration(milliseconds: 50),
      register: () async {
        if (++registrations == 2) registered.complete();
      },
      cancel: () async {
        entered.complete();
        await release.future;
        throw StateError('late platform failure');
      },
    );
    final pause = expectLater(
      stalled.pause(),
      throwsA(isA<TimeoutException>()),
    );
    await entered.future;
    await expectLater(stalled.resume(), throwsA(isA<TimeoutException>()));
    await pause;
    expect(await control.isPaused(), isFalse);
    release.complete();
    await registered.future;
    await control.reconcile();
    expect(await control.isPaused(), isFalse);
  });

  test('a different isolate cannot overtake a native effect', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final slow = WakeupControl(
      path: path,
      register: () async {
        started.complete();
        await release.future;
      },
      cancel: () async {},
    );
    final registration = slow.request();
    await started.future;
    final databasePath = path;
    final attempting = ReceivePort();
    final signal = attempting.sendPort;
    final cancellation = pauseInIsolate(databasePath, signal);
    await attempting.first;
    attempting.close();
    var finished = false;
    final observed = cancellation.then((value) {
      finished = true;
      return value;
    });
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(finished, isFalse);
    release.complete();
    await registration;
    expect(await observed, isTrue);
    expect(await control.isPaused(), isTrue);
  });
}
