/// Flutter bootstrap for the ordinary Stem application API.
///
/// Use `StemFlutter.createApp` to create a core `StemApp`, then explicitly
/// start its worker. Tasks, execution, results, and diagnostics use Stem APIs.
library;

export 'package:stem/stable.dart';

export 'src/runtime/stem_flutter.dart' show StemFlutter;
export 'src/workflow/hosted_run_builder.dart' show HostedRunBuilder;
export 'src/workflow/workflow_host_controller.dart'
    show WorkflowHostController, WorkflowHostFactory;
export 'src/workflow/workflow_host_scope.dart' show WorkflowHostScope;
