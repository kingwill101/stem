import 'package:flutter_test/flutter_test.dart';
import 'package:stem_flutter/stem_flutter.dart';

void main() {
  group('StemFlutterWorkerSignal', () {
    test('round-trips status messages', () {
      const signal = StemFlutterWorkerSignal.status(
        status: StemFlutterWorkerStatus.waiting,
        detail: 'Last heartbeat 10:00:00',
      );

      final parsed = StemFlutterWorkerSignal.tryParse(signal.toMessage());

      expect(parsed, isNotNull);
      expect(parsed!.type, StemFlutterWorkerSignalType.status);
      expect(parsed.status, StemFlutterWorkerStatus.waiting);
      expect(parsed.detail, 'Last heartbeat 10:00:00');
    });

    test('parses fatal compatibility messages', () {
      final parsed = StemFlutterWorkerSignal.tryParse(<String, Object?>{
        'type': 'error',
        'error': 'database locked',
      });

      expect(parsed, isNotNull);
      expect(parsed!.type, StemFlutterWorkerSignalType.fatal);
      expect(parsed.message, 'database locked');
    });
  });
}
