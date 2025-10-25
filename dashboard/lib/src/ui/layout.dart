enum DashboardPage {
  overview('/'),
  tasks('/tasks'),
  events('/events'),
  workers('/workers');

  const DashboardPage(this.path);

  final String path;

  String get label {
    switch (this) {
      case DashboardPage.overview:
        return 'Overview';
      case DashboardPage.tasks:
        return 'Tasks';
      case DashboardPage.events:
        return 'Events';
      case DashboardPage.workers:
        return 'Workers';
    }
  }

  String get title => 'Stem Dashboard · $label';
}

String renderLayout(DashboardPage page, String content) {
  return '''
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${page.title}</title>
  <script src="https://cdn.jsdelivr.net/npm/@hotwired/turbo@8/dist/turbo.es2017-umd.js" data-turbo-track="reload"></script>
  <style>
    *,
    *::before,
    *::after {
      box-sizing: border-box;
    }

    :root {
      color-scheme: dark;
      --surface-900: #0f172a;
      --surface-800: #111827;
      --surface-700: #1e293b;
      --surface-600: #1f2937;
      --accent-500: #38bdf8;
      --accent-400: #7dd3fc;
      --text-primary: #e2e8f0;
      --text-secondary: #94a3b8;
      --border-muted: rgba(148, 163, 184, 0.2);
      --border-strong: rgba(148, 163, 184, 0.35);
      --shadow-soft: 0 12px 40px rgba(15, 23, 42, 0.32);
      font-family: "Inter", system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }

    body {
      margin: 0;
      background: var(--surface-900);
      color: var(--text-primary);
    }

    a {
      color: inherit;
      text-decoration: none;
    }

    .app-shell {
      min-height: 100vh;
      display: flex;
      gap: 24px;
      padding: 24px;
    }

    .sidebar {
      width: 240px;
      flex-shrink: 0;
      background: linear-gradient(160deg, rgba(30, 58, 138, 0.6), rgba(8, 145, 178, 0.3));
      border-radius: 24px;
      padding: 28px 22px;
      display: flex;
      flex-direction: column;
      gap: 24px;
      box-shadow: var(--shadow-soft);
      border: 1px solid rgba(125, 211, 252, 0.2);
    }

    .brand {
      font-weight: 600;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      color: var(--accent-400);
      font-size: 0.95rem;
    }

    nav {
      display: flex;
      flex-direction: column;
      gap: 8px;
    }

    .nav-link {
      display: flex;
      align-items: center;
      gap: 12px;
      padding: 12px 14px;
      border-radius: 12px;
      color: var(--text-secondary);
      font-weight: 500;
      transition: background 160ms ease, color 160ms ease, transform 160ms ease;
    }

    .nav-link::before {
      content: '';
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: rgba(148, 163, 184, 0.24);
      transition: background 160ms ease;
    }

    .nav-link:hover {
      background: rgba(148, 163, 184, 0.16);
      color: var(--text-primary);
      transform: translateX(2px);
    }

    .nav-link.active {
      background: rgba(56, 189, 248, 0.18);
      color: var(--text-primary);
    }

    .nav-link.active::before {
      background: var(--accent-500);
    }

    .sidebar-footer {
      margin-top: auto;
      font-size: 0.8rem;
      color: rgba(226, 232, 240, 0.6);
    }

    .main {
      flex: 1;
      background: var(--surface-800);
      border-radius: 32px;
      padding: 40px;
      box-shadow: var(--shadow-soft);
      border: 1px solid rgba(148, 163, 184, 0.12);
      display: flex;
      flex-direction: column;
    }

    turbo-frame#dashboard-content {
      display: block;
      flex: 1;
    }

    h1 {
      margin: 0;
      font-size: 2rem;
      font-weight: 600;
      letter-spacing: -0.02em;
    }

    .page-header {
      margin-bottom: 28px;
    }

    .page-subtitle {
      margin-top: 12px;
      color: var(--text-secondary);
      font-size: 0.95rem;
    }

    .cards {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 20px;
      margin-bottom: 32px;
    }

    .card {
      border-radius: 20px;
      padding: 20px;
      background: linear-gradient(160deg, rgba(17, 24, 39, 0.94), rgba(15, 23, 42, 0.8));
      border: 1px solid rgba(148, 163, 184, 0.14);
      box-shadow: 0 14px 35px rgba(15, 23, 42, 0.4);
    }

    .card-title {
      font-size: 0.85rem;
      font-weight: 600;
      letter-spacing: 0.04em;
      text-transform: uppercase;
      color: var(--text-secondary);
      margin-bottom: 12px;
    }

    .card-value {
      font-size: 1.75rem;
      font-weight: 600;
    }

    .card-caption {
      margin-top: 10px;
      color: rgba(148, 163, 184, 0.8);
      font-size: 0.9rem;
    }

    .table-card {
      border-radius: 22px;
      border: 1px solid rgba(148, 163, 184, 0.12);
      background: rgba(15, 23, 42, 0.86);
      overflow: hidden;
    }

    .filter-form {
      display: flex;
      gap: 12px;
      align-items: center;
      flex-wrap: wrap;
      margin: 24px 0;
    }

    .filter-form input[type="text"] {
      background: rgba(30, 41, 59, 0.7);
      border: 1px solid rgba(148, 163, 184, 0.18);
      border-radius: 12px;
      padding: 10px 14px;
      color: var(--text-primary);
      min-width: 200px;
    }

    .filter-form button {
      background: var(--accent-500);
      color: var(--surface-900);
      border: none;
      border-radius: 12px;
      padding: 10px 16px;
      font-weight: 600;
      cursor: pointer;
    }

    .filter-form button:hover {
      background: var(--accent-400);
    }

    .filter-label {
      font-size: 0.8rem;
      text-transform: uppercase;
      letter-spacing: 0.08em;
      color: var(--text-secondary);
    }

    .clear-filter {
      color: var(--accent-400);
      font-size: 0.85rem;
    }

    .sort-link {
      color: var(--text-secondary);
      font-weight: 600;
    }

    .sort-link:hover {
      color: var(--accent-400);
    }

    .sort-link.active {
      color: var(--text-primary);
    }

    table {
      width: 100%;
      border-collapse: collapse;
    }

    thead {
      background: rgba(30, 41, 59, 0.85);
      text-transform: uppercase;
      font-size: 0.75rem;
      letter-spacing: 0.08em;
      color: var(--text-secondary);
    }

    th,
    td {
      padding: 14px 18px;
      text-align: left;
    }

    tbody tr {
      border-bottom: 1px solid rgba(148, 163, 184, 0.08);
      transition: background 140ms ease;
    }

    tbody tr:last-child {
      border-bottom: none;
    }

    tbody tr:hover {
      background: rgba(30, 64, 175, 0.16);
    }

    .queue-row {
      cursor: pointer;
    }

    .queue-row:hover {
      background: rgba(56, 189, 248, 0.12);
    }

    .queue-detail {
      display: none;
      background: rgba(15, 23, 42, 0.75);
    }

    .queue-detail.visible {
      display: table-row;
    }

    .detail-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      gap: 12px;
    }

    .detail-grid div {
      background: rgba(30, 41, 59, 0.6);
      border: 1px solid rgba(148, 163, 184, 0.12);
      border-radius: 12px;
      padding: 12px;
    }

    .flash {
      padding: 14px 18px;
      border-radius: 12px;
      margin-bottom: 20px;
      font-weight: 600;
    }

    .flash.success {
      background: rgba(34, 197, 94, 0.16);
      color: #bbf7d0;
      border: 1px solid rgba(34, 197, 94, 0.32);
    }

    .flash.error {
      background: rgba(239, 68, 68, 0.16);
      color: #fecaca;
      border: 1px solid rgba(239, 68, 68, 0.32);
    }

    .enqueue-card {
      background: rgba(15, 23, 42, 0.8);
      border: 1px solid rgba(148, 163, 184, 0.14);
      border-radius: 16px;
      padding: 24px;
    }

    .enqueue-form {
      display: flex;
      flex-direction: column;
      gap: 16px;
    }

    .form-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 16px;
    }

    .form-grid label {
      display: flex;
      flex-direction: column;
      gap: 8px;
      color: var(--text-secondary);
      font-size: 0.85rem;
    }

    .form-grid input,
    .form-grid textarea {
      background: rgba(30, 41, 59, 0.72);
      border: 1px solid rgba(148, 163, 184, 0.18);
      border-radius: 12px;
      padding: 10px 12px;
      color: var(--text-primary);
    }

    .payload-label textarea {
      min-height: 120px;
      resize: vertical;
    }

    .enqueue-form button {
      align-self: flex-start;
      background: var(--accent-500);
      color: var(--surface-900);
      border: none;
      border-radius: 12px;
      padding: 12px 18px;
      font-weight: 600;
      cursor: pointer;
    }

    .enqueue-form button:hover {
      background: var(--accent-400);
    }

    .muted {
      color: var(--text-secondary);
    }

    .pill {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      font-size: 0.8rem;
      padding: 6px 12px;
      border-radius: 999px;
      background: rgba(56, 189, 248, 0.12);
      color: var(--accent-400);
    }

    .event-feed {
      display: grid;
      gap: 16px;
    }

    .event-item {
      border-radius: 16px;
      background: rgba(15, 23, 42, 0.8);
      border: 1px solid rgba(148, 163, 184, 0.12);
      padding: 0;
      overflow: hidden;
    }

    .event-item summary {
      cursor: pointer;
      list-style: none;
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 18px;
      font-weight: 600;
      color: var(--text-primary);
    }

    .event-item summary::-webkit-details-marker {
      display: none;
    }

    .event-item[open] summary {
      background: rgba(56, 189, 248, 0.08);
    }

    .event-title {
      font-size: 1rem;
    }

    .event-time {
      font-size: 0.85rem;
      color: var(--text-secondary);
    }

    .event-item > *:not(summary) {
      padding: 0 18px 18px 18px;
    }

    .event-meta {
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
      margin-top: 10px;
      font-size: 0.85rem;
      color: var(--text-secondary);
    }

    @media (max-width: 1024px) {
      .app-shell {
        flex-direction: column;
      }

      .sidebar {
        flex-direction: row;
        width: 100%;
        align-items: center;
        justify-content: space-between;
        gap: 16px;
      }

      nav {
        flex-direction: row;
      }

      .main {
        padding: 28px;
      }
    }
  </style>
</head>
<body>
  <div class="app-shell">
    <aside class="sidebar">
      <div class="brand">Stem</div>
      <nav>
        ${_renderNav(page)}
      </nav>
      <div class="sidebar-footer">Hotwire preview</div>
    </aside>
    <main class="main">
      ${renderFrame(page, content)}
    </main>
  </div>
  <script type="module">
  const frame = document.getElementById('dashboard-content');

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
    const socket = new WebSocket(`\${protocol}://\${window.location.host}/dash/streams?topic=stem-dashboard:events`);
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

  if (frame) {
    setActive(frame.dataset.page ?? '${page.name}');
    if ((frame.dataset.page ?? '${page.name}') === 'events') {
      ensureEventsStream();
    }
    document.addEventListener('turbo:frame-load', (event) => {
      if (event.target.id !== 'dashboard-content') return;
      const currentPage = event.target.dataset.page ?? '${page.name}';
      setActive(currentPage);
      if (currentPage === 'events') {
        ensureEventsStream();
      }
    });
  }

  document.addEventListener('click', (event) => {
    const row = event.target.closest('[data-queue-row]');
    if (!row) return;
    const queue = row.dataset.queueRow;
    if (!queue) return;
    const detail = document.querySelector(`[data-queue-detail="\${queue}"]`);
    if (!detail) return;
    detail.classList.toggle('visible');
  });
  </script>
</body>
</html>
''';
}

String renderFrame(DashboardPage page, String content) {
  return '''
<turbo-frame id="dashboard-content" data-page="${page.name}">
$content
</turbo-frame>
''';
}

String _renderNav(DashboardPage active) {
  return DashboardPage.values.map((page) => _navLink(page, active)).join('\n');
}

String _navLink(DashboardPage page, DashboardPage active) {
  final isActive = page == active;
  final classes = ['nav-link', if (isActive) 'active'].join(' ');
  final aria = isActive ? ' aria-current="page"' : '';
  return '''
<a href="${page.path}" class="$classes" data-nav="${page.name}" data-turbo-frame="dashboard-content"$aria>
  ${page.label}
</a>
''';
}
