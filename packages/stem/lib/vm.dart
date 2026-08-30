/// Stem APIs for Dart VM worker and daemon runtimes.
///
/// Existing `stable.dart` and `stem.dart` imports remain supported. This
/// entrypoint makes the VM dependency explicit for new worker applications.
library;

export 'src/core/task_invocation_vm.dart';
export 'stable.dart';
