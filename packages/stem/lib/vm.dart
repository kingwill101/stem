/// Stem APIs for Dart VM worker and daemon runtimes.
///
/// Existing `stable.dart` and `stem.dart` imports remain supported. This
/// entrypoint makes the VM dependency explicit for new worker applications.
library;

export 'stable.dart';
export 'src/core/task_invocation_vm.dart';
