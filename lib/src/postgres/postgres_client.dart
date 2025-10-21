import 'dart:async';
import 'package:postgres/postgres.dart';

class PostgresClient {
  PostgresClient(String connectionString, {String? applicationName})
    : _uri = Uri.parse(connectionString),
      _applicationName = applicationName;

  final Uri _uri;
  final String? _applicationName;
  PostgreSQLConnection? _connection;
  Future<void>? _opening;
  Future<void> _operationChain = Future<void>.value();

  Future<T> run<T>(Future<T> Function(PostgreSQLConnection conn) action) {
    final completer = Completer<T>();
    _operationChain = _operationChain.then((_) async {
      try {
        final conn = await _ensureOpen();
        final result = await action(conn);
        completer.complete(result);
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  Future<void> close() async {
    _operationChain = _operationChain.then((_) async {
      if (_connection != null && !_connection!.isClosed) {
        await _connection!.close();
      }
      _connection = null;
    });
    await _operationChain;
  }

  Future<PostgreSQLConnection> _ensureOpen() async {
    if (_connection != null && !_connection!.isClosed) {
      return _connection!;
    }
    if (_opening != null) {
      await _opening;
      return _connection!;
    }
    _opening = _openConnection();
    await _opening;
    _opening = null;
    return _connection!;
  }

  Future<void> _openConnection() async {
    final host = _uri.host.isEmpty ? 'localhost' : _uri.host;
    final port = _uri.hasPort ? _uri.port : 5432;
    var database = _uri.path.isEmpty ? '' : _uri.path.substring(1);
    if (database.isEmpty) {
      database = 'postgres';
    }
    String? username;
    String? password;
    if (_uri.userInfo.isNotEmpty) {
      final parts = _uri.userInfo.split(':');
      username = parts.isNotEmpty ? parts.first : null;
      password = parts.length > 1 ? parts[1] : null;
    }
    final useSSL = _shouldUseSsl(_uri);
    final conn = PostgreSQLConnection(
      host,
      port,
      database,
      username: username,
      password: password,
      useSSL: useSSL,
      timeoutInSeconds: 30,
    );
    await conn.open();
    final appName = _applicationName;
    if (appName != null && appName.isNotEmpty) {
      await conn.execute(
        'SET application_name = @appName',
        substitutionValues: {'appName': appName},
      );
    }
    _connection = conn;
  }

  bool _shouldUseSsl(Uri uri) {
    final sslMode = uri.queryParameters['sslmode'];
    if (sslMode != null) {
      return sslMode.toLowerCase() == 'require';
    }
    return uri.scheme == 'postgresql+ssl' || uri.scheme == 'postgres+ssl';
  }
}
