import 'package:stem/stem.dart';

class WorkflowCliContext {
  WorkflowCliContext({
    required this.runtime,
    required this.store,
    Future<void> Function()? dispose,
  }) : _dispose = dispose ?? (() async {});

  final WorkflowRuntime runtime;
  final WorkflowStore store;
  final Future<void> Function() _dispose;

  Future<void> dispose() => _dispose();
}
