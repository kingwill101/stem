import 'package:stem/src/worker/worker_config.dart';
import 'package:test/test.dart';

void main() {
  group('WorkerAutoscaleConfig', () {
    test('defaults minConcurrency to 1', () {
      const config = WorkerAutoscaleConfig(minConcurrency: 0);
      expect(config.minConcurrency, equals(1));
    });

    test('copyWith overrides selected fields', () {
      const config = WorkerAutoscaleConfig(enabled: true, maxConcurrency: 8);
      final updated = config.copyWith(scaleUpStep: 3);

      expect(updated.enabled, isTrue);
      expect(updated.maxConcurrency, equals(8));
      expect(updated.scaleUpStep, equals(3));
    });
  });

  group('WorkerLifecycleConfig', () {
    test('copyWith preserves defaults and updates values', () {
      const config = WorkerLifecycleConfig();
      final updated = config.copyWith(
        installSignalHandlers: false,
        maxTasksPerIsolate: 5,
      );

      expect(updated.installSignalHandlers, isFalse);
      expect(updated.maxTasksPerIsolate, equals(5));
      expect(updated.forceShutdownAfter, equals(const Duration(seconds: 10)));
    });
  });
}
