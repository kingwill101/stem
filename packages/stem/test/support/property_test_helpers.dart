import 'package:property_testing/property_testing.dart';
import 'package:test/test.dart';

final PropertyConfig fastPropertyConfig = PropertyConfig(numTests: 25);
final PropertyConfig defaultPropertyConfig = PropertyConfig(numTests: 50);

const ChaosConfig defaultChaosConfig = ChaosConfig(
  maxLength: 128,
  intensity: 0.6,
);

Future<void> expectProperty<T>(
  PropertyTestRunner<T> runner, {
  required String description,
}) async {
  final result = await runner.run();
  if (!result.success) {
    throw TestFailure('Property failed ($description): ${result.report}');
  }
}
