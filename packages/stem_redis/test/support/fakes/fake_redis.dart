import 'dart:async';
import 'dart:collection';

import 'package:redis/redis.dart';

typedef RedisCommandResponder =
    FutureOr<Object?> Function(List<Object?> command);

class FakeRedisConnection extends RedisConnection {
  bool closed = false;

  @override
  Future close() async {
    closed = true;
  }
}

class FakeRedisCommand extends Command {
  FakeRedisCommand(this.fakeConnection) : super(fakeConnection);

  final FakeRedisConnection fakeConnection;
  final Queue<RedisCommandResponder> _responders = Queue();
  final List<List<Object?>> sent = [];

  void queueResponse(RedisCommandResponder responder) {
    _responders.add(responder);
  }

  @override
  // ignore: non_constant_identifier_names
  Future send_object(Object obj) async {
    final command = (obj as List).cast<Object?>();
    sent.add(command);
    if (command.isNotEmpty && command.first == 'XREADGROUP') {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    if (_responders.isEmpty) {
      return null;
    }
    final responder = _responders.removeFirst();
    final result = responder(command);
    if (result is Future) {
      return await result;
    }
    return result;
  }
}
