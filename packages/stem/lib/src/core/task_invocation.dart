/// Task invocation API selected for the current runtime.
///
/// VM builds retain isolate-backed invocation support. JS-targeted builds use
/// the portable implementation, whose local context has no isolate imports.
library;

export 'task_invocation_portable.dart'
    if (dart.library.io) 'task_invocation_vm.dart';
