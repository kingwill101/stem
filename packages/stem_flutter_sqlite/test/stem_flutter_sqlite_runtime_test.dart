import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stem/stem.dart';
import 'package:stem_flutter/stem_flutter.dart';
import 'package:stem_flutter_sqlite/stem_flutter_sqlite.dart';

Future<void> _sqliteLauncherEntry(Map<String, Object?> message) async {
  final bootstrap = StemFlutterSqliteWorkerBootstrap.fromMessage(message);
  final commands = ReceivePort();
  await Future<void>.delayed(const Duration(milliseconds: 20));
  bootstrap.sendPort.send(
    StemFlutterWorkerSignal.ready(commandPort: commands.sendPort).toMessage(),
  );
  await Future<void>.delayed(const Duration(milliseconds: 20));
  bootstrap.sendPort.send(
    StemFlutterWorkerSignal.status(
      status: StemFlutterWorkerStatus.running,
      detail:
          '${bootstrap.brokerPath}|${bootstrap.backendPath}|'
          '${bootstrap.timeMachineAssets.length}',
    ).toMessage(),
  );

  await for (final command in commands) {
    if (command is Map<Object?, Object?> && command['type'] == 'shutdown') {
      commands.close();
      return;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StemFlutterSqliteRuntime', () {
    test(
      'open creates a foreground runtime backed by separate sqlite files',
      () async {
        final sandbox = await Directory.systemTemp.createTemp(
          'stem_flutter_sqlite_runtime_test_',
        );
        addTearDown(() => sandbox.delete(recursive: true));

        final layout = await StemFlutterStorageLayout.forRoot(
          Directory('${sandbox.path}${Platform.pathSeparator}runtime'),
        );
        final runtime = await StemFlutterSqliteRuntime.open(
          layout: layout,
          tasks: const <TaskHandler<Object?>>[],
        );
        addTearDown(runtime.close);

        expect(runtime.layout.root.path, layout.root.path);
        expect(layout.brokerFile.existsSync(), isTrue);
        expect(layout.backendFile.existsSync(), isTrue);
        expect(runtime.broker, isNotNull);
        expect(runtime.backend, isNotNull);
        expect(runtime.stem, isNotNull);
      },
    );

    test(
      'launcher forwards sqlite bootstrap details into the worker isolate',
      () async {
        final sandbox = await Directory.systemTemp.createTemp(
          'stem_flutter_sqlite_launcher_test_',
        );
        addTearDown(() => sandbox.delete(recursive: true));

        final layout = await StemFlutterStorageLayout.forRoot(
          Directory('${sandbox.path}${Platform.pathSeparator}runtime'),
        );
        final rootToken = RootIsolateToken.instance;
        expect(rootToken, isNotNull);

        final host = await StemFlutterSqliteWorkerLauncher.spawn(
          entrypoint: _sqliteLauncherEntry,
          layout: layout,
          rootIsolateToken: rootToken!,
          brokerPollInterval: const Duration(milliseconds: 250),
          brokerSweeperInterval: const Duration(seconds: 2),
          brokerVisibilityTimeout: const Duration(seconds: 6),
        );
        addTearDown(host.dispose);

        final ready = await host.signals
            .firstWhere(
              (signal) => signal.type == StemFlutterWorkerSignalType.ready,
            )
            .timeout(const Duration(seconds: 5));
        expect(ready.commandPort, isNotNull);

        final running = await host.signals
            .firstWhere(
              (signal) =>
                  signal.type == StemFlutterWorkerSignalType.status &&
                  signal.status == StemFlutterWorkerStatus.running,
            )
            .timeout(const Duration(seconds: 5));

        final detailParts = running.detail!.split('|');
        expect(detailParts[0], layout.brokerFile.path);
        expect(detailParts[1], layout.backendFile.path);
        expect(int.parse(detailParts[2]), greaterThanOrEqualTo(2));
      },
    );
  });
}
