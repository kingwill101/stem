import 'package:contextual/contextual.dart' as contextual;
import 'package:stem/stem.dart';
import 'package:stem_postgres/src/database/datasource.dart';
import 'package:test/test.dart';

void main() {
  test('createDataSource forwards logger and logging flags', () {
    final logger = contextual.Logger();
    final dataSource = createDataSource(
      connectionString: 'postgresql://user:pass@localhost:5432/stem',
      logging: true,
      logger: logger,
    );

    expect(dataSource.options.logging, isTrue);
    expect(dataSource.options.logger, same(logger));
  });

  test('createDataSource defaults to stemLogger', () {
    final dataSource = createDataSource(
      connectionString: 'postgresql://user:pass@localhost:5432/stem',
    );

    expect(dataSource.options.logger, same(stemLogger));
  });
}
