import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:routed/routed.dart';
import 'package:routed_hotwire/routed_hotwire.dart';
import 'package:stem/stem.dart'
    show TaskState, generateEnvelopeId, stemLogContext, stemLogger;
import 'package:stem_dashboard/src/config/config.dart';
import 'package:stem_dashboard/src/services/models.dart';
import 'package:stem_dashboard/src/services/stem_service.dart';
import 'package:stem_dashboard/src/state/dashboard_state.dart';
import 'package:stem_dashboard/src/stem/control_messages.dart';
import 'package:stem_dashboard/src/ui/content.dart';
import 'package:stem_dashboard/src/ui/layout.dart';
import 'package:stem_dashboard/src/ui/overview.dart';
import 'package:stem_dashboard/src/ui/paths.dart';

/// Mount options for embedding the dashboard in a host app.
class DashboardMountOptions {
  /// Creates mount options.
  const DashboardMountOptions({this.basePath = ''});

  /// Prefix path used when mounting routes into a host app.
  ///
  /// Examples: `''` (root), `'/dashboard'`.
  final String basePath;
}

/// Options controlling how the dashboard server binds to the network.
class DashboardServerOptions {
  /// Creates server options with optional overrides.
  const DashboardServerOptions({
    this.host = '127.0.0.1',
    this.port = 3080,
    this.echoRoutes = false,
    this.basePath = '',
  });

  /// Hostname or IP address for the HTTP server.
  final String host;

  /// TCP port for the HTTP server.
  final int port;

  /// Whether to log each registered route on startup.
  final bool echoRoutes;

  /// Prefix path used when serving the dashboard from a sub-route.
  final String basePath;

  /// Returns a copy with the provided fields replaced.
  DashboardServerOptions copyWith({
    String? host,
    int? port,
    bool? echoRoutes,
    String? basePath,
  }) {
    return DashboardServerOptions(
      host: host ?? this.host,
      port: port ?? this.port,
      echoRoutes: echoRoutes ?? this.echoRoutes,
      basePath: basePath ?? this.basePath,
    );
  }
}

/// Boots the Stem dashboard HTTP server.
Future<void> runDashboardServer({
  DashboardServerOptions options = const DashboardServerOptions(),
  DashboardConfig? config,
  DashboardDataSource? service,
  DashboardState? state,
}) async {
  final serviceOwner = service == null;
  final resolvedConfig =
      config ?? (serviceOwner ? DashboardConfig.load() : null);
  final dashboardService =
      service ?? await StemDashboardService.connect(resolvedConfig!);
  final stateOwner = state == null;
  final dashboardState =
      state ??
      DashboardState(
        service: dashboardService,
        alertWebhookUrls: resolvedConfig?.alertWebhookUrls ?? const [],
        alertBacklogThreshold: resolvedConfig?.alertBacklogThreshold ?? 500,
        alertFailedTaskThreshold:
            resolvedConfig?.alertFailedTaskThreshold ?? 25,
        alertOfflineWorkerThreshold:
            resolvedConfig?.alertOfflineWorkerThreshold ?? 1,
        alertCooldown:
            resolvedConfig?.alertCooldown ?? const Duration(minutes: 5),
      );

  if (stateOwner) {
    await dashboardState.start();
  }
  final engine = buildDashboardEngine(
    service: dashboardService,
    state: dashboardState,
    basePath: options.basePath,
  );
  final resolvedBasePath = normalizeDashboardBasePath(options.basePath);
  final dashboardUrlPath = dashboardRoute(resolvedBasePath, '/');

  stemLogger.info(
    'Starting dashboard server',
    stemLogContext(
      component: 'dashboard',
      subsystem: 'server',
      fields: {
        'host': options.host,
        'port': options.port,
        'basePath': dashboardUrlPath,
      },
    ),
  );

  try {
    await engine.serve(
      host: options.host,
      port: options.port,
      echo: options.echoRoutes,
    );
    await _waitForShutdownSignal();
  } finally {
    await engine.close();
    if (stateOwner) {
      await dashboardState.dispose();
    }
    if (serviceOwner) {
      await dashboardService.close();
    }
  }
}

Future<void> _waitForShutdownSignal() async {
  final completer = Completer<void>();
  final subscriptions = <StreamSubscription<ProcessSignal>>[];

  void complete(ProcessSignal signal) {
    stemLogger.info(
      'Shutdown signal received',
      stemLogContext(
        component: 'dashboard',
        subsystem: 'server',
        fields: {'signal': signal.toString()},
      ),
    );
    if (!completer.isCompleted) {
      completer.complete();
    }
  }

  void watch(ProcessSignal signal) {
    subscriptions.add(signal.watch().listen(complete));
  }

  watch(ProcessSignal.sigint);
  if (!Platform.isWindows) {
    watch(ProcessSignal.sigterm);
  }

  try {
    await completer.future;
  } finally {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }
}

/// Constructs the dashboard engine with routes and Turbo streaming.
Engine buildDashboardEngine({
  required DashboardDataSource service,
  required DashboardState state,
  String basePath = '',
}) {
  final engine = Engine();
  mountDashboard(
    engine: engine,
    service: service,
    state: state,
    options: DashboardMountOptions(basePath: basePath),
  );
  return engine;
}

