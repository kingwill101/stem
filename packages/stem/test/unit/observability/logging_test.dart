import 'package:contextual/contextual.dart'
    show
        LogDriver,
        LogEntry,
        LoggerChannelSelection,
        PlainTextLogFormatter,
        PrettyLogFormatter;
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

  test('createStemLogger defaults to the pretty formatter', () async {
    final logger = createStemLogger(enableConsole: false);
    final driver = _RecordingLogDriver();
    logger.addChannel('recording', driver);

    logger.channel('recording').info('default pretty mode');
    await logger.shutdown();

    expect(driver.entries, hasLength(1));
  });

  test('createStemLogFormatter returns the pretty formatter', () {
    expect(
      createStemLogFormatter(StemLogFormat.pretty),
      isA<PrettyLogFormatter>(),
    );
  });

  test(
    'configureStemLogging can switch the shared logger to pretty mode',
    () async {
      final original = stemLogger;
      addTearDown(() => setStemLogger(original));
      final replacement = createStemLogger(enableConsole: false);
      final driver = _RecordingLogDriver();
      replacement.addChannel('recording', driver);
      setStemLogger(replacement);

      configureStemLogging(format: StemLogFormat.pretty);
      stemLogger.channel('recording').info('pretty shared mode');
      await stemLogger.shutdown();

      expect(driver.entries, hasLength(1));
      expect(
        createStemLogFormatter(StemLogFormat.pretty),
        isA<PrettyLogFormatter>(),
      );
    },
  );

  test('createStemLogFormatter returns the plain formatter', () {
    expect(
      createStemLogFormatter(StemLogFormat.plain),
      isA<PlainTextLogFormatter>(),
    );
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

class _RecordingLogDriver extends LogDriver {
  _RecordingLogDriver() : entries = <LogEntry>[], super('recording');

  final List<LogEntry> entries;

  @override
  Future<void> log(LogEntry entry) async {
    entries.add(entry);
  }
}
