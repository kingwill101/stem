import 'package:contextual/contextual.dart' as contextual;
import 'package:stem/observability.dart' show stemLogger;
import 'package:stem_sqlite/src/database/datasource.dart';
import 'package:test/test.dart';

void main() {
  test('createDataSource accepts a Stem logger and enables ORM logging', () {
    final dataSource = createDataSource(logging: true, logger: stemLogger);

    expect(dataSource.options.logging, isTrue);
    expect(dataSource.options.logger, isA<contextual.Logger>());
  });

  test('createDataSource defaults to stemLogger', () {
    final dataSource = createDataSource();

    expect(dataSource.options.logger, isA<contextual.Logger>());
  });
}