/// Mounts dashboard routes and websocket streams into an existing [engine].
void mountDashboard({
  required Engine engine,
  required DashboardDataSource service,
  required DashboardState state,
  DashboardMountOptions options = const DashboardMountOptions(),
}) {
  final resolvedBasePath = normalizeDashboardBasePath(options.basePath);
  registerDashboardRoutes(
    engine,
    service,
    state,
    basePath: resolvedBasePath,
  );
  final streamPath = dashboardRoute(resolvedBasePath, '/dash/streams');
  engine.ws(
    streamPath,
    TurboStreamSocketHandler(
      hub: state.hub,
      topicResolver: (context) =>
          context.initialContext.uri.queryParametersAll['topic'] ??
          const ['stem-dashboard:events'],
    ),
  );
}

/// Registers the dashboard HTTP routes on [engine].
void registerDashboardRoutes(
  Engine engine,
  DashboardDataSource service,
  DashboardState state, {
  String basePath = '',
}) {
  engine
    ..get(
      dashboardRoute(basePath, '/'),
      (ctx) => _renderPage(
        ctx,
        DashboardPage.overview,
        service,
        state,
        basePath: basePath,
      ),
    )
    ..get(
      dashboardRoute(basePath, '/tasks'),
      (ctx) => _renderPage(
        ctx,
        DashboardPage.tasks,
        service,
        state,
        basePath: basePath,
      ),
    )
    ..get(
      dashboardRoute(basePath, '/tasks/detail'),
      (ctx) => _renderPage(
        ctx,
        DashboardPage.taskDetail,
        service,
        state,
        basePath: basePath,
      ),
    )
    ..get(
      dashboardRoute(basePath, '/tasks/inline'),
      (ctx) => _renderTaskInline(ctx, service, basePath: basePath),
    )
    ..get(
      dashboardRoute(basePath, '/failures'),
      (ctx) => _renderPage(
        ctx,
        DashboardPage.failures,
        service,
        state,
        basePath: basePath,
      ),
    )
    ..get(
      dashboardRoute(basePath, '/search'),
      (ctx) => _renderPage(
        ctx,
        DashboardPage.search,
        service,
        state,
        basePath: basePath,
      ),
    )
    ..get(
      dashboardRoute(basePath, '/audit'),
      (ctx) => _renderPage(
        ctx,
        DashboardPage.audit,
        service,
        state,
        basePath: basePath,
      ),
    )
    ..get(
      dashboardRoute(basePath, '/events'),
      (ctx) => _renderPage(
        ctx,
        DashboardPage.events,
        service,
        state,
        basePath: basePath,
      ),
    )
    ..get(
      dashboardRoute(basePath, '/namespaces'),
      (ctx) => _renderPage(
        ctx,
        DashboardPage.namespaces,
        service,
        state,
        basePath: basePath,
      ),
    )
    ..get(
      dashboardRoute(basePath, '/workflows'),
      (ctx) => _renderPage(
        ctx,
        DashboardPage.workflows,
        service,
        state,
        basePath: basePath,
      ),
    )
    ..get(
      dashboardRoute(basePath, '/jobs'),
      (ctx) => _renderPage(
        ctx,
        DashboardPage.jobs,
        service,
        state,
        basePath: basePath,
      ),
    )
    ..get(
      dashboardRoute(basePath, '/workers'),
      (ctx) => _renderPage(
        ctx,
        DashboardPage.workers,
        service,
        state,
        basePath: basePath,
      ),
    )
    ..get(
      dashboardRoute(basePath, '/partials/overview'),
      (ctx) => _renderOverviewPartials(ctx, service, state, basePath: basePath),
    )
    ..post(
      dashboardRoute(basePath, '/tasks/enqueue'),
      (ctx) => _enqueueTask(ctx, service, state, basePath: basePath),
    )
    ..post(
      dashboardRoute(basePath, '/tasks/action'),
      (ctx) => _taskAction(ctx, service, state, basePath: basePath),
    )
    ..post(
      dashboardRoute(basePath, '/workers/control'),
      (ctx) => _controlWorkers(ctx, service, state, basePath: basePath),
    )
    ..post(
      dashboardRoute(basePath, '/queues/replay'),
      (ctx) => _replayDeadLetters(ctx, service, state, basePath: basePath),
    );
}

Future<Response> _renderOverviewPartials(
  EngineContext ctx,
  DashboardDataSource service,
  DashboardState state, {
  required String basePath,
}) async {
  try {
    final queues = await service.fetchQueueSummaries();
    final workers = await service.fetchWorkerStatuses();
    final taskStatuses = await service.fetchTaskStatuses(limit: 300);
    final sections = buildOverviewSections(
      queues,
      workers,
      state.throughput,
      taskStatuses,
      defaultNamespace: _resolveDefaultNamespace(workers, taskStatuses),
    );

    final updates = [
      turboStreamReplace(
        target: 'overview-metrics',
        html: prefixDashboardUrlAttributes(sections.metrics, basePath),
      ),
      turboStreamReplace(
        target: 'overview-namespaces',
        html: prefixDashboardUrlAttributes(sections.namespaces, basePath),
      ),
      turboStreamReplace(
        target: 'overview-queue-table',
        html: prefixDashboardUrlAttributes(sections.topQueues, basePath),
      ),
      turboStreamReplace(
        target: 'overview-workflows',
        html: prefixDashboardUrlAttributes(sections.workflows, basePath),
      ),
      turboStreamReplace(
        target: 'overview-jobs',
        html: prefixDashboardUrlAttributes(sections.jobs, basePath),
      ),
      turboStreamReplace(
        target: 'overview-latency-table',
        html: prefixDashboardUrlAttributes(sections.latency, basePath),
      ),
      turboStreamReplace(
        target: 'overview-recent-tasks',
        html: prefixDashboardUrlAttributes(sections.recentTasks, basePath),
      ),
    ].join('\n');

    return ctx.turboStream(updates);
  } on Object catch (error, stack) {
    stemLogger.error(
      'Failed to render overview partials',
      stemLogContext(
        component: 'dashboard',
        subsystem: 'server',
        fields: {
          'error': error.toString(),
          'stack': stack.toString(),
        },
      ),
    );
    return ctx.turboHtml(
      '<div class="muted">Failed to refresh overview metrics.</div>',
      statusCode: HttpStatus.internalServerError,
    );
  }
}

