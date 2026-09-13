import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:stem_flutter/src/workflow/workflow_host_controller.dart';

/// Provides a [WorkflowHostController] to descendants and observes foreground
/// transitions for recovery.
///
/// The caller owns the controller and must close/dispose it. Removing this
/// scope only detaches widget/lifecycle listeners.
final class WorkflowHostScope extends StatefulWidget {
  /// Creates a scope with caller-owned loading and error presentation.
  const WorkflowHostScope({
    required this.controller,
    required this.child,
    this.loadingBuilder,
    this.errorBuilder,
    super.key,
  });

  /// Controller exposed to descendants.
  final WorkflowHostController controller;

  /// Content shown once loading completes or when no loading builder is given.
  final Widget child;

  /// Builds content while a factory host is starting.
  final WidgetBuilder? loadingBuilder;

  /// Builds content for startup/recovery errors.
  final Widget Function(BuildContext context, Object error, StackTrace? stack)?
  errorBuilder;

  /// Finds the nearest workflow host controller.
  static WorkflowHostController of(BuildContext context) {
    final inherited = context
        .dependOnInheritedWidgetOfExactType<_WorkflowHostInherited>();
    if (inherited == null) {
      throw StateError('No WorkflowHostScope found in context.');
    }
    return inherited.controller;
  }

  @override
  State<WorkflowHostScope> createState() => _WorkflowHostScopeState();
}

final class _WorkflowHostScopeState extends State<WorkflowHostScope>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_changed);
    unawaited(widget.controller.start());
  }

  @override
  void didUpdateWidget(WorkflowHostScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      unawaited(widget.controller.start());
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller.recover());
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    Widget content;
    if (controller.error != null && widget.errorBuilder != null) {
      content = widget.errorBuilder!(
        context,
        controller.error!,
        controller.errorStack,
      );
    } else if (controller.isLoading && widget.loadingBuilder != null) {
      content = widget.loadingBuilder!(context);
    } else {
      content = widget.child;
    }
    return _WorkflowHostInherited(controller: controller, child: content);
  }
}

final class _WorkflowHostInherited
    extends InheritedNotifier<WorkflowHostController> {
  const _WorkflowHostInherited({
    required WorkflowHostController controller,
    required super.child,
  }) : super(notifier: controller);

  WorkflowHostController get controller => notifier!;
}
