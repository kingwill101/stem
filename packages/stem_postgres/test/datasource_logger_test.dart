import 'package:contextual/contextual.dart' as contextual;
import 'package:stem/observability.dart' show stemLogger;
import 'package:stem_postgres/src/database/datasource.dart';
import 'package:test/test.dart';

void main() {
  test('createDataSource accepts a Stem logger and enables ORM logging', () {
    final dataSource = createDataSource(
      connectionString: 'postgresql://user:pass@localhost:5432/stem',
      logging: true,
      logger: stemLogger,
    );

    expect(dataSource.options.logging, isTrue);
    expect(dataSource.options.logger, isA<contextual.Logger>());
  });

  test('createDataSource defaults to stemLogger', () {
    final dataSource = createDataSource(
      connectionString: 'postgresql://user:pass@localhost:5432/stem',
    );

    expect(dataSource.options.logger, isA<contextual.Logger>());
  });
}
