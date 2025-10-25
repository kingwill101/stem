import 'dart:convert';
import 'dart:io';

import 'package:routed/routed.dart';
import 'package:routed_hotwire/routed_hotwire.dart';

import 'config/config.dart';
import 'services/models.dart';
import 'services/stem_service.dart';
import 'state/dashboard_state.dart';
import 'ui/content.dart';
import 'ui/layout.dart';

/// Options controlling how the dashboard server binds to the network.
class DashboardServerOptions {
  const DashboardServerOptions({
    this.host = '127.0.0.1',
    this.port = 3080,
    this.echoRoutes = false,
  });

  final String host;
  final int port;
  final bool echoRoutes;

  DashboardServerOptions copyWith({String? host, int? port, bool? echoRoutes}) {
    return DashboardServerOptions(
      host: host ?? this.host,
      port: port ?? this.port,
      echoRoutes: echoRoutes ?? this.echoRoutes,
    );
  }
}

/// Boot the Stem dashboard HTTP server.
Future<void> runDashboardServer({
  DashboardServerOptions options = const DashboardServerOptions(),
  DashboardConfig? config,
  DashboardDataSource? service,
  DashboardState? state,
}) async {
  final resolvedConfig = config ?? DashboardConfig.load();
  final serviceOwner = service == null;
  final dashboardService =
      service ?? await StemDashboardService.connect(resolvedConfig);
  final stateOwner = state == null;
  final dashboardState = state ?? DashboardState(service: dashboardService);

  if (stateOwner) {
    await dashboardState.start();
  }
  final engine = buildDashboardEngine(
    service: dashboardService,
    state: dashboardState,
  );

  stdout.writeln(
    '[stem-dashboard] Starting on http://${options.host}:${options.port}',
  );

  try {
    await engine.serve(
      host: options.host,
      port: options.port,
      echo: options.echoRoutes,
    );
  } finally {
    if (stateOwner) {
      await dashboardState.dispose();
    }
    if (serviceOwner) {
      await dashboardService.close();
    }
  }
}

/// Construct the dashboard engine with routes and Turbo streaming.
Engine buildDashboardEngine({
  required DashboardDataSource service,
  required DashboardState state,
}) {
  final engine = Engine();
  _registerRoutes(engine, service, state);
  engine.ws(
    '/dash/streams',
    TurboStreamSocketHandler(
      hub: state.hub,
      topicResolver: (context) =>
          context.initialContext.request.uri.queryParametersAll['topic'] ??
          const ['stem-dashboard:events'],
    ),
  );
  return engine;
}

void _registerRoutes(
  Engine engine,
  DashboardDataSource service,
  DashboardState state,
) {
  engine.get(
    '/',
    (ctx) => _renderPage(ctx, DashboardPage.overview, service, state),
  );
  engine.get(
    '/tasks',
    (ctx) => _renderPage(ctx, DashboardPage.tasks, service, state),
  );
  engine.get(
    '/events',
    (ctx) => _renderPage(ctx, DashboardPage.events, service, state),
  );
  engine.get(
    '/workers',
    (ctx) => _renderPage(ctx, DashboardPage.workers, service, state),
  );
  engine.post('/tasks/enqueue', (ctx) => _enqueueTask(ctx, service));
}

Future<Response> _renderPage(
  EngineContext ctx,
  DashboardPage page,
  DashboardDataSource service,
  DashboardState state,
) async {
  final turbo = ctx.turbo;
  try {
    final queues = page == DashboardPage.overview || page == DashboardPage.tasks
        ? await service.fetchQueueSummaries()
        : const <QueueSummary>[];
    final workers =
        page == DashboardPage.overview || page == DashboardPage.workers
        ? await service.fetchWorkerStatuses()
        : const <WorkerStatus>[];
    final tasksOptions = page == DashboardPage.tasks
        ? _parseTasksOptions(ctx.request.uri.queryParameters)
        : const TasksPageOptions();

    final content = buildPageContent(
      page: page,
      queues: queues,
      workers: workers,
      events: page == DashboardPage.events ? state.events : const [],
      tasksOptions: tasksOptions,
    );

    if (turbo.isFrameRequest) {
      return ctx.turboFrame(renderFrame(page, content));
    }

    return ctx.turboHtml(renderLayout(page, content));
  } catch (error, stack) {
    stderr.writeln(
      '[stem-dashboard] Failed to render ${page.name} page: $error',
    );
    stderr.writeln(stack);
    final errorContent = _renderErrorPanel(error);
    if (turbo.isFrameRequest) {
      return ctx.turboFrame(renderFrame(page, errorContent));
    }
    return ctx.turboHtml(renderLayout(page, errorContent));
  }
}

String _renderErrorPanel(Object error) {
  return '''
<section class="event-feed">
  <div class="event-item">
    <h3>Unable to load data</h3>
    <p class="muted">The dashboard could not reach Stem services. Root cause: $error</p>
  </div>
</section>
''';
}

Future<Response> _enqueueTask(
  EngineContext ctx,
  DashboardDataSource service,
) async {
  try {
    final queue = (await ctx.postForm('queue')).trim();
    final task = (await ctx.postForm('task')).trim();
    if (queue.isEmpty || task.isEmpty) {
      return ctx.turboSeeOther('/tasks?error=missing-fields');
    }

    final payloadText = (await ctx.postForm('payload')).trim();
    Map<String, Object?> args = const {};
    if (payloadText.isNotEmpty) {
      try {
        final decoded = jsonDecode(payloadText);
        if (decoded is Map<String, dynamic>) {
          args = decoded;
        } else {
          return ctx.turboSeeOther('/tasks?error=invalid-payload');
        }
      } catch (_) {
        return ctx.turboSeeOther('/tasks?error=invalid-payload');
      }
    }

    final priorityInput =
        int.tryParse((await ctx.postForm('priority')).trim()) ?? 0;
    final maxRetriesInput =
        int.tryParse((await ctx.postForm('maxRetries')).trim()) ?? 0;
    final priority = (priorityInput.clamp(0, 9)).toInt();
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
    return ctx.turboSeeOther('/tasks?flash=queued');
  } catch (error, stack) {
    stderr.writeln('[stem-dashboard] enqueue failed: $error');
    stderr.writeln(stack);
    return ctx.turboSeeOther('/tasks?error=enqueue-failed');
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
  return TasksPageOptions(
    sortKey: sortKey,
    descending: descending,
    filter: filter,
    flashKey: params['flash']?.trim().isEmpty == true ? null : params['flash'],
    errorKey: params['error']?.trim().isEmpty == true ? null : params['error'],
  );
}
