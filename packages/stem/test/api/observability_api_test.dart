import 'package:stem/observability.dart';
import 'package:test/test.dart';

void main() {
  test('observability entrypoint exposes Stem-owned logging configuration', () {
    expect(StemLogLevel.warning, isA<StemLogLevel>());
    expect(StemLogFormat.plain, isA<StemLogFormat>());

    configureStemLogging(
      level: StemLogLevel.warning,
      format: StemLogFormat.plain,
      enableConsole: false,
    );
    stemLogger.info(
      'structured message',
      fields: const {'component': 'api-test'},
    );
  });
}
