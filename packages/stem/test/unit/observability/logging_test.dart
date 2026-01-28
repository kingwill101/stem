import 'package:contextual/contextual.dart';
import 'package:stem/src/observability/logging.dart';
import 'package:test/test.dart';

void main() {
  test('configureStemLogging updates logger level', () {
    configureStemLogging(level: Level.debug);
    configureStemLogging(level: Level.warning);
  });

  test('setStemLogger replaces the shared logger', () {
    final original = stemLogger;
    final replacement = Logger();

    setStemLogger(replacement);
    expect(identical(stemLogger, replacement), isTrue);

    setStemLogger(original);
  });
}
