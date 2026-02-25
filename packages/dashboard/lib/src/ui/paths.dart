/// Normalizes a dashboard base path for route mounting.
String normalizeDashboardBasePath(String basePath) {
  final trimmed = basePath.trim();
  if (trimmed.isEmpty || trimmed == '/') return '';
  final leading = trimmed.startsWith('/') ? trimmed : '/$trimmed';
  return leading.endsWith('/')
      ? leading.substring(0, leading.length - 1)
      : leading;
}

/// Builds a dashboard route by combining [basePath] and [path].
String dashboardRoute(String basePath, String path) {
  final normalizedBasePath = normalizeDashboardBasePath(basePath);
  final normalizedPath = path.startsWith('/') ? path : '/$path';
  if (normalizedBasePath.isEmpty) return normalizedPath;
  if (normalizedPath == '/') return normalizedBasePath;
  return '$normalizedBasePath$normalizedPath';
}

/// Prefixes root-relative HTML URL attributes with [basePath].
String prefixDashboardUrlAttributes(String html, String basePath) {
  final normalizedBasePath = normalizeDashboardBasePath(basePath);
  if (normalizedBasePath.isEmpty) return html;

  return html.replaceAllMapped(
    RegExp(r'''(href|action|value)=("')/(?!/)([^"']*)\2'''),
    (match) {
      final attribute = match.group(1)!;
      final quote = match.group(2)!;
      final remainder = match.group(3)!;
      final path = remainder.isEmpty ? '/' : '/$remainder';
      final resolved = dashboardRoute(normalizedBasePath, path);
      return '$attribute=$quote$resolved$quote';
    },
  );
}