Future<Response> _renderPage(
  EngineContext ctx,
  DashboardPage page,
  DashboardDataSource service,
  DashboardState state, {
  required String basePath,
}) async {
  final turbo = ctx.turbo;
  try {
    final needsQueues =
        page == DashboardPage.overview ||
        page == DashboardPage.tasks ||
        page == DashboardPage.workers ||
        page == DashboardPage.search ||
        page == DashboardPage.namespaces;
    final queues = needsQueues
        ? await service.fetchQueueSummaries()
        : const <QueueSummary>[];
    final workers =
        page == DashboardPage.overview ||
            page == DashboardPage.workers ||
            page == DashboardPage.search ||
            page == DashboardPage.namespaces
        ? await service.fetchWorkerStatuses()
        : const <WorkerStatus>[];
    var tasksOptions = page == DashboardPage.tasks
        ? _parseTasksOptions(ctx.uri.queryParameters)
        : const TasksPageOptions();
    final failuresOptions = page == DashboardPage.failures
        ? _parseFailuresOptions(ctx.uri.queryParameters)
        : const FailuresPageOptions();

    final searchOptions = page == DashboardPage.search
        ? _parseSearchOptions(ctx.uri.queryParameters)
        : const SearchPageOptions();
    final namespacesOptions = page == DashboardPage.namespaces
        ? _parseNamespacesOptions(ctx.uri.queryParameters)
        : const NamespacesPageOptions();
    final workflowsOptions = page == DashboardPage.workflows
        ? _parseWorkflowsOptions(ctx.uri.queryParameters)
        : const WorkflowsPageOptions();
    final jobsOptions = page == DashboardPage.jobs
        ? _parseJobsOptions(ctx.uri.queryParameters)
        : const JobsPageOptions();
    final workersOptions = page == DashboardPage.workers
        ? _parseWorkersOptions(ctx.uri.queryParameters)
        : const WorkersPageOptions();

    List<DashboardTaskStatusEntry> taskStatuses;
    if (page == DashboardPage.tasks) {
      final localFilteringNeeded =
          tasksOptions.hasNamespaceFilter ||
          tasksOptions.hasTaskFilter ||
          tasksOptions.hasRunIdFilter;
      if (!localFilteringNeeded) {
        final pageRequest = await service.fetchTaskStatuses(
          state: tasksOptions.stateFilter,
          queue: tasksOptions.filter,
          limit: tasksOptions.pageSize + 1,
          offset: tasksOptions.offset,
        );
        final hasNextPage = pageRequest.length > tasksOptions.pageSize;
        taskStatuses = hasNextPage
            ? pageRequest.take(tasksOptions.pageSize).toList(growable: false)
            : pageRequest;
        tasksOptions = tasksOptions.copyWith(
          hasNextPage: hasNextPage,
          hasPreviousPage: tasksOptions.page > 1,
        );
      } else {
        final source = tasksOptions.hasRunIdFilter
            ? await service.fetchTaskStatusesForRun(
                tasksOptions.runId!,
                limit: 1000,
              )
            : await service.fetchTaskStatuses(
                state: tasksOptions.stateFilter,
                queue: tasksOptions.filter,
                limit: 1000,
              );
        final filtered = _applyTaskViewFilters(source, tasksOptions);
        final pageItems = filtered
            .skip(tasksOptions.offset)
            .take(tasksOptions.pageSize)
            .toList(growable: false);
        final hasNextPage =
            filtered.length > tasksOptions.offset + pageItems.length;
        taskStatuses = pageItems;
        tasksOptions = tasksOptions.copyWith(
          hasNextPage: hasNextPage,
          hasPreviousPage: tasksOptions.page > 1,
        );
      }
    } else if (page == DashboardPage.failures) {
      taskStatuses = await service.fetchTaskStatuses(
        state: TaskState.failed,
        queue: failuresOptions.queue,
        limit: 300,
      );
    } else if (page == DashboardPage.overview) {
      taskStatuses = await service.fetchTaskStatuses(limit: 300);
    } else if (page == DashboardPage.search) {
      taskStatuses = await service.fetchTaskStatuses(limit: 500);
    } else if (page == DashboardPage.namespaces) {
      taskStatuses = await service.fetchTaskStatuses(limit: 600);
    } else if (page == DashboardPage.workflows) {
      taskStatuses = await service.fetchTaskStatuses(limit: 700);
    } else if (page == DashboardPage.jobs) {
      taskStatuses = await service.fetchTaskStatuses(limit: 700);
    } else {
      taskStatuses = const <DashboardTaskStatusEntry>[];
    }

    final taskDetail = page == DashboardPage.taskDetail
        ? await service.fetchTaskStatus(ctx.uri.queryParameters['id'] ?? '')
        : null;
    final runId = ctx.uri.queryParameters['runId']?.trim().isNotEmpty ?? false
        ? ctx.uri.queryParameters['runId']!.trim()
        : taskDetail?.runId;
    final runTimeline = page == DashboardPage.taskDetail && runId != null
        ? await service.fetchTaskStatusesForRun(runId, limit: 250)
        : const <DashboardTaskStatusEntry>[];
    final workflowRun = page == DashboardPage.taskDetail && runId != null
        ? await service.fetchWorkflowRun(runId)
        : null;
    final workflowSteps = page == DashboardPage.taskDetail && runId != null
        ? await service.fetchWorkflowSteps(runId)
        : const <DashboardWorkflowStepSnapshot>[];

    final content = buildPageContent(
      page: page,
      queues: queues,
      workers: workers,
      taskStatuses: taskStatuses,
      taskDetail: taskDetail,
      runTimeline: runTimeline,
      workflowRun: workflowRun,
      workflowSteps: workflowSteps,
      auditEntries: page == DashboardPage.search || page == DashboardPage.audit
          ? state.auditEntries
          : const <DashboardAuditEntry>[],
      throughput: page == DashboardPage.overview ? state.throughput : null,
      events: page == DashboardPage.events ? state.events : const [],
      defaultNamespace: _resolveDefaultNamespace(workers, taskStatuses),
      tasksOptions: tasksOptions,
      workersOptions: workersOptions,
      failuresOptions: failuresOptions,
      searchOptions: searchOptions,
      namespacesOptions: namespacesOptions,
      workflowsOptions: workflowsOptions,
      jobsOptions: jobsOptions,
    );
    final contentWithBasePath = prefixDashboardUrlAttributes(content, basePath);
    final streamPath = dashboardRoute(basePath, '/dash/streams');

    if (turbo.isFrameRequest) {
      return ctx.turboFrame(renderFrame(page, contentWithBasePath));
    }

    return ctx.turboHtml(
      renderLayout(
        page,
        contentWithBasePath,
        basePath: basePath,
        streamPath: streamPath,
      ),
    );
  } on Object catch (error, stack) {
    stemLogger.error(
      'Failed to render dashboard page',
      stemLogContext(
        component: 'dashboard',
        subsystem: 'server',
        fields: {
          'page': page.name,
          'error': error.toString(),
          'stack': stack.toString(),
        },
      ),
    );
    final errorContent = _renderErrorPanel(error);
    if (turbo.isFrameRequest) {
      return ctx.turboFrame(
        renderFrame(page, prefixDashboardUrlAttributes(errorContent, basePath)),
      );
    }
    return ctx.turboHtml(
      renderLayout(
        page,
        prefixDashboardUrlAttributes(errorContent, basePath),
        basePath: basePath,
      ),
    );
  }
}

