import 'package:stem_dashboard/src/ui/paths.dart';

/// Pages supported by the dashboard UI.
enum DashboardPage {
  /// Overview landing page.
  overview('/'),

  /// Task and queue details page.
  tasks('/tasks'),

  /// Detailed view for a single task / workflow run.
  taskDetail('/tasks/detail'),

  /// Failure diagnostics and grouped retry controls.
  failures('/failures'),

  /// Global search and saved operational views.
  search('/search'),

  /// Audit log for actions and alert deliveries.
  audit('/audit'),

  /// Event feed page.
  events('/events'),

  /// Namespace-centric operational summary.
  namespaces('/namespaces'),

  /// Workflow run-centric operational summary.
  workflows('/workflows'),

  /// Task family/job-centric operational summary.
  jobs('/jobs'),

  /// Worker status page.
  workers('/workers');

  /// Creates a dashboard page entry with a path.
  const DashboardPage(this.path);

  /// Route path for this page.
  final String path;

  /// Display label used in navigation.
  String get label {
    switch (this) {
      case DashboardPage.overview:
        return 'Overview';
      case DashboardPage.tasks:
        return 'Tasks';
      case DashboardPage.taskDetail:
        return 'Task Detail';
      case DashboardPage.failures:
        return 'Failures';
      case DashboardPage.search:
        return 'Search';
      case DashboardPage.audit:
        return 'Audit';
      case DashboardPage.events:
        return 'Events';
      case DashboardPage.namespaces:
        return 'Namespaces';
      case DashboardPage.workflows:
        return 'Workflows';
      case DashboardPage.jobs:
        return 'Jobs';
      case DashboardPage.workers:
        return 'Workers';
    }
  }

  /// Whether this page should appear in sidebar navigation.
  bool get showInNav => this != DashboardPage.taskDetail;

  /// Browser title for this page.
  String get title => 'Stem Dashboard · $label';
}

