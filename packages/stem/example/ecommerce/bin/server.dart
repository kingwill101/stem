import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:stem_ecommerce_example/ecommerce.dart';

Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '8085') ?? 8085;
  final databasePath = Platform.environment['ECOMMERCE_DB_PATH'];

  final app = await EcommerceServer.create(databasePath: databasePath);
  final server = await shelf_io.serve(
    app.handler,
    InternetAddress.anyIPv4,
    port,
  );

  stdout.writeln(
    'Ecommerce API running on http://${server.address.address}:${server.port}',
  );
  stdout.writeln('Database: ${app.repository.databasePath}');
  stdout.writeln('Endpoints:');
  stdout.writeln('  GET    /health');
  stdout.writeln('  GET    /catalog');
  stdout.writeln('  POST   /carts');
  stdout.writeln('  GET    /carts/<cartId>');
  stdout.writeln('  POST   /carts/<cartId>/items');
  stdout.writeln('  POST   /checkout/<cartId>');
  stdout.writeln('  GET    /orders/<orderId>');
  stdout.writeln('  GET    /runs/<runId>');

  Future<void> shutdown([ProcessSignal? signal]) async {
    if (signal != null) {
      stdout.writeln('Received $signal, shutting down...');
    }
    await server.close(force: true);
    await app.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(shutdown);
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen(shutdown);
  }
}