String _renderErrorPanel(Object error) {
  return '''
<section class="event-feed">
  <div class="event-item">
    <h3>Unable to load data</h3>
    <p class="muted">
      The dashboard could not reach Stem services. Root cause: $error
    </p>
  </div>
</section>
''';
}

Future<Response> _renderTaskInline(
  EngineContext ctx,
  DashboardDataSource service, {
  required String basePath,
}) async {
  final taskId = (ctx.uri.queryParameters['id'] ?? '').trim();
  final target = _sanitizeDomTarget(ctx.uri.queryParameters['target'] ?? '');
  if (target.isEmpty) {
    return ctx.turboHtml(
      '<div class="muted">Missing inline target.</div>',
      statusCode: HttpStatus.badRequest,
    );
  }

  DashboardTaskStatusEntry? task;
  if (taskId.isNotEmpty) {
    task = await service.fetchTaskStatus(taskId);
  }

  final content = prefixDashboardUrlAttributes(
    buildTaskInlineContent(task),
    basePath,
  );
  final payload =
      '<div id="$target" data-task-inline-shell="loaded">$content</div>';
  return ctx.turboStream(turboStreamReplace(target: target, html: payload));
}

String _sanitizeDomTarget(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  final validPattern = RegExp(r'^[A-Za-z][A-Za-z0-9:_-]*$');
  return validPattern.hasMatch(trimmed) ? trimmed : '';
}