/// Renders the full HTML layout for a dashboard page.
String renderLayout(
  DashboardPage page,
  String content, {
  String basePath = '',
  String? streamPath,
}) {
  final resolvedBasePath = normalizeDashboardBasePath(basePath);
  final resolvedStreamPath =
      streamPath ?? dashboardRoute(basePath, '/dash/streams');
  return '''
<!doctype html>
<html lang="en" class="dark">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${page.title}</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Manrope:wght@400;500;600;700&display=swap" rel="stylesheet">
  <script src="https://cdn.tailwindcss.com?plugins=forms,typography" data-turbo-track="reload"></script>
  <script>
    tailwind.config = {
      darkMode: 'class',
      theme: {
        extend: {
          colors: {
            stem: {
              950: '#0f172a',
              900: '#111827',
              800: '#1e293b',
              500: '#38bdf8',
              400: '#7dd3fc',
            },
          },
          fontFamily: {
            sans: ['Manrope', 'system-ui', 'sans-serif'],
          },
        },
      },
    };
  </script>
  <script src="https://cdn.jsdelivr.net/npm/@hotwired/turbo@8/dist/turbo.es2017-umd.js" data-turbo-track="reload"></script>
  <style>
    *,
    *::before,
    *::after {
      box-sizing: border-box;
    }

    html {
      color-scheme: dark;
    }

    body {
      margin: 0;
      font-family: "Manrope", system-ui, sans-serif;
      color: #e2e8f0;
      background: #0f172a;
    }

    a {
      color: inherit;
      text-decoration: none;
    }

    h1 {
      margin: 0;
      font-size: 1.875rem;
      font-weight: 600;
      letter-spacing: -0.02em;
    }

    table {
      width: 100%;
      border-collapse: collapse;
    }

    thead {
      background: rgba(30, 41, 59, 0.85);
      color: #94a3b8;
      font-size: 0.75rem;
      text-transform: uppercase;
      letter-spacing: 0.08em;
    }

    th,
    td {
      padding: 0.875rem 1rem;
      text-align: left;
      vertical-align: top;
    }

    tbody tr {
      border-bottom: 1px solid rgba(148, 163, 184, 0.1);
      transition: background-color 160ms ease;
    }

    tbody tr:last-child {
      border-bottom: none;
    }

    tbody tr:hover {
      background: rgba(30, 64, 175, 0.25);
    }

    turbo-frame#dashboard-content {
      display: block;
      flex: 1;
      position: relative;
      min-height: 14rem;
      transition: opacity 140ms ease;
    }

    turbo-frame#dashboard-content[data-nav-loading='true'][busy] {
      opacity: 0.82;
    }

    turbo-frame#dashboard-content[data-nav-loading='true'][busy]::before {
      content: 'Updating view';
      position: absolute;
      top: 0.75rem;
      right: 1rem;
      z-index: 31;
      pointer-events: none;
      border-radius: 999px;
      border: 1px solid rgba(125, 211, 252, 0.36);
      background: rgba(15, 23, 42, 0.92);
      color: #bae6fd;
      padding: 0.25rem 0.6rem;
      font-size: 0.7rem;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.06em;
    }

    turbo-frame#dashboard-content[data-nav-loading='true'][busy]::after {
      content: '';
      position: absolute;
      inset: 0.75rem;
      z-index: 30;
      pointer-events: none;
      border-radius: 0.9rem;
      border: 1px solid rgba(125, 211, 252, 0.14);
      background:
        linear-gradient(
          90deg,
          rgba(56, 189, 248, 0) 0%,
          rgba(125, 211, 252, 0.2) 45%,
          rgba(56, 189, 248, 0) 100%
        ),
        repeating-linear-gradient(
          to bottom,
          rgba(148, 163, 184, 0.12) 0 14px,
          rgba(15, 23, 42, 0) 14px 34px
        ),
        linear-gradient(
          180deg,
          rgba(15, 23, 42, 0.88) 0%,
          rgba(15, 23, 42, 0.78) 100%
        );
      background-size: 220% 100%, 100% 100%, 100% 100%;
      animation: dashboardSkeletonShimmer 1.2s linear infinite;
    }

    @keyframes dashboardSkeletonShimmer {
      from {
        background-position: -180% 0, 0 0, 0 0;
      }
      to {
        background-position: 180% 0, 0 0, 0 0;
      }
    }

    .app-shell {
      position: relative;
      display: flex;
      min-height: 100vh;
      gap: 1rem;
      padding: 0.75rem;
    }

    .app-shell::before {
      content: '';
      position: fixed;
      inset: 0;
      pointer-events: none;
      background:
        radial-gradient(900px 420px at 12% -8%, rgba(56, 189, 248, 0.18), transparent 70%),
        radial-gradient(760px 380px at 102% 18%, rgba(14, 116, 144, 0.16), transparent 64%),
        linear-gradient(180deg, #0b1220 0%, #0f172a 48%, #0c1324 100%);
    }

    .app-shell > * {
      position: relative;
      z-index: 10;
    }

    .sidebar-backdrop {
      position: fixed;
      inset: 0;
      z-index: 30;
      background: rgba(15, 23, 42, 0.72);
      backdrop-filter: blur(4px);
      opacity: 0;
      pointer-events: none;
      transition: opacity 200ms ease;
    }

    .sidebar-backdrop[data-open='true'] {
      opacity: 1;
      pointer-events: auto;
    }

    .sidebar {
      position: fixed;
      top: 0.75rem;
      bottom: 0.75rem;
      left: 0.75rem;
      z-index: 40;
      display: flex;
      flex-direction: column;
      gap: 1.5rem;
      width: min(18rem, calc(100vw - 1.5rem));
      transform: translateX(-120%);
      border-radius: 1.5rem;
      border: 1px solid rgba(125, 211, 252, 0.2);
      background: linear-gradient(180deg, rgba(15, 23, 42, 0.95) 0%, rgba(23, 37, 84, 0.9) 52%, rgba(22, 78, 99, 0.8) 100%);
      box-shadow: 0 24px 50px rgba(2, 6, 23, 0.45);
      padding: 1.25rem 1rem;
      transition: transform 300ms ease;
      height: calc(100vh - 1.5rem);
    }

    .sidebar[data-open='true'] {
      transform: translateX(0);
    }

    .sidebar-head {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 0.75rem;
    }

    .sidebar-close,
    .sidebar-toggle {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      width: 2.5rem;
      height: 2.5rem;
      border-radius: 0.75rem;
      border: 1px solid rgba(203, 213, 225, 0.2);
      background: rgba(15, 23, 42, 0.65);
      color: #cbd5e1;
      cursor: pointer;
    }

    .sidebar-close:hover,
    .sidebar-toggle:hover {
      border-color: rgba(125, 211, 252, 0.55);
      color: #bae6fd;
    }

    .brand-panel {
      border-radius: 1rem;
      border: 1px solid rgba(125, 211, 252, 0.25);
      background: rgba(56, 189, 248, 0.1);
      padding: 0.75rem 0.875rem;
      flex: 1;
    }

    .brand {
      font-size: 0.9rem;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.16em;
      color: #e0f2fe;
    }

    .brand-tagline {
      margin: 0.25rem 0 0;
      font-size: 0.75rem;
      color: #94a3b8;
    }

    .sidebar-status {
      margin-top: 0.75rem;
      display: flex;
      align-items: center;
      gap: 0.5rem;
      font-size: 0.72rem;
      letter-spacing: 0.14em;
      text-transform: uppercase;
      color: #bbf7d0;
    }

    .status-dot {
      width: 0.625rem;
      height: 0.625rem;
      border-radius: 999px;
      background: #86efac;
      box-shadow: 0 0 0 5px rgba(16, 185, 129, 0.2);
    }

    nav {
      display: flex;
      flex-direction: column;
      gap: 0.5rem;
      border-radius: 1rem;
      border: 1px solid rgba(203, 213, 225, 0.14);
      background: rgba(15, 23, 42, 0.45);
      padding: 0.5rem;
    }

    .nav-link {
      display: flex;
      align-items: center;
      gap: 0.75rem;
      padding: 0.65rem 0.875rem;
      border-radius: 0.75rem;
      color: rgba(226, 232, 240, 0.82);
      font-weight: 500;
      transition: transform 150ms ease, background-color 150ms ease, color 150ms ease;
    }

    .nav-link::before {
      content: '';
      width: 0.5rem;
      height: 0.5rem;
      border-radius: 999px;
      background: rgba(148, 163, 184, 0.35);
      transition: background-color 150ms ease;
    }

    .nav-link:hover {
      transform: translateX(2px);
      background: rgba(125, 211, 252, 0.12);
      color: #f8fafc;
    }

    .nav-link.active {
      background: linear-gradient(90deg, rgba(125, 211, 252, 0.24), rgba(103, 232, 249, 0.18));
      color: #f8fafc;
    }

    .nav-link.active::before {
      background: #7dd3fc;
    }

    .sidebar-footer {
      margin-top: auto;
      border-radius: 1rem;
      border: 1px solid rgba(203, 213, 225, 0.14);
      background: rgba(15, 23, 42, 0.45);
      padding: 0.75rem 0.875rem;
      font-size: 0.75rem;
      color: rgba(226, 232, 240, 0.7);
      line-height: 1.5;
    }

    .main {
      position: relative;
      display: flex;
      flex: 1;
      flex-direction: column;
      min-width: 0;
      border-radius: 1.5rem;
      border: 1px solid rgba(148, 163, 184, 0.16);
      background: rgba(15, 23, 42, 0.7);
      backdrop-filter: blur(8px);
      box-shadow: 0 24px 50px rgba(2, 6, 23, 0.4);
      padding: 1rem;
    }

    .top-panel {
      margin-bottom: 1.25rem;
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      justify-content: space-between;
      gap: 1rem;
      border-radius: 1rem;
      border: 1px solid rgba(125, 211, 252, 0.22);
      background: linear-gradient(90deg, rgba(15, 23, 42, 0.86), rgba(15, 23, 42, 0.74), rgba(21, 94, 117, 0.58));
      padding: 1rem;
    }

    .top-panel-left {
      display: flex;
      align-items: center;
      gap: 0.75rem;
      min-width: 0;
    }

    .panel-eyebrow {
      margin: 0 0 0.2rem;
      font-size: 0.72rem;
      text-transform: uppercase;
      letter-spacing: 0.14em;
      color: #94a3b8;
    }

    .panel-title {
      margin: 0;
      font-size: 1.4rem;
      font-weight: 600;
      color: #f1f5f9;
      letter-spacing: -0.02em;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
      max-width: min(60vw, 28rem);
    }

    .top-panel-right {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: 0.5rem;
    }

    .status-pill {
      display: inline-flex;
      align-items: center;
      gap: 0.5rem;
      border-radius: 999px;
      border: 1px solid rgba(110, 231, 183, 0.38);
      background: rgba(52, 211, 153, 0.12);
      padding: 0.3rem 0.75rem;
      font-size: 0.7rem;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.12em;
      color: #d1fae5;
    }

    .status-pill-dot {
      width: 0.5rem;
      height: 0.5rem;
      border-radius: 999px;
      background: #86efac;
    }

    .quick-link {
      display: inline-flex;
      align-items: center;
      border-radius: 999px;
      border: 1px solid rgba(125, 211, 252, 0.32);
      background: rgba(56, 189, 248, 0.14);
      padding: 0.36rem 0.75rem;
      font-size: 0.72rem;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.08em;
      color: #bae6fd;
    }

    .quick-link:hover {
      border-color: rgba(186, 230, 253, 0.55);
      background: rgba(125, 211, 252, 0.2);
    }

    .content-shell {
      display: flex;
      flex: 1;
      min-height: 0;
    }

    .page-header {
      margin-bottom: 1.75rem;
      border-radius: 1rem;
      border: 1px solid rgba(203, 213, 225, 0.14);
      background: rgba(15, 23, 42, 0.45);
      padding: 1.1rem 1.25rem;
    }

    .page-subtitle {
      margin-top: 0.75rem;
      font-size: 0.93rem;
      color: #94a3b8;
      line-height: 1.5;
    }

    .cards {
      margin-bottom: 2rem;
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 1.25rem;
    }

    .card {
      position: relative;
      overflow: hidden;
      border-radius: 1rem;
      border: 1px solid rgba(148, 163, 184, 0.16);
      background: linear-gradient(150deg, rgba(15, 23, 42, 0.94), rgba(2, 6, 23, 0.86));
      padding: 1.25rem;
      box-shadow: 0 10px 24px rgba(2, 6, 23, 0.35);
    }

    .card-title {
      margin-bottom: 0.75rem;
      font-size: 0.76rem;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.08em;
      color: #94a3b8;
    }

    .card-value {
      font-size: 1.8rem;
      font-weight: 600;
      color: #f1f5f9;
    }

    .card-caption {
      margin-top: 0.65rem;
      font-size: 0.86rem;
      color: rgba(148, 163, 184, 0.92);
      line-height: 1.45;
    }

    .table-card {
      overflow: hidden;
      border-radius: 1rem;
      border: 1px solid rgba(148, 163, 184, 0.18);
      background: rgba(2, 6, 23, 0.78);
      box-shadow: 0 8px 20px rgba(2, 6, 23, 0.3);
    }

    .filter-form {
      margin: 1.5rem 0;
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: 0.75rem;
      border-radius: 1rem;
      border: 1px solid rgba(203, 213, 225, 0.14);
      background: rgba(15, 23, 42, 0.4);
      padding: 1rem;
    }

    .filter-form input[type="text"],
    .filter-form select,
    .form-grid input,
    .form-grid textarea {
      min-width: 10rem;
      border-radius: 0.75rem;
      border: 1px solid rgba(148, 163, 184, 0.2);
      background: rgba(30, 41, 59, 0.75);
      color: #e2e8f0;
      padding: 0.6rem 0.75rem;
      font: inherit;
    }

    .filter-form input[type="text"] {
      min-width: 13rem;
    }

    .filter-form button,
    .enqueue-form button {
      border: none;
      border-radius: 0.75rem;
      background: #38bdf8;
      color: #0f172a;
      padding: 0.62rem 1rem;
      font-weight: 600;
      cursor: pointer;
    }

    .filter-form button:hover,
    .enqueue-form button:hover {
      background: #7dd3fc;
    }

    .filter-label {
      font-size: 0.72rem;
      text-transform: uppercase;
      letter-spacing: 0.12em;
      color: #94a3b8;
    }

    .clear-filter {
      font-size: 0.86rem;
      color: #7dd3fc;
    }

    .sort-link {
      color: #94a3b8;
      font-weight: 600;
    }

    .sort-link:hover {
      color: #7dd3fc;
    }

    .sort-link.active {
      color: #f1f5f9;
    }

    .queue-row,
    .task-row {
      cursor: pointer;
    }

    .queue-row:hover {
      background: rgba(125, 211, 252, 0.1);
    }

    .queue-detail,
    .task-detail {
      display: none;
      background: rgba(2, 6, 23, 0.68);
    }

    .queue-detail.visible,
    .task-detail.visible {
      display: table-row;
    }

    .task-detail-cell {
      padding: 1rem;
    }

    .detail-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      gap: 0.75rem;
    }

    .detail-grid div {
      border-radius: 0.75rem;
      border: 1px solid rgba(148, 163, 184, 0.15);
      background: rgba(30, 41, 59, 0.6);
      padding: 0.75rem;
    }

    .meta-list {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
      gap: 0.5rem;
    }

    .meta-item {
      display: flex;
      flex-direction: column;
      gap: 0.3rem;
      min-width: 0;
      border-radius: 0.65rem;
      border: 1px solid rgba(148, 163, 184, 0.15);
      background: rgba(30, 41, 59, 0.6);
      padding: 0.6rem;
    }

    .payload-block {
      margin-top: 0.65rem;
      white-space: pre-wrap;
      word-break: break-word;
      border-radius: 0.65rem;
      border: 1px solid rgba(148, 163, 184, 0.2);
      background: rgba(2, 6, 23, 0.72);
      padding: 0.65rem 0.75rem;
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, "Courier New", monospace;
      font-size: 0.76rem;
      line-height: 1.55;
      color: #cbd5e1;
    }

    .flash {
      margin-bottom: 1.25rem;
      border-radius: 0.75rem;
      padding: 0.85rem 1rem;
      font-weight: 600;
    }

    .flash.success {
      border: 1px solid rgba(52, 211, 153, 0.35);
      background: rgba(52, 211, 153, 0.16);
      color: #bbf7d0;
    }

    .flash.error {
      border: 1px solid rgba(248, 113, 113, 0.35);
      background: rgba(248, 113, 113, 0.16);
      color: #fecaca;
    }

    .enqueue-card {
      border-radius: 1rem;
      border: 1px solid rgba(148, 163, 184, 0.16);
      background: rgba(2, 6, 23, 0.78);
      padding: 1.5rem;
    }

    .enqueue-form {
      display: flex;
      flex-direction: column;
      gap: 1rem;
    }

    .form-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 1rem;
    }

    .form-grid label {
      display: flex;
      flex-direction: column;
      gap: 0.5rem;
      font-size: 0.86rem;
      color: #94a3b8;
    }

    .payload-label textarea {
      min-height: 8rem;
      resize: vertical;
    }

    .enqueue-form button {
      align-self: flex-start;
      padding: 0.72rem 1rem;
    }

    .muted {
      color: #94a3b8;
    }

    .pill {
      display: inline-flex;
      align-items: center;
      gap: 0.35rem;
      border-radius: 999px;
      background: rgba(56, 189, 248, 0.14);
      padding: 0.35rem 0.75rem;
      color: #7dd3fc;
      font-size: 0.76rem;
    }

    .pill.success {
      background: rgba(52, 211, 153, 0.16);
      color: #bbf7d0;
    }

    .pill.error {
      background: rgba(248, 113, 113, 0.16);
      color: #fecaca;
    }

    .pill.warning {
      background: rgba(251, 191, 36, 0.2);
      color: #fde68a;
    }

    .pill.running {
      background: rgba(96, 165, 250, 0.2);
      color: #bfdbfe;
    }

    .pill.muted {
      background: rgba(148, 163, 184, 0.2);
      color: #cbd5e1;
    }

    .event-feed {
      display: grid;
      gap: 1rem;
    }

    .control-panel {
      margin-top: 1.75rem;
      border-radius: 1rem;
      border: 1px solid rgba(148, 163, 184, 0.16);
      background: rgba(2, 6, 23, 0.75);
      padding: 1.5rem;
    }

    .section-heading {
      margin: 0 0 1rem;
      font-size: 1.05rem;
      font-weight: 600;
      letter-spacing: -0.01em;
    }

    .action-bar {
      display: flex;
      flex-wrap: wrap;
      gap: 0.75rem;
    }

    .inline-form {
      margin: 0;
      display: inline-flex;
      align-items: center;
    }

    .ghost-button {
      border-radius: 0.75rem;
      border: 1px solid rgba(125, 211, 252, 0.3);
      background: rgba(56, 189, 248, 0.15);
      color: #7dd3fc;
      padding: 0.5rem 0.85rem;
      font-weight: 600;
      cursor: pointer;
    }

    .ghost-button:hover {
      background: rgba(125, 211, 252, 0.24);
    }

    .ghost-button.disabled {
      opacity: 0.45;
      pointer-events: none;
      cursor: default;
    }

    .pager {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 0.75rem;
      border-bottom: 1px solid rgba(148, 163, 184, 0.12);
      padding: 0.85rem 1rem;
    }

    .event-item {
      overflow: hidden;
      border-radius: 1rem;
      border: 1px solid rgba(148, 163, 184, 0.16);
      background: rgba(2, 6, 23, 0.82);
    }

    .event-item summary {
      display: flex;
      align-items: center;
      justify-content: space-between;
      list-style: none;
      cursor: pointer;
      padding: 1rem;
      font-weight: 600;
      color: #f1f5f9;
    }

    .event-item summary::-webkit-details-marker {
      display: none;
    }

    .event-item[open] summary {
      background: rgba(56, 189, 248, 0.12);
    }

    .event-title {
      font-size: 1rem;
    }

    .event-time {
      font-size: 0.85rem;
      color: #94a3b8;
    }

    .event-item > *:not(summary) {
      padding: 0 1rem 1rem;
    }

    .event-meta {
      margin-top: 0.65rem;
      display: flex;
      flex-wrap: wrap;
      gap: 0.75rem;
      font-size: 0.86rem;
      color: #94a3b8;
    }

    .error-preview {
      display: inline-block;
      max-width: 30rem;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
      vertical-align: top;
    }

    .mt-3 { margin-top: 0.75rem; }
    .mb-2 { margin-bottom: 0.5rem; }
    .mt-7 { margin-top: 1.75rem; }
    .mb-7 { margin-bottom: 1.75rem; }
    .p-4 { padding: 1rem; }
    .text-center { text-align: center; }
    .font-semibold { font-weight: 600; }
    .font-medium { font-weight: 500; }
    .text-slate-100 { color: #f1f5f9; }
    .text-slate-300 { color: #cbd5e1; }
    .text-slate-300\\/70 { color: rgba(203, 213, 225, 0.7); }
    .text-sky-100 { color: #e0f2fe; }
    .text-sky-200 { color: #bae6fd; }
    .text-lg { font-size: 1.125rem; }
    .text-sm { font-size: 0.875rem; }
    .uppercase { text-transform: uppercase; }
    .tracking-wide { letter-spacing: 0.06em; }
    .tracking-wider { letter-spacing: 0.1em; }
    .tracking-tight { letter-spacing: -0.01em; }
    .leading-relaxed { line-height: 1.625; }
    .border-b { border-bottom: 1px solid rgba(148, 163, 184, 0.12); }
    .ring-1 { box-shadow: inset 0 0 0 1px rgba(125, 211, 252, 0.14); }
    .ring-inset { }
    .ring-sky-300\\/10 { }
    .bg-slate-900\\/20 { background: rgba(15, 23, 42, 0.2); }
    .bg-slate-900\\/40 { background: rgba(15, 23, 42, 0.4); }
    .bg-slate-900\\/45 { background: rgba(15, 23, 42, 0.45); }
    .border { border: 1px solid rgba(148, 163, 184, 0.16); }
    .border-slate-300\\/10 { border-color: rgba(203, 213, 225, 0.1); }
    .border-slate-300\\/15 { border-color: rgba(203, 213, 225, 0.15); }
    .rounded-2xl { border-radius: 1rem; }
    .px-5 { padding-left: 1.25rem; padding-right: 1.25rem; }
    .py-5 { padding-top: 1.25rem; padding-bottom: 1.25rem; }
    .px-4 { padding-left: 1rem; padding-right: 1rem; }
    .py-3 { padding-top: 0.75rem; padding-bottom: 0.75rem; }

    @media (min-width: 640px) {
      .top-panel {
        padding: 1rem 1.25rem;
      }
    }

    @media (min-width: 1024px) {
      .app-shell {
        gap: 1.5rem;
        padding: 1.5rem;
      }

      .sidebar-backdrop,
      .sidebar-close,
      .sidebar-toggle {
        display: none;
      }

      .sidebar {
        position: sticky;
        top: 1.5rem;
        left: auto;
        transform: translateX(0);
        width: 18rem;
        height: calc(100vh - 3rem);
      }

      .main {
        padding: 1.5rem;
      }
    }
  </style>
  <style type="text/tailwindcss">
    @layer base {
      *,
      *::before,
      *::after {
        @apply box-border;
      }

      html {
        color-scheme: dark;
      }

      body {
        @apply m-0 bg-stem-950 font-sans text-slate-200 antialiased;
      }

      a {
        @apply text-inherit no-underline;
      }

      h1 {
        @apply m-0 text-3xl font-semibold tracking-tight;
      }

      table {
        @apply w-full border-collapse;
      }

      thead {
        @apply bg-slate-800/85 text-xs uppercase tracking-widest text-slate-400;
      }

      th,
      td {
        @apply px-4 py-3.5 text-left align-top;
      }

      tbody tr {
        @apply border-b border-slate-400/10 transition-colors duration-150;
      }

      tbody tr:last-child {
        @apply border-b-0;
      }

      tbody tr:hover {
        @apply bg-blue-900/25;
      }

      turbo-frame#dashboard-content {
        @apply block flex-1;
      }
    }

    @layer components {
      .app-shell {
        @apply relative flex min-h-screen gap-4 p-3 lg:gap-6 lg:p-6;
      }

      .app-shell::before {
        content: '';
        @apply pointer-events-none fixed inset-0;
        background:
          radial-gradient(900px 420px at 12% -8%, rgba(56, 189, 248, 0.18), transparent 70%),
          radial-gradient(760px 380px at 102% 18%, rgba(14, 116, 144, 0.16), transparent 64%),
          linear-gradient(180deg, #0b1220 0%, #0f172a 48%, #0c1324 100%);
      }

      .app-shell > * {
        @apply relative z-10;
      }

      .sidebar-backdrop {
        @apply pointer-events-none fixed inset-0 z-30 bg-stem-950/70 opacity-0 backdrop-blur-sm transition duration-200 lg:hidden;
      }

      .sidebar-backdrop[data-open='true'] {
        @apply pointer-events-auto opacity-100;
      }

      .sidebar {
        @apply fixed inset-y-3 left-3 z-40 flex -translate-x-full flex-col gap-6 rounded-3xl border border-sky-200/20 bg-gradient-to-b from-slate-900/95 via-blue-950/90 to-cyan-900/80 px-4 py-5 shadow-2xl shadow-sky-950/40 transition duration-300 lg:sticky lg:top-6 lg:w-72 lg:translate-x-0;
        width: min(18rem, calc(100vw - 1.5rem));
        height: calc(100vh - 1.5rem);
      }

      .sidebar[data-open='true'] {
        @apply translate-x-0;
      }

      .sidebar-head {
        @apply flex items-center justify-between gap-3;
      }

      .sidebar-close {
        @apply inline-flex h-10 w-10 items-center justify-center rounded-xl border border-slate-300/20 bg-slate-900/60 text-slate-300 transition hover:border-sky-300/45 hover:text-sky-200 lg:hidden;
      }

      .brand-panel {
        @apply rounded-2xl border border-sky-300/25 bg-sky-400/10 px-3.5 py-3;
      }

      .brand {
        @apply text-sm font-semibold uppercase tracking-widest text-sky-200;
      }

      .brand-tagline {
        @apply mt-1 text-xs text-slate-400;
      }

      .sidebar-status {
        @apply mt-4 flex items-center gap-2 text-xs uppercase tracking-wider text-emerald-200;
      }

      .status-dot {
        @apply h-2.5 w-2.5 rounded-full bg-emerald-300 ring-4 ring-emerald-300/20;
      }

      nav {
        @apply flex flex-col gap-2 rounded-2xl border border-slate-300/15 bg-slate-900/40 p-2;
      }

      .nav-link {
        @apply flex items-center gap-3 rounded-xl px-3.5 py-2.5 font-medium text-slate-300/80 transition duration-150;
      }

      .nav-link::before {
        content: '';
        @apply h-2 w-2 rounded-full bg-slate-400/30 transition duration-150;
      }

      .nav-link:hover {
        @apply translate-x-0.5 bg-sky-300/10 text-slate-100;
      }

      .nav-link.active {
        @apply bg-gradient-to-r from-sky-300/25 to-cyan-300/20 text-slate-50;
      }

      .nav-link.active::before {
        @apply bg-sky-300;
      }

      .sidebar-footer {
        @apply mt-auto rounded-2xl border border-slate-300/15 bg-slate-900/45 px-3.5 py-3 text-xs leading-relaxed text-slate-300/70;
      }

      .main {
        @apply relative flex flex-1 flex-col rounded-3xl border border-slate-400/15 bg-slate-900/70 p-4 shadow-2xl backdrop-blur xl:p-6;
      }

      .top-panel {
        @apply mb-5 flex flex-wrap items-center justify-between gap-4 rounded-2xl border border-sky-300/20 bg-gradient-to-r from-slate-900/85 via-slate-900/70 to-cyan-950/60 px-4 py-4;
      }

      .top-panel-left {
        @apply flex min-w-0 items-center gap-3;
      }

      .sidebar-toggle {
        @apply inline-flex h-10 w-10 items-center justify-center rounded-xl border border-slate-300/20 bg-slate-900/60 text-slate-200 transition hover:border-sky-300/45 hover:text-sky-200 lg:hidden;
      }

      .panel-eyebrow {
        @apply text-xs uppercase tracking-wider text-slate-400;
      }

      .panel-title {
        @apply truncate text-xl font-semibold tracking-tight text-slate-100 sm:text-2xl;
      }

      .top-panel-right {
        @apply flex flex-wrap items-center gap-2 sm:gap-3;
      }

      .status-pill {
        @apply inline-flex items-center gap-2 rounded-full border border-emerald-300/35 bg-emerald-300/10 px-3 py-1 text-xs font-semibold uppercase tracking-wider text-emerald-100;
      }

      .status-pill-dot {
        @apply h-2 w-2 rounded-full bg-emerald-300;
      }

      .quick-link {
        @apply inline-flex items-center rounded-full border border-sky-300/30 bg-sky-400/12 px-3 py-1.5 text-xs font-semibold uppercase tracking-wide text-sky-200 transition hover:border-sky-200/50 hover:bg-sky-300/20;
      }

      .content-shell {
        @apply flex min-h-0 flex-1;
      }

      .page-header {
        @apply mb-7;
      }

      .page-subtitle {
        @apply mt-3 text-sm text-slate-400;
      }

      .cards {
        @apply mb-8 grid grid-cols-1 gap-5 sm:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-4;
      }

      .card {
        @apply rounded-2xl border border-slate-400/15 bg-gradient-to-br from-stem-900/95 to-stem-950/80 p-5 shadow-xl;
      }

      .card-title {
        @apply mb-3 text-xs font-semibold uppercase tracking-wide text-slate-400;
      }

      .card-value {
        @apply text-3xl font-semibold;
      }

      .card-caption {
        @apply mt-2.5 text-sm text-slate-400/90;
      }

      .table-card {
        @apply overflow-hidden rounded-2xl border border-slate-400/15 bg-stem-950/85;
      }

      .filter-form {
        @apply my-6 flex flex-wrap items-center gap-3;
      }

      .filter-form input[type="text"],
      .filter-form select {
        @apply min-w-40 rounded-xl border border-slate-400/20 bg-slate-800/75 px-3.5 py-2.5 text-slate-100;
      }

      .filter-form input[type="text"] {
        @apply min-w-52;
      }

      .filter-form button,
      .enqueue-form button {
        @apply cursor-pointer rounded-xl bg-sky-400 px-4 py-2.5 font-semibold text-stem-950 transition duration-150 hover:bg-sky-300;
      }

      .filter-label {
        @apply text-xs uppercase tracking-widest text-slate-400;
      }

      .clear-filter {
        @apply text-sm text-sky-300;
      }

      .sort-link {
        @apply font-semibold text-slate-400;
      }

      .sort-link:hover {
        @apply text-sky-300;
      }

      .sort-link.active {
        @apply text-slate-100;
      }

      .queue-row,
      .task-row {
        @apply cursor-pointer;
      }

      .queue-row:hover {
        @apply bg-sky-400/10;
      }

      .queue-detail,
      .task-detail {
        @apply hidden bg-stem-950/80;
      }

      .queue-detail.visible,
      .task-detail.visible {
        @apply table-row;
      }

      .task-detail-cell {
        @apply p-4;
      }

      .detail-grid {
        @apply grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-3;
      }

      .detail-grid div {
        @apply rounded-xl border border-slate-400/15 bg-slate-800/60 p-3;
      }

      .meta-list {
        @apply grid grid-cols-1 gap-2 lg:grid-cols-2;
      }

      .meta-item {
        @apply flex min-w-0 flex-col gap-1 rounded-lg border border-slate-400/15 bg-slate-800/60 p-2.5;
      }

      .payload-block {
        @apply mt-2.5 whitespace-pre-wrap break-words rounded-lg border border-slate-400/20 bg-slate-950/70 px-3 py-2.5 font-mono text-xs leading-relaxed text-slate-300;
      }

      .flash {
        @apply mb-5 rounded-xl px-4 py-3.5 font-semibold;
      }

      .flash.success {
        @apply border border-emerald-400/35 bg-emerald-400/15 text-emerald-200;
      }

      .flash.error {
        @apply border border-red-400/35 bg-red-400/15 text-red-200;
      }

      .enqueue-card {
        @apply rounded-2xl border border-slate-400/15 bg-stem-950/85 p-6;
      }

      .enqueue-form {
        @apply flex flex-col gap-4;
      }

      .form-grid {
        @apply grid grid-cols-1 gap-4 md:grid-cols-2;
      }

      .form-grid label {
        @apply flex flex-col gap-2 text-sm text-slate-400;
      }

      .form-grid input,
      .form-grid textarea {
        @apply rounded-xl border border-slate-400/20 bg-slate-800/75 px-3 py-2.5 text-slate-100;
      }

      .payload-label textarea {
        @apply min-h-32 resize-y;
      }

      .enqueue-form button {
        @apply self-start px-4 py-3;
      }

      .muted {
        @apply text-slate-400;
      }

      .pill {
        @apply inline-flex items-center gap-1.5 rounded-full bg-sky-400/15 px-3 py-1.5 text-xs text-sky-300;
      }

      .pill.success {
        @apply bg-emerald-400/15 text-emerald-200;
      }

      .pill.error {
        @apply bg-red-400/15 text-red-200;
      }

      .pill.warning {
        @apply bg-amber-400/20 text-amber-200;
      }

      .pill.running {
        @apply bg-blue-400/20 text-blue-200;
      }

      .pill.muted {
        @apply bg-slate-400/20 text-slate-300;
      }

      .event-feed {
        @apply grid gap-4;
      }

      .control-panel {
        @apply mt-7 rounded-2xl border border-slate-400/15 bg-stem-950/80 p-6;
      }

      .section-heading {
        @apply mb-4 text-lg font-semibold tracking-tight;
      }

      .action-bar {
        @apply flex flex-wrap gap-3;
      }

      .inline-form {
        @apply m-0 inline-flex items-center;
      }

      .ghost-button {
        @apply cursor-pointer rounded-xl border border-sky-300/30 bg-sky-400/15 px-3.5 py-2 font-semibold text-sky-300 transition duration-150 hover:bg-sky-400/25;
      }

      .ghost-button.disabled {
        @apply pointer-events-none cursor-default opacity-45;
      }

      .pager {
        @apply flex items-center justify-between gap-3 border-b border-slate-400/10 px-4 py-3.5;
      }

      .event-item {
        @apply overflow-hidden rounded-2xl border border-slate-400/15 bg-stem-950/85;
      }

      .event-item summary {
        @apply flex cursor-pointer list-none items-center justify-between px-4 py-4 font-semibold text-slate-100;
      }

      .event-item summary::-webkit-details-marker {
        display: none;
      }

      .event-item[open] summary {
        @apply bg-sky-400/10;
      }

      .event-title {
        @apply text-base;
      }

      .event-time {
        @apply text-sm text-slate-400;
      }

      .event-item > *:not(summary) {
        @apply px-4 pb-4;
      }

      .event-meta {
        @apply mt-2.5 flex flex-wrap gap-3 text-sm text-slate-400;
      }

      .error-preview {
        @apply inline-block max-w-[30rem] overflow-hidden text-ellipsis whitespace-nowrap align-top;
      }
    }

    @media (min-width: 1024px) {
      .sidebar {
        width: 18rem;
      }
    }
  </style>
</head>
<body>
  <div class="app-shell">
    <button id="sidebar-backdrop" class="sidebar-backdrop" type="button" aria-label="Close navigation"></button>
    <aside id="dashboard-sidebar" class="sidebar" data-open="false" aria-label="Dashboard navigation">
      <div class="sidebar-head">
        <div class="brand-panel">
          <div class="brand">Stem</div>
          <p class="brand-tagline">Workflow control plane</p>
          <div class="sidebar-status">
            <span class="status-dot"></span>
            <span>Live feed</span>
          </div>
        </div>
        <button id="sidebar-close" class="sidebar-close" type="button" aria-label="Close navigation panel">
          ✕
        </button>
      </div>
      <nav>
        ${_renderNav(page, basePath)}
      </nav>
      <div class="sidebar-footer">
        Turbo streams and frame-driven updates keep this panel live without full-page navigation.
      </div>
    </aside>
    <main class="main">
      <header class="top-panel">
        <div class="top-panel-left">
          <button id="sidebar-toggle" class="sidebar-toggle" type="button" aria-label="Open navigation panel">
            ☰
          </button>
          <div>
            <p class="panel-eyebrow">Operations cockpit</p>
            <h2 id="top-panel-title" class="panel-title">${page.label}</h2>
          </div>
        </div>
        <div class="top-panel-right">
          <span class="status-pill">
            <span class="status-pill-dot"></span>
            Auto refresh
          </span>
          <a href="${dashboardRoute(basePath, '/tasks')}" class="quick-link" data-turbo-frame="dashboard-content">Tasks</a>
          <a href="${dashboardRoute(basePath, '/workers')}" class="quick-link" data-turbo-frame="dashboard-content">Workers</a>
        </div>
      </header>
      <div class="content-shell">
        ${renderFrame(page, content)}
      </div>
      <div id="dashboard-refresh-signal" hidden></div>
    </main>
  </div>
  <script type="module">
  const frame = document.getElementById('dashboard-content');
  const sidebar = document.getElementById('dashboard-sidebar');
  const sidebarToggle = document.getElementById('sidebar-toggle');
  const sidebarClose = document.getElementById('sidebar-close');
  const sidebarBackdrop = document.getElementById('sidebar-backdrop');
  const topPanelTitle = document.getElementById('top-panel-title');
  const dashboardBasePath = '$resolvedBasePath';
  const tasksInlinePath = `\${dashboardBasePath || ''}/tasks/inline`;
  const overviewPartialsPath = `\${dashboardBasePath || ''}/partials/overview`;
  const refreshablePages = new Set(['overview', 'tasks', 'taskDetail', 'failures', 'workers', 'search', 'audit', 'namespaces', 'workflows', 'jobs']);
  let lastRefreshAt = 0;
  let currentFrameUrl = '';
  let frameNavigationInFlight = false;
  let pendingNavigationUrl = '';
  let refreshFrameController = null;
  let refreshOverviewController = null;

  const normalizeFrameUrl = (rawUrl) => {
    try {
      const parsed = new URL(rawUrl, window.location.origin);
      return `\${parsed.pathname}\${parsed.search}`;
    } catch (_) {
      return window.location.pathname + window.location.search;
    }
  };

  const rememberCurrentFrameUrl = (rawUrl) => {
    if (!frame) return;
    const normalized = normalizeFrameUrl(rawUrl);
    currentFrameUrl = normalized;
    frame.dataset.currentUrl = normalized;
  };

  const snapshotFrameUrl = () => {
    const raw = frame?.dataset?.currentUrl ||
      currentFrameUrl ||
      (window.location.pathname + window.location.search);
    return normalizeFrameUrl(raw);
  };

  const cancelRefreshControllers = () => {
    if (refreshFrameController) {
      refreshFrameController.abort();
      refreshFrameController = null;
    }
    if (refreshOverviewController) {
      refreshOverviewController.abort();
      refreshOverviewController = null;
    }
  };

  const markNavigationLoading = (enabled) => {
    if (!frame) return;
    if (enabled) {
      frame.dataset.navLoading = 'true';
      return;
    }
    delete frame.dataset.navLoading;
  };

  const dashboardPathFromUrl = (rawUrl) => {
    const parsed = new URL(rawUrl, window.location.origin);
    const pathname = parsed.pathname || '/';
    if (!dashboardBasePath) return pathname;
    if (pathname === dashboardBasePath) return '/';
    if (pathname.startsWith(`\${dashboardBasePath}/`)) {
      return pathname.substring(dashboardBasePath.length);
    }
    return pathname;
  };

  const pageFromUrl = (rawUrl) => {
    let path;
    try {
      path = dashboardPathFromUrl(rawUrl);
    } catch (_) {
      path = '/';
    }
    if (path === '/' || path === '') return 'overview';
    if (path.startsWith('/tasks/detail')) return 'tasks';
    if (path.startsWith('/tasks')) return 'tasks';
    if (path.startsWith('/failures')) return 'failures';
    if (path.startsWith('/search')) return 'search';
    if (path.startsWith('/audit')) return 'audit';
    if (path.startsWith('/events')) return 'events';
    if (path.startsWith('/namespaces')) return 'namespaces';
    if (path.startsWith('/workflows')) return 'workflows';
    if (path.startsWith('/jobs')) return 'jobs';
    if (path.startsWith('/workers')) return 'workers';
    return 'overview';
  };

  const pageTitleFromUrl = (rawUrl) => {
    let path;
    try {
      path = dashboardPathFromUrl(rawUrl);
    } catch (_) {
      path = '/';
    }
    if (path === '/' || path === '') return 'Overview';
    if (path.startsWith('/tasks/detail')) return 'Task Detail';
    if (path.startsWith('/tasks')) return 'Tasks';
    if (path.startsWith('/failures')) return 'Failures';
    if (path.startsWith('/search')) return 'Search';
    if (path.startsWith('/audit')) return 'Audit';
    if (path.startsWith('/events')) return 'Events';
    if (path.startsWith('/namespaces')) return 'Namespaces';
    if (path.startsWith('/workflows')) return 'Workflows';
    if (path.startsWith('/jobs')) return 'Jobs';
    if (path.startsWith('/workers')) return 'Workers';
    return 'Overview';
  };

  const resolveCurrentPage = () => {
    const url = frame?.dataset?.currentUrl || currentFrameUrl || (window.location.pathname + window.location.search);
    return pageFromUrl(url);
  };

  const updatePanelTitle = (rawUrl) => {
    if (!topPanelTitle) return;
    topPanelTitle.textContent = pageTitleFromUrl(rawUrl);
  };

  const isDesktop = () => window.matchMedia('(min-width: 1024px)').matches;

  const closeSidebarPanel = () => {
    if (!sidebar || !sidebarBackdrop) return;
    sidebar.dataset.open = 'false';
    sidebarBackdrop.dataset.open = 'false';
  };

  const openSidebarPanel = () => {
    if (!sidebar || !sidebarBackdrop || isDesktop()) return;
    sidebar.dataset.open = 'true';
    sidebarBackdrop.dataset.open = 'true';
  };

  const syncSidebarWithViewport = () => {
    if (isDesktop()) {
      closeSidebarPanel();
    }
  };

  const syncHistoryToFrameUrl = () => {
    if (!currentFrameUrl) return;
    const current = window.location.pathname + window.location.search;
    if (current === currentFrameUrl) return;
    window.history.replaceState(window.history.state, '', currentFrameUrl);
  };

  const refreshOverviewPartials = async (sourceUrl) => {
    if (refreshOverviewController) {
      refreshOverviewController.abort();
    }
    const controller = new AbortController();
    refreshOverviewController = controller;
    const response = await fetch(overviewPartialsPath, {
      headers: { Accept: 'text/vnd.turbo-stream.html' },
      signal: controller.signal,
    });
    const body = await response.text();
    if (controller.signal.aborted) return;
    if (!response.ok) {
      throw new Error(`Failed overview partial refresh: \${response.status}`);
    }
    if (snapshotFrameUrl() !== normalizeFrameUrl(sourceUrl)) {
      return;
    }
    if (resolveCurrentPage() !== 'overview') {
      return;
    }
    if (!window.Turbo) return;
    window.Turbo.renderStreamMessage(body);
  };

  const refreshFrameContent = async (sourceUrl) => {
    if (!frame) return;
    if (refreshFrameController) {
      refreshFrameController.abort();
    }
    const controller = new AbortController();
    refreshFrameController = controller;
    const response = await fetch(sourceUrl, {
      headers: {
        Accept: 'text/html',
        'Turbo-Frame': 'dashboard-content',
      },
      signal: controller.signal,
    });
    const body = await response.text();
    if (controller.signal.aborted) return;
    if (!response.ok) {
      throw new Error(`Failed frame refresh: \${response.status}`);
    }
    if (snapshotFrameUrl() !== normalizeFrameUrl(sourceUrl)) {
      return;
    }

    const parser = new DOMParser();
    const doc = parser.parseFromString(body, 'text/html');
    const nextFrame = doc.getElementById('dashboard-content');
    if (!nextFrame) {
      throw new Error('Missing dashboard-content frame in refresh response.');
    }

    frame.innerHTML = nextFrame.innerHTML;
    frame.dataset.page = nextFrame.dataset.page || frame.dataset.page || '';
    rememberCurrentFrameUrl(sourceUrl);
    syncHistoryToFrameUrl();
    updatePanelTitle(sourceUrl);
    const currentPage = resolveCurrentPage();
    setActive(currentPage);
    if (currentPage === 'events') {
      ensureEventsStream();
    }
    scheduleFrameRefresh(currentPage);
  };

  const refreshFrame = () => {
    if (document.visibilityState === 'hidden') return;
    if (!window.Turbo || !frame) return;
    if (frameNavigationInFlight) return;
    const now = Date.now();
    if (now - lastRefreshAt < 1200) return;
    lastRefreshAt = now;
    const sourceUrl = snapshotFrameUrl();
    const page = resolveCurrentPage();
    if (page === 'overview') {
      refreshOverviewPartials(sourceUrl).catch(() => {
        if (frameNavigationInFlight) return;
        const fallbackUrl = snapshotFrameUrl();
        window.Turbo.visit(fallbackUrl, { frame: 'dashboard-content', action: 'replace' });
      });
      return;
    }
    refreshFrameContent(sourceUrl).catch(() => {
      if (frameNavigationInFlight) return;
      const fallbackUrl = snapshotFrameUrl();
      window.Turbo.visit(fallbackUrl, { frame: 'dashboard-content', action: 'replace' });
    });
  };

  const setActive = (page) => {
    document.querySelectorAll('[data-nav]').forEach((link) => {
      const active = link.dataset.nav === page;
      link.classList.toggle('active', active);
      if (active) {
        link.setAttribute('aria-current', 'page');
      } else {
        link.removeAttribute('aria-current');
      }
    });
  };

  const ensureEventsStream = () => {
    if (window.stemDashboardEventsWs) return;
    const protocol = window.location.protocol === 'https:' ? 'wss' : 'ws';
    const socket = new WebSocket(`\${protocol}://\${window.location.host}$resolvedStreamPath?topic=stem-dashboard:events`);
    socket.addEventListener('message', (event) => {
      if (window.Turbo) {
        window.Turbo.renderStreamMessage(event.data);
      }
    });
    socket.addEventListener('close', () => {
      window.stemDashboardEventsWs = null;
      setTimeout(() => {
        ensureEventsStream();
      }, 2000);
    });
    socket.addEventListener('error', () => {
      try { socket.close(); } catch (_) {}
    });
    window.stemDashboardEventsWs = socket;
  };

  const ensureRefreshStream = () => {
    if (window.stemDashboardRefreshWs) return;
    const protocol = window.location.protocol === 'https:' ? 'wss' : 'ws';
    const socket = new WebSocket(`\${protocol}://\${window.location.host}$resolvedStreamPath?topic=stem-dashboard:refresh`);
    socket.addEventListener('message', () => {
      const page = resolveCurrentPage();
      if (!refreshablePages.has(page)) return;
      refreshFrame();
    });
    socket.addEventListener('close', () => {
      window.stemDashboardRefreshWs = null;
      setTimeout(() => {
        ensureRefreshStream();
      }, 2000);
    });
    socket.addEventListener('error', () => {
      try { socket.close(); } catch (_) {}
    });
    window.stemDashboardRefreshWs = socket;
  };

  const scheduleFrameRefresh = (page) => {
    if (window.stemDashboardFrameTimer) {
      clearInterval(window.stemDashboardFrameTimer);
      window.stemDashboardFrameTimer = null;
    }
    if (!refreshablePages.has(page)) return;
    window.stemDashboardFrameTimer = setInterval(() => {
      refreshFrame();
    }, 5000);
  };

  const loadTaskInlineDetails = async (row) => {
    const taskId = row?.dataset?.taskRow;
    const target = row?.dataset?.taskInlineTarget;
    if (!taskId || !target) return;
    const shell = document.getElementById(target);
    if (!shell) return;
    const state = shell.dataset.taskInlineShell;
    if (state === 'loading' || state === 'loaded') return;

    shell.dataset.taskInlineShell = 'loading';
    shell.innerHTML = '<p class="muted">Loading task detail...</p>';

    const params = new URLSearchParams({ id: taskId, target });
    const response = await fetch(`\${tasksInlinePath}?\${params.toString()}`, {
      headers: { Accept: 'text/vnd.turbo-stream.html' },
    });
    const body = await response.text();
    if (!response.ok) {
      throw new Error(`Failed inline task request: \${response.status}`);
    }
    if (window.Turbo) {
      window.Turbo.renderStreamMessage(body);
      return;
    }
    shell.dataset.taskInlineShell = 'loaded';
    shell.innerHTML = body;
  };

  const ensureTaskDetailRow = (taskRow) => {
    const taskId = taskRow?.dataset?.taskRow;
    if (!taskId) return null;
    let target = taskRow?.dataset?.taskInlineTarget;
    if (!target) {
      const normalized = taskId.replace(/[^a-zA-Z0-9_-]/g, '-');
      target = `task-inline-\${normalized}`;
      taskRow.dataset.taskInlineTarget = target;
    }
    let detail = document.querySelector(`[data-task-detail="\${taskId}"]`);
    if (detail) return detail;

    detail = document.createElement('tr');
    detail.className = 'task-detail';
    detail.dataset.taskDetail = taskId;

    const detailCell = document.createElement('td');
    detailCell.className = 'task-detail-cell';
    detailCell.colSpan = Math.max(taskRow.cells?.length || 1, 1);
    detailCell.innerHTML = `<div id="\${target}" data-task-inline-shell="pending"><p class="muted">Loading task detail...</p></div>`;

    detail.appendChild(detailCell);
    taskRow.insertAdjacentElement('afterend', detail);
    return detail;
  };

  const collapseTaskDetailRow = (taskRow) => {
    const taskId = taskRow?.dataset?.taskRow;
    if (!taskId) return;
    const detail = document.querySelector(`[data-task-detail="\${taskId}"]`);
    detail?.remove();
    taskRow.setAttribute('aria-expanded', 'false');
  };

  if (frame) {
    rememberCurrentFrameUrl(frame.dataset.currentUrl || window.location.pathname + window.location.search);
    const initialPage = resolveCurrentPage();
    setActive(initialPage);
    updatePanelTitle(frame.dataset.currentUrl || window.location.pathname + window.location.search);
    ensureRefreshStream();
    if (initialPage === 'events') {
      ensureEventsStream();
    }
    scheduleFrameRefresh(initialPage);
    document.addEventListener('turbo:before-fetch-request', (event) => {
      if (event.target !== frame) return;
      frameNavigationInFlight = true;
      cancelRefreshControllers();
      const requestUrl = event.detail?.url;
      if (!requestUrl) return;
      const normalized = normalizeFrameUrl(requestUrl);
      pendingNavigationUrl = normalized;
      rememberCurrentFrameUrl(normalized);
    });
    document.addEventListener('turbo:before-frame-render', (event) => {
      if (event.target !== frame) return;
      if (pendingNavigationUrl !== '') {
        const responseUrl = event.detail?.fetchResponse?.response?.url ??
          event.detail?.newFrame?.src;
        if (responseUrl) {
          const normalized = normalizeFrameUrl(responseUrl);
          if (normalized != pendingNavigationUrl) {
            event.preventDefault();
            return;
          }
        }
      }
    });
    document.addEventListener('turbo:fetch-request-error', (event) => {
      if (event.target !== frame) return;
      frameNavigationInFlight = false;
      pendingNavigationUrl = '';
      markNavigationLoading(false);
    });
    document.addEventListener('turbo:frame-load', (event) => {
      if (event.target.id !== 'dashboard-content') return;
      frameNavigationInFlight = false;
      const responseUrl = event.detail?.fetchResponse?.response?.url ?? event.target?.src;
      if (responseUrl) {
        rememberCurrentFrameUrl(responseUrl);
        syncHistoryToFrameUrl();
        updatePanelTitle(responseUrl);
      }
      pendingNavigationUrl = '';
      markNavigationLoading(false);
      const currentPage = resolveCurrentPage();
      setActive(currentPage);
      ensureRefreshStream();
      if (currentPage === 'events') {
        ensureEventsStream();
      }
      scheduleFrameRefresh(currentPage);
    });
  }

  sidebarToggle?.addEventListener('click', () => {
    openSidebarPanel();
  });
  sidebarClose?.addEventListener('click', () => {
    closeSidebarPanel();
  });
  sidebarBackdrop?.addEventListener('click', () => {
    closeSidebarPanel();
  });
  window.addEventListener('resize', () => {
    syncSidebarWithViewport();
  });
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
      closeSidebarPanel();
    }
  });
  syncSidebarWithViewport();

  document.addEventListener('click', (event) => {
    const frameLink = event.target.closest('a[data-turbo-frame="dashboard-content"]');
    if (frameLink) {
      const href = frameLink.getAttribute('href');
      if (href) {
        if (frameLink.hasAttribute('data-nav')) {
          closeSidebarPanel();
        }
        if (window.Turbo &&
            event.button === 0 &&
            !event.metaKey &&
            !event.ctrlKey &&
            !event.shiftKey &&
            !event.altKey) {
          event.preventDefault();
          frameNavigationInFlight = true;
          cancelRefreshControllers();
          const normalized = normalizeFrameUrl(href);
          pendingNavigationUrl = normalized;
          rememberCurrentFrameUrl(normalized);
          markNavigationLoading(true);
          window.Turbo.visit(
            href,
            { frame: 'dashboard-content', action: 'replace' },
          );
          return;
        }
      }
    }
    const isInteractive = Boolean(
      event.target.closest('a, button, input, textarea, select, label, form')
    );
    const row = event.target.closest('[data-queue-row]');
    if (row && !isInteractive) {
      const queue = row.dataset.queueRow;
      if (!queue) return;
      const detail = document.querySelector(`[data-queue-detail="\${queue}"]`);
      if (!detail) return;
      detail.classList.toggle('visible');
      return;
    }
    const taskRow = event.target.closest('[data-task-row]');
    if (!taskRow || isInteractive) return;
    const taskId = taskRow.dataset.taskRow;
    if (!taskId) return;
    if (taskRow.getAttribute('aria-expanded') === 'true') {
      collapseTaskDetailRow(taskRow);
      return;
    }

    const detail = ensureTaskDetailRow(taskRow);
    if (!detail) return;
    detail.classList.add('visible');
    taskRow.setAttribute('aria-expanded', 'true');
    loadTaskInlineDetails(taskRow).catch(() => {
      const target = taskRow.dataset.taskInlineTarget;
      if (!target) return;
      const shell = document.getElementById(target);
      if (!shell) return;
      shell.dataset.taskInlineShell = 'error';
      shell.innerHTML = '<p class="muted">Failed to load task detail. Open full detail for this task.</p>';
    });
  });
  </script>
</body>
</html>
''';
}

/// Renders a Turbo frame payload for a dashboard page.
String renderFrame(DashboardPage page, String content) {
  return '''
<turbo-frame id="dashboard-content" data-page="${page.name}">
$content
</turbo-frame>
''';
}

String _renderNav(DashboardPage active, String basePath) {
  return DashboardPage.values
      .where((page) => page.showInNav)
      .map((page) => _navLink(page, active, basePath))
      .join('\n');
}

String _navLink(DashboardPage page, DashboardPage active, String basePath) {
  final isActive = page == active;
  final classes = ['nav-link', if (isActive) 'active'].join(' ');
  final aria = isActive ? ' aria-current="page"' : '';
  final route = dashboardRoute(basePath, page.path);
  return '''
<a href="$route" class="$classes" data-nav="${page.name}" data-turbo-frame="dashboard-content"$aria>
  ${page.label}
</a>
''';
}
