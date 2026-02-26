import 'package:stem_dashboard/src/services/models.dart';
import 'package:stem_dashboard/src/ui/event_templates.dart';
import 'package:stem_dashboard/src/ui/options.dart';
import 'package:stem_dashboard/src/ui/shared.dart';
import 'package:stem_dashboard/src/ui/workers.dart';
import 'package:test/test.dart';

void main() {
  test('buildWorkerRow escapes worker and queue values', () {
    final html = buildWorkerRow(
      WorkerStatus(
        workerId: 'worker<script>alert(1)</script>',
        namespace: 'stem',
        timestamp: DateTime.utc(2026),
        isolateCount: 2,
        inflight: 1,
        queues: const [
          WorkerQueueInfo(name: 'queue" onclick="evil()', inflight: 1),
        ],
      ),
    );

    expect(html, contains('worker&lt;script&gt;alert(1)&lt;/script&gt;'));
    expect(html, contains('queue&quot; onclick=&quot;evil()'));
    expect(html, isNot(contains('worker<script>alert(1)</script>')));
  });

  test('buildWorkersContent escapes namespace filter in empty state', () {
    final html = buildWorkersContent(
      const [],
      const [],
      const WorkersPageOptions(namespaceFilter: '<svg/onload=alert(1)>'),
    );

    expect(html, contains('&lt;svg/onload=alert(1)&gt;'));
    expect(html, isNot(contains('<svg/onload=alert(1)>')));
  });

  test('buildQueueTableRow escapes queue in content and attributes', () {
    final html = buildQueueTableRow(
      const QueueSummary(
        queue: 'alpha" data-pwn="1',
        pending: 1,
        inflight: 0,
        deadLetters: 0,
      ),
    );

    expect(html, contains('data-queue-row="alpha&quot; data-pwn=&quot;1"'));
    expect(
      html,
      contains('<span class="pill">alpha&quot; data-pwn=&quot;1</span>'),
    );
    expect(html, isNot(contains('data-queue-row="alpha" data-pwn="1"')));
  });

  test('renderEventItem escapes title, summary, and metadata values', () {
    final html = renderEventItem(
      DashboardEvent(
        title: '<b>event</b>',
        timestamp: DateTime.utc(2026),
        summary: '<script>alert(1)</script>',
        metadata: const {
          'queue': '<img src=x onerror=alert(1)>',
        },
      ),
    );

    expect(html, contains('&lt;b&gt;event&lt;/b&gt;'));
    expect(html, contains('&lt;script&gt;alert(1)&lt;/script&gt;'));
    expect(html, contains('&lt;img src=x onerror=alert(1)&gt;'));
    expect(html, isNot(contains('<script>alert(1)</script>')));
  });
}