Future<Response> _enqueueTask(
  EngineContext ctx,
  DashboardDataSource service,
  DashboardState state, {
  required String basePath,
}) async {
  final tasksPath = dashboardRoute(basePath, '/tasks');
  try {
    final queue = (await ctx.postForm('queue')).trim();
    final task = (await ctx.postForm('task')).trim();
    if (queue.isEmpty || task.isEmpty) {
      state.recordAudit(
        kind: 'action',
        action: 'task.enqueue',
        status: 'error',
        actor: 'dashboard',
        summary: 'Task enqueue rejected: queue/task missing.',
      );
      return ctx.turboSeeOther('$tasksPath?error=missing-fields');
    }

    final payloadText = (await ctx.postForm('payload')).trim();
    var args = const <String, Object?>{};
    if (payloadText.isNotEmpty) {
      try {
        final decoded = jsonDecode(payloadText);
        if (decoded is Map<String, dynamic>) {
          args = decoded;
        } else {
          state.recordAudit(
            kind: 'action',
            action: 'task.enqueue',
            status: 'error',
            actor: 'dashboard',
            summary: 'Task enqueue rejected: payload not a JSON object.',
          );
          return ctx.turboSeeOther('$tasksPath?error=invalid-payload');
        }
      } on Object {
        state.recordAudit(
          kind: 'action',
          action: 'task.enqueue',
          status: 'error',
          actor: 'dashboard',
          summary: 'Task enqueue rejected: invalid JSON payload.',
        );
        return ctx.turboSeeOther('$tasksPath?error=invalid-payload');
      }
    }

    final priorityInput =
        int.tryParse((await ctx.postForm('priority')).trim()) ?? 0;
    final maxRetriesInput =
        int.tryParse((await ctx.postForm('maxRetries')).trim()) ?? 0;
    final priority = priorityInput.clamp(0, 9);
    final maxRetries = maxRetriesInput < 0 ? 0 : maxRetriesInput;

    await service.enqueueTask(
      EnqueueRequest(
        queue: queue,
        task: task,
        args: args,
        priority: priority,
        maxRetries: maxRetries,
      ),
    );
    state.recordAudit(
      kind: 'action',
      action: 'task.enqueue',
      status: 'ok',
      actor: 'dashboard',
      summary: 'Queued task "$task" on "$queue".',
      metadata: {'queue': queue, 'task': task},
    );
    return ctx.turboSeeOther('$tasksPath?flash=queued');
  } on Object catch (error, stack) {
    stemLogger.error(
      'Dashboard enqueue failed',
      stemLogContext(
        component: 'dashboard',
        subsystem: 'server',
        fields: {
          'error': error.toString(),
          'stack': stack.toString(),
        },
      ),
    );
    state.recordAudit(
      kind: 'action',
      action: 'task.enqueue',
      status: 'error',
      actor: 'dashboard',
      summary: 'Task enqueue failed: $error',
    );
    return ctx.turboSeeOther('$tasksPath?error=enqueue-failed');
  }
}

Future<Response> _taskAction(
  EngineContext ctx,
  DashboardDataSource service,
  DashboardState state, {
  required String basePath,
}) async {
  final redirect = _resolveRedirectPath(
    await ctx.defaultPostForm('redirect', dashboardRoute(basePath, '/tasks')),
    fallbackPath: dashboardRoute(basePath, '/tasks'),
  );
  try {
    final action = (await ctx.postForm('action')).trim().toLowerCase();
    final taskId = (await ctx.postForm('taskId')).trim();
    final queueRaw = (await ctx.defaultPostForm('queue', '')).trim();
    final queue = queueRaw.isEmpty ? null : queueRaw;

    if (taskId.isEmpty) {
      state.recordAudit(
        kind: 'action',
        action: 'task.action',
        status: 'error',
        actor: 'dashboard',
        summary: 'Task action rejected: missing task id.',
      );
      return ctx.turboSeeOther(
        _appendRedirectQuery(redirect, {'error': 'Task ID is required.'}),
      );
    }

    switch (action) {
      case 'cancel':
        final reasonRaw = (await ctx.defaultPostForm(
          'reason',
          'Cancelled from dashboard.',
        )).trim();
        final terminate = _isTruthy(
          (await ctx.defaultPostForm('terminate', 'false')).trim(),
        );
        final revoked = await service.revokeTask(
          taskId,
          terminate: terminate,
          reason: reasonRaw.isEmpty ? null : reasonRaw,
        );
        if (!revoked) {
          state.recordAudit(
            kind: 'action',
            action: 'task.cancel',
            status: 'error',
            actor: 'dashboard',
            summary: 'Failed to revoke task $taskId.',
            metadata: {'taskId': taskId, 'queue': ?queue},
          );
          return ctx.turboSeeOther(
            _appendRedirectQuery(redirect, {
              'error': 'Unable to revoke task $taskId.',
            }),
          );
        }
        state.recordAudit(
          kind: 'action',
          action: 'task.cancel',
          status: 'ok',
          actor: 'dashboard',
          summary: 'Revocation requested for $taskId.',
          metadata: {'taskId': taskId, 'queue': ?queue},
        );
        return ctx.turboSeeOther(
          _appendRedirectQuery(redirect, {
            'flash': 'Revocation requested for task $taskId.',
          }),
        );
      case 'replay':
        final replayed = await service.replayTaskById(taskId, queue: queue);
        if (!replayed) {
          state.recordAudit(
            kind: 'action',
            action: 'task.replay',
            status: 'error',
            actor: 'dashboard',
            summary: 'Task $taskId was not found in dead letters.',
            metadata: {'taskId': taskId, 'queue': ?queue},
          );
          return ctx.turboSeeOther(
            _appendRedirectQuery(redirect, {
              'error': 'Task $taskId was not found in dead letters.',
            }),
          );
        }
        state.recordAudit(
          kind: 'action',
          action: 'task.replay',
          status: 'ok',
          actor: 'dashboard',
          summary: 'Replayed dead-letter task $taskId.',
          metadata: {'taskId': taskId, 'queue': ?queue},
        );
        return ctx.turboSeeOther(
          _appendRedirectQuery(redirect, {
            'flash': 'Replayed dead-letter task $taskId as a new envelope.',
          }),
        );
      default:
        state.recordAudit(
          kind: 'action',
          action: 'task.action',
          status: 'error',
          actor: 'dashboard',
          summary: 'Unsupported task action "$action".',
          metadata: {'taskId': taskId},
        );
        return ctx.turboSeeOther(
          _appendRedirectQuery(redirect, {
            'error': 'Unsupported task action "$action".',
          }),
        );
    }
  } on Object catch (error, stack) {
    stemLogger.error(
      'Dashboard task action failed',
      stemLogContext(
        component: 'dashboard',
        subsystem: 'server',
        fields: {
          'error': error.toString(),
          'stack': stack.toString(),
        },
      ),
    );
    state.recordAudit(
      kind: 'action',
      action: 'task.action',
      status: 'error',
      actor: 'dashboard',
      summary: 'Task action failed: $error',
    );
    return ctx.turboSeeOther(
      _appendRedirectQuery(redirect, {'error': 'Task action failed.'}),
    );
  }
}

