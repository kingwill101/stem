import 'package:contextual/contextual.dart' as contextual;
import 'package:stem/stem.dart';
import 'package:stem_sqlite/src/database/datasource.dart';
import 'package:test/test.dart';

void main() {
  test('createDataSource forwards logger and logging flags', () {
    final logger = contextual.Logger();
    final dataSource = createDataSource(logging: true, logger: logger);

    expect(dataSource.options.logging, isTrue);
    expect(dataSource.options.logger, same(logger));
  });

  test('createDataSource defaults to stemLogger', () {
    final dataSource = createDataSource();

    expect(dataSource.options.logger, same(stemLogger));
  });
}
