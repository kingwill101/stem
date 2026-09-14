import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_stem_example/src/greeting_page.dart';
import 'package:flutter_stem_example/src/greeting_workflow.dart';
import 'package:stem/stem.dart';

void main() {
  testWidgets('button submits the workflow and shows its result', (
    tester,
  ) async {
    // The test owns the host so it can await shutdown after the page
    // is removed; the page borrows it and leaves teardown to us. The host
    // is created on the test's fake clock (like the Stem apps in
    // widget_test.dart) so submission and result polling advance with pumps.
    WorkflowHost? owned;
    // Best-effort cleanup if the body fails early; the body itself drains
    // close with pumps, which teardown can no longer do.
    addTearDown(() {
      final host = owned;
      owned = null;
      if (host != null) host.close();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: GreetingPage(
          createHost: () async => owned = await WorkflowHost.inMemory(
            workflows: [greetingWorkflow],
          ),
        ),
      ),
    );
    // The host owns background timers, so settle manually instead of
    // pumpAndSettle (which would wait on its clock forever). The button
    // renders disabled before the host is ready, so wait for it to enable.
    final greetButton = find.widgetWithText(FilledButton, 'Greet me');
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (tester.widget<FilledButton>(greetButton).enabled) break;
    }
    expect(find.widgetWithText(FilledButton, 'Greet me'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Ada');
    await tester.tap(find.widgetWithText(FilledButton, 'Greet me'));
    await tester.pump();
    // The host runs on real timers and the greeting finishes on a real
    // isolate, so alternate real-time slices (workflow progress) with pumps
    // (frame rebuild + fake-clock advance) until the result renders.
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (find.textContaining('Hello, Ada!').evaluate().isNotEmpty) break;
    }

    expect(find.textContaining('Hello, Ada!'), findsOneWidget);
    expect(find.textContaining('from '), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    // Close on the fake clock: close() joins worker shutdown, whose timers
    // only advance with pumps. Awaiting it under runAsync would stall them.
    final host = owned!;
    owned = null;
    var closed = false;
    host.close().then((_) => closed = true);
    for (var i = 0; i < 200 && !closed; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(closed, isTrue, reason: 'Host must shut down cleanly.');
  });
}