TasksPageOptions _parseTasksOptions(Map<String, String> params) {
  final sortKey = switch ((params['sort'] ?? 'queue').toLowerCase()) {
    'pending' => 'pending',
    'inflight' => 'inflight',
    'deadletters' => 'dead',
    'dead' => 'dead',
    _ => 'queue',
  };
  final direction = (params['direction'] ?? 'asc').toLowerCase();
  final descending = direction == 'desc';
  final filterRaw = params['queue']?.trim();
  final filter = filterRaw == null || filterRaw.isEmpty ? null : filterRaw;
  final namespaceRaw = params['namespace']?.trim();
  final namespaceFilter = namespaceRaw == null || namespaceRaw.isEmpty
      ? null
      : namespaceRaw;
  final taskRaw = params['task']?.trim();
  final taskFilter = taskRaw == null || taskRaw.isEmpty ? null : taskRaw;
  final runRaw = params['runId']?.trim();
  final runId = runRaw == null || runRaw.isEmpty ? null : runRaw;
  final stateRaw = params['state']?.trim().toLowerCase();
  final stateFilter = switch (stateRaw) {
    'queued' => TaskState.queued,
    'running' => TaskState.running,
    'succeeded' => TaskState.succeeded,
    'failed' => TaskState.failed,
    'retried' => TaskState.retried,
    'cancelled' => TaskState.cancelled,
    _ => null,
  };
  final pageRaw = int.tryParse((params['page'] ?? '1').trim());
  final page = pageRaw == null || pageRaw < 1 ? 1 : pageRaw;
  final pageSizeRaw = int.tryParse((params['pageSize'] ?? '25').trim());
  final pageSize = (pageSizeRaw ?? 25).clamp(25, 200);
  return TasksPageOptions(
    sortKey: sortKey,
    descending: descending,
    filter: filter,
    namespaceFilter: namespaceFilter,
    taskFilter: taskFilter,
    runId: runId,
    stateFilter: stateFilter,
    page: page,
    pageSize: pageSize,
    flashKey: params['flash']?.trim().isEmpty ?? false ? null : params['flash'],
    errorKey: params['error']?.trim().isEmpty ?? false ? null : params['error'],
  );
}

WorkersPageOptions _parseWorkersOptions(Map<String, String> params) {
  final flash = params['flash']?.trim();
  final error = params['error']?.trim();
  final target = params['scope']?.trim();
  final namespace = params['namespace']?.trim();
  return WorkersPageOptions(
    flashMessage: flash?.isNotEmpty ?? false ? flash : null,
    errorMessage: error?.isNotEmpty ?? false ? error : null,
    scope: target?.isNotEmpty ?? false ? target : null,
    namespaceFilter: namespace?.isNotEmpty ?? false ? namespace : null,
  );
}

FailuresPageOptions _parseFailuresOptions(Map<String, String> params) {
  final queue = params['queue']?.trim();
  final flash = params['flash']?.trim();
  final error = params['error']?.trim();
  return FailuresPageOptions(
    queue: queue?.isEmpty ?? true ? null : queue,
    flashMessage: flash?.isEmpty ?? true ? null : flash,
    errorMessage: error?.isEmpty ?? true ? null : error,
  );
}

SearchPageOptions _parseSearchOptions(Map<String, String> params) {
  final query = params['q']?.trim();
  final scopeRaw = (params['scope'] ?? 'all').trim().toLowerCase();
  final scope = switch (scopeRaw) {
    'tasks' => 'tasks',
    'workers' => 'workers',
    'queues' => 'queues',
    'audit' => 'audit',
    _ => 'all',
  };
  return SearchPageOptions(
    query: query?.isEmpty ?? true ? null : query,
    scope: scope,
  );
}

NamespacesPageOptions _parseNamespacesOptions(Map<String, String> params) {
  final namespace = params['namespace']?.trim();
  return NamespacesPageOptions(
    namespace: namespace?.isNotEmpty ?? false ? namespace : null,
  );
}

WorkflowsPageOptions _parseWorkflowsOptions(Map<String, String> params) {
  final workflow = params['workflow']?.trim();
  final runId = params['runId']?.trim();
  return WorkflowsPageOptions(
    workflow: workflow?.isNotEmpty ?? false ? workflow : null,
    runId: runId?.isNotEmpty ?? false ? runId : null,
  );
}

JobsPageOptions _parseJobsOptions(Map<String, String> params) {
  final task = params['task']?.trim();
  final queue = params['queue']?.trim();
  return JobsPageOptions(
    task: task?.isNotEmpty ?? false ? task : null,
    queue: queue?.isNotEmpty ?? false ? queue : null,
  );
}

