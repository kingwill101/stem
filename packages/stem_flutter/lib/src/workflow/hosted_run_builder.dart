import 'package:flutter/widgets.dart';
import 'package:stem/stable.dart';

/// Builds UI from the existing persisted [WorkflowRunView] snapshots.
///
/// This widget intentionally does not decode results. Use [HostedRun.result]
/// when a typed terminal result is required.
final class HostedRunBuilder<R> extends StatefulWidget {
  /// Creates a builder that listens to [run] snapshots.
  const HostedRunBuilder({
    required this.run,
    required this.builder,
    this.initialData,
    this.errorBuilder,
    super.key,
  });

  /// The core hosted run to observe.
  final HostedRun<R> run;

  /// Builds the current core snapshot.
  final Widget Function(BuildContext context, WorkflowRunView snapshot) builder;

  /// Optional snapshot shown before the stream emits.
  final WorkflowRunView? initialData;

  /// Builds stream errors, when provided.
  final Widget Function(BuildContext context, Object error, StackTrace stack)?
  errorBuilder;

  @override
  State<HostedRunBuilder<R>> createState() => _HostedRunBuilderState<R>();
}

class _HostedRunBuilderState<R> extends State<HostedRunBuilder<R>> {
  late Stream<WorkflowRunView> _stream;

  @override
  void initState() {
    super.initState();
    _stream = widget.run.watch();
  }

  @override
  void didUpdateWidget(HostedRunBuilder<R> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.run, widget.run)) {
      _stream = widget.run.watch();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<WorkflowRunView>(
      key: ObjectKey(widget.run),
      stream: _stream,
      initialData: widget.initialData,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return widget.errorBuilder?.call(
                context,
                snapshot.error!,
                snapshot.stackTrace ?? StackTrace.current,
              ) ??
              ErrorWidget(snapshot.error!);
        }
        final view = snapshot.data;
        if (view == null) return const SizedBox.shrink();
        return widget.builder(context, view);
      },
    );
  }
}
