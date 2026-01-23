import 'package:contextual/contextual.dart';
import 'package:stem/src/observability/logging.dart';
import 'package:test/test.dart';

void main() {
  test('configureStemLogging updates logger level', () {
    configureStemLogging(level: Level.debug);
    configureStemLogging(level: Level.warning);
  });
}