List<DashboardTaskStatusEntry> _applyTaskViewFilters(
  List<DashboardTaskStatusEntry> tasks,
  TasksPageOptions options,
) {
  final queueFilter = options.filter?.toLowerCase();
  final namespaceFilter = options.namespaceFilter?.toLowerCase();
  final taskFilter = options.taskFilter?.toLowerCase();
  final runFilter = options.runId?.toLowerCase();
  return tasks.where((entry) {
    if (options.hasFilter) {
      final queue = entry.queue.toLowerCase();
      if (!(queueFilter != null && queue.contains(queueFilter))) {
        return false;
      }
    }
    if (options.hasNamespaceFilter &&
        entry.namespace.toLowerCase() != namespaceFilter) {
      return false;
    }
    if (options.hasTaskFilter) {
      final name = entry.taskName.toLowerCase();
      if (!(taskFilter != null && name.contains(taskFilter))) {
        return false;
      }
    }
    if (options.hasRunIdFilter) {
      final runId = entry.runId?.toLowerCase() ?? '';
      if (!(runFilter != null && runId.contains(runFilter))) {
        return false;
      }
    }
    if (options.hasStateFilter && entry.state != options.stateFilter) {
      return false;
    }
    return true;
  }).toList(growable: false);
}

String _resolveDefaultNamespace(
  List<WorkerStatus> workers,
  List<DashboardTaskStatusEntry> tasks,
) {
  for (final worker in workers) {
    final value = worker.namespace.trim();
    if (value.isNotEmpty) return value;
  }
  for (final task in tasks) {
    final value = task.namespace.trim();
    if (value.isNotEmpty) return value;
  }
  return 'stem';
}

Future<Response> _controlWorkers(
  EngineContext ctx,
  DashboardDataSource service,
  DashboardState state, {
  required String basePath,
}) async {
  final namespaceFilter = (await ctx.defaultPostForm('namespace', '')).trim();
  final workersPath = namespaceFilter.isEmpty
      ? dashboardRoute(basePath, '/workers')
      : _appendRedirectQuery(
          dashboardRoute(basePath, '/workers'),
          {'namespace': namespaceFilter},
        );
  try {
    final rawAction = (await ctx.postForm('action')).trim().toLowerCase();
    if (rawAction.isEmpty) {
      state.recordAudit(
        kind: 'action',
        action: 'worker.control',
        status: 'error',
        actor: 'dashboard',
        summary: 'Control action missing.',
      );
      return ctx.turboSeeOther(
        '$workersPath?error=${Uri.encodeComponent('Control action missing.')}',
      );
    }

    final workerField = (await ctx.postForm('worker')).trim();
    final targets = workerField
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final broadcast =
        targets.isEmpty ||
        targets.any((value) => value == '*' || value.toLowerCase() == 'all');
    final resolvedTargets = broadcast ? const <String>[] : targets;

    final timeoutRaw = (await ctx.defaultPostForm('timeoutMs', '')).trim();
    final timeoutMs = int.tryParse(timeoutRaw);
    final timeout = timeoutMs != null && timeoutMs > 0
        ? Duration(milliseconds: timeoutMs)
        : const Duration(seconds: 5);

    final commandType = switch (rawAction) {
      'ping' => 'ping',
      'pause' => 'shutdown',
      'shutdown' => 'shutdown',
      _ => null,
    };

    if (commandType == null) {
      state.recordAudit(
        kind: 'action',
        action: 'worker.control',
        status: 'error',
        actor: 'dashboard',
        summary: 'Unsupported control action "$rawAction".',
      );
      final encodedError = Uri.encodeComponent(
        'Unsupported control action "$rawAction".',
      );
      return ctx.turboSeeOther('$workersPath?error=$encodedError');
    }

    final payload = <String, Object?>{};
    if (rawAction == 'pause') {
      payload['mode'] = 'soft';
    } else if (rawAction == 'shutdown') {
      payload['mode'] = 'hard';
    }

    final requestId = generateEnvelopeId();
    final command = ControlCommandMessage(
      requestId: requestId,
      type: commandType,
      targets: resolvedTargets,
      payload: payload,
      timeoutMs: timeout.inMilliseconds,
    );

    final replies = await service.sendControlCommand(command, timeout: timeout);
    final okReplies = replies.where((reply) => reply.status == 'ok').length;
    final errorReplies = replies.length - okReplies;
    final scope = broadcast
        ? 'cluster'
        : resolvedTargets.length == 1
        ? resolvedTargets.first
        : '${resolvedTargets.length} workers';

    final label = switch (rawAction) {
      'ping' => 'Ping',
      'pause' => 'Pause',
      'shutdown' => 'Shutdown',
      _ => rawAction,
    };

    if (errorReplies > 0) {
      final primaryError = replies
          .firstWhere((reply) => reply.status != 'ok')
          .error?['message'];
      final message = StringBuffer()
        ..write(
          '$label command reached $scope but $errorReplies replies '
          'reported errors.',
        );
      if (primaryError is String && primaryError.isNotEmpty) {
        message.write(' Example: $primaryError');
      }
      state.recordAudit(
        kind: 'action',
        action: 'worker.control.$rawAction',
        status: 'error',
        actor: 'dashboard',
        summary:
            '$label command reached $scope with $errorReplies error replies.',
      );
      final encodedMessage = Uri.encodeComponent(message.toString());
      final encodedScope = Uri.encodeComponent(scope);
      return ctx.turboSeeOther(
        '$workersPath?error=$encodedMessage&scope=$encodedScope',
      );
    }

    final ackLabel = okReplies == 1 ? 'reply' : 'replies';
    final message = replies.isEmpty
        ? '$label command sent to $scope.'
        : '$label command acknowledged by $okReplies $ackLabel from $scope.';
    state.recordAudit(
      kind: 'action',
      action: 'worker.control.$rawAction',
      status: 'ok',
      actor: 'dashboard',
      summary: message,
    );
    final encodedMessage = Uri.encodeComponent(message);
    final encodedScope = Uri.encodeComponent(scope);
    return ctx.turboSeeOther(
      '$workersPath?flash=$encodedMessage&scope=$encodedScope',
    );
  } on Object catch (error, stack) {
    stemLogger.error(
      'Dashboard control command failed',
      stemLogContext(
        component: 'dashboard',
        subsystem: 'server',
        fields: {
          'error': error.toString(),
          'stack': stack.toString(),
        },
      ),
    );
    state.recordAudit(
      kind: 'action',
      action: 'worker.control',
      status: 'error',
      actor: 'dashboard',
      summary: 'Control command failed: $error',
    );
    return ctx.turboSeeOther(
      '$workersPath?error=${Uri.encodeComponent('Control command failed.')}',
    );
  }
}

