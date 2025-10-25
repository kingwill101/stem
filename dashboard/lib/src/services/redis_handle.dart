import 'dart:async';

import 'package:redis/redis.dart';

class RedisHandle {
  RedisHandle(this._connection, this._command);

  final RedisConnection _connection;
  final Command _command;

  Future<void> close() async {
    try {
      await _connection.close();
    } catch (_) {}
  }

  Future<dynamic> send(List<Object> command) {
    return _enqueue(() => _command.send_object(command));
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final next = _serial.then((_) => action());
    _serial = next.then((_) => null, onError: (_) => null);
    return next;
  }

  Future<void> _serial = Future.value();
}
