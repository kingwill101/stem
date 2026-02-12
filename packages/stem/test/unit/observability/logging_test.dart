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
    addTearDown(() => setStemLogger(original));
    final replacement = Logger();

    setStemLogger(replacement);
    expect(identical(stemLogger, replacement), isTrue);
  });

  test('stemContextFields includes component and subsystem', () {
    final context = stemContextFields(
      component: 'stem',
      subsystem: 'worker',
      fields: const {'queue': 'default'},
    );

    expect(context['component'], 'stem');
    expect(context['subsystem'], 'worker');
    expect(context['queue'], 'default');
  });
}
