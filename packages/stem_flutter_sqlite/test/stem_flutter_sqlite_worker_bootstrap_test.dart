import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stem_flutter_sqlite/stem_flutter_sqlite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'round-trips bootstrap payloads through isolate-safe messages',
    () async {
      final port = ReceivePort();
      addTearDown(port.close);

      final rootToken = RootIsolateToken.instance;
      expect(rootToken, isNotNull);

      final bootstrap = StemFlutterSqliteWorkerBootstrap(
        sendPort: port.sendPort,
        rootIsolateToken: rootToken!,
        brokerPath: '/tmp/broker.sqlite',
        backendPath: '/tmp/backend.sqlite',
        timeMachineAssets: <String, Uint8List>{
          'cultures/cultures.bin': Uint8List.fromList(<int>[1, 2]),
          'tzdb/tzdb.bin': Uint8List.fromList(<int>[3, 4, 5]),
        },
        brokerPollInterval: const Duration(milliseconds: 250),
        brokerSweeperInterval: const Duration(seconds: 2),
        brokerVisibilityTimeout: const Duration(seconds: 6),
      );

      final decoded = StemFlutterSqliteWorkerBootstrap.fromMessage(
        bootstrap.toMessage(),
      );
      decoded.sendPort.send('ping');

      expect(await port.first, 'ping');
      expect(decoded.rootIsolateToken, same(rootToken));
      expect(decoded.brokerPath, '/tmp/broker.sqlite');
      expect(decoded.backendPath, '/tmp/backend.sqlite');
      expect(
        decoded.timeMachineAssets['tzdb/tzdb.bin'],
        orderedEquals(Uint8List.fromList(<int>[3, 4, 5])),
      );
      expect(decoded.brokerPollInterval, const Duration(milliseconds: 250));
      expect(decoded.brokerSweeperInterval, const Duration(seconds: 2));
      expect(decoded.brokerVisibilityTimeout, const Duration(seconds: 6));
    },
  );
}