Future<Response> _replayDeadLetters(
  EngineContext ctx,
  DashboardDataSource service,
  DashboardState state, {
  required String basePath,
}) async {
  final redirect = _resolveRedirectPath(
    await ctx.defaultPostForm('redirect', dashboardRoute(basePath, '/workers')),
    fallbackPath: dashboardRoute(basePath, '/workers'),
  );
  try {
    final queue = (await ctx.postForm('queue')).trim();
    if (queue.isEmpty) {
      state.recordAudit(
        kind: 'action',
        action: 'queue.replay',
        status: 'error',
        actor: 'dashboard',
        summary: 'Replay rejected: missing queue name.',
      );
      return ctx.turboSeeOther(
        _appendRedirectQuery(redirect, {
          'error': 'Queue name is required for replay.',
        }),
      );
    }
    final limitInput = (await ctx.defaultPostForm('limit', '50')).trim();
    final limit = int.tryParse(limitInput)?.clamp(1, 500) ?? 50;
    final dryRunFlag = (await ctx.defaultPostForm(
      'dryRun',
      'false',
    )).toLowerCase();
    final dryRun =
        dryRunFlag == 'true' || dryRunFlag == '1' || dryRunFlag == 'yes';

    final result = await service.replayDeadLetters(
      queue,
      limit: limit,
      dryRun: dryRun,
    );

    final scope = queue;
    if (result.entries.isEmpty) {
      final message = dryRun
          ? 'Dry run replay found no dead letters for "$queue".'
          : 'No dead letters replayed for "$queue".';
      state.recordAudit(
        kind: 'action',
        action: 'queue.replay',
        status: 'ok',
        actor: 'dashboard',
        summary: message,
        metadata: {'queue': queue, 'dryRun': dryRun},
      );
      return ctx.turboSeeOther(
        _appendRedirectQuery(redirect, {
          'flash': message,
          'scope': scope,
          if (redirect == '/failures') 'queue': queue,
        }),
      );
    }

    final entryCount = result.entries.length;
    final entrySuffix = entryCount == 1 ? '' : 's';
    final message = dryRun
        ? 'Dry run replay would consider $entryCount dead letter$entrySuffix '
              'for "$queue".'
        : 'Replayed $entryCount dead letter$entrySuffix for "$queue".';
    state.recordAudit(
      kind: 'action',
      action: 'queue.replay',
      status: 'ok',
      actor: 'dashboard',
      summary: message,
      metadata: {'queue': queue, 'entries': entryCount, 'dryRun': dryRun},
    );
    return ctx.turboSeeOther(
      _appendRedirectQuery(redirect, {
        'flash': message,
        'scope': scope,
        if (redirect == '/failures') 'queue': queue,
      }),
    );
  } on Object catch (error, stack) {
    stemLogger.error(
      'Dashboard dead-letter replay failed',
      stemLogContext(
        component: 'dashboard',
        subsystem: 'server',
        fields: {
          'error': error.toString(),
          'stack': stack.toString(),
        },
      ),
    );
    state.recordAudit(
      kind: 'action',
      action: 'queue.replay',
      status: 'error',
      actor: 'dashboard',
      summary: 'Dead-letter replay failed: $error',
    );
    return ctx.turboSeeOther(
      _appendRedirectQuery(redirect, {
        'error': 'Failed to replay dead letters.',
      }),
    );
  }
}

String _resolveRedirectPath(
  String? raw, {
  required String fallbackPath,
}) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty || !value.startsWith('/')) {
    return fallbackPath;
  }
  final uri = Uri.tryParse(value);
  if (uri == null || uri.host.isNotEmpty || uri.scheme.isNotEmpty) {
    return fallbackPath;
  }
  return value;
}

String _appendRedirectQuery(
  String path,
  Map<String, String> params,
) {
  final uri = Uri.parse(path);
  final merged = Map<String, String>.from(uri.queryParameters);
  for (final entry in params.entries) {
    if (entry.value.trim().isEmpty) continue;
    merged[entry.key] = entry.value;
  }
  final query = merged.entries
      .map(
        (entry) {
          final key = Uri.encodeQueryComponent(entry.key);
          final value = Uri.encodeQueryComponent(entry.value);
          return '$key=$value';
        },
      )
      .join('&');
  return query.isEmpty ? uri.path : '${uri.path}?$query';
}

bool _isTruthy(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized == 'true' || normalized == '1' || normalized == 'yes';
}
