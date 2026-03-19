import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  test('package:stem exports logging types used by the public API', () {
    void acceptsStemLogger(Logger logger, Level level) {
      logger.setLevel(level);
    }

    final context = stemLogContext(
      component: 'stem',
      subsystem: 'worker',
    );

    acceptsStemLogger(stemLogger, Level.critical);
    expect(context, isA<Context>());
  });

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
