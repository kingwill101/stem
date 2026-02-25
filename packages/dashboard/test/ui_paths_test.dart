import 'package:stem_dashboard/src/ui/paths.dart';
import 'package:test/test.dart';

void main() {
  test(
    'prefixes root-relative url attributes while preserving quote style',
    () {
      const html =
          '<a href="/tasks">Tasks</a> '
          "<form action='/workers'></form> "
          '<input value="/search?q=alpha" />';

      final prefixed = prefixDashboardUrlAttributes(html, '/dashboard');

      expect(prefixed, contains('href="/dashboard/tasks"'));
      expect(prefixed, contains("action='/dashboard/workers'"));
      expect(prefixed, contains('value="/dashboard/search?q=alpha"'));
    },
  );

  test('does not rewrite protocol-relative urls', () {
    const html =
        '<a href="//cdn.example.com/app.js">CDN</a> '
        '<form action="/workers"></form>';

    final prefixed = prefixDashboardUrlAttributes(html, '/dashboard');

    expect(prefixed, contains('href="//cdn.example.com/app.js"'));
    expect(prefixed, contains('action="/dashboard/workers"'));
  });
}
