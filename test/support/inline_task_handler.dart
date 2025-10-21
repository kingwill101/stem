import 'dart:async';

import 'package:stem/stem.dart';

typedef InlineTaskCallback<R> = FutureOr<R> Function(
    TaskContext context, Map<String, Object?> args);

class InlineTaskHandler<R> extends TaskHandler<R> {
  InlineTaskHandler({
    required this.name,
    required InlineTaskCallback<R> onCall,
    TaskOptions options = const TaskOptions(),
  })  : _onCall = onCall,
        _options = options;

  @override
  final String name;

  final InlineTaskCallback<R> _onCall;
  final TaskOptions _options;

  @override
  TaskOptions get options => _options;

  @override
  Future<R> call(TaskContext context, Map<String, Object?> args) async {
    return await _onCall(context, args);
  }

  @override
  TaskEntrypoint? get isolateEntrypoint => null;
}
