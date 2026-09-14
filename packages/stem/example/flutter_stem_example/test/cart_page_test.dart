import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_stem_example/src/cart/cart_page.dart';
import 'package:flutter_stem_example/src/cart/cart_workflows.dart';
import 'package:stem/stem.dart';

WorkflowJournalEntry _compensationEntry(String state) => WorkflowJournalEntry(
  runId: 'run-1',
  kind: WorkflowJournalKind.compensation,
  name: 'release-reservation',
  revision: 1,
  data: {'state': state},
);

/// Drives the mini-Medusa cart through the widget test fake clock.
///
/// The host lives on fake time (submission and polling advance with pumps)
/// while workflow execution and compensation need real time, so waits
/// alternate `runAsync` slices with pumps. Teardown drains `close()` the same
/// way: shutdown joins worker work spread across both clocks.
class _CartHarness {
  _CartHarness(this.tester);

  final WidgetTester tester;
  WorkflowHost? owned;

  Future<void> pumpPage() async {
    await tester.pumpWidget(
      MaterialApp(
        home: CartPage(
          createHost: (services) async {
            final demo = createCartDemo(services);
            return owned = await WorkflowHost.inMemory(
              workflows: [demo.checkoutWorkflow, demo.fulfillOrderWorkflow],
            );
          },
        ),
      ),
    );
    final checkout = find.textContaining('Checkout');
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (checkout.evaluate().isNotEmpty) break;
    }
    expect(checkout, findsOneWidget);
  }

  Future<void> addFirstProduct({int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pump();
    }
  }

  Future<void> tapCheckout() async {
    await tester.tap(find.byType(FilledButton).first);
    await tester.pump();
  }

  /// Pumps slices until [text] renders or the budget runs out.
  Future<void> waitFor(String text) async {
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (find.textContaining(text).evaluate().isNotEmpty) return;
    }
  }

  /// The result sections sit below the fold in the page's lazy ListView,
  /// so scroll until [text] is built before asserting on it.
  Future<void> scrollTo(String text) async {
    for (var i = 0; i < 10; i++) {
      if (find.textContaining(text).evaluate().isNotEmpty) return;
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();
    }
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
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
  }
}

void main() {
  test('compensation status treats exhausted cleanup as a failure', () {
    expect(
      compensationStatusForJournal(const []),
      'Checkout failed; no rollback needed.',
    );
    expect(
      compensationStatusForJournal([_compensationEntry('completed')]),
      'Checkout failed and rollback complete.',
    );
    expect(
      compensationStatusForJournal([_compensationEntry('exhausted')]),
      'Checkout failed; rollback failed and needs attention.',
    );
    expect(
      compensationStatusForJournal([_compensationEntry('running')]),
      isNull,
    );
  });

  testWidgets('successful checkout shows the order and step log', (
    tester,
  ) async {
    final harness = _CartHarness(tester);
    addTearDown(() {
      final host = harness.owned;
      harness.owned = null;
      if (host != null) host.close();
    });
    await harness.pumpPage();
    await harness.addFirstProduct(times: 2);
    await harness.tapCheckout();
    await harness.waitFor('confirmed');

    expect(find.textContaining('confirmed'), findsOneWidget);
    await harness.scrollTo('Tracking: trk-');
    expect(find.textContaining('Tracking: trk-'), findsOneWidget);
    expect(find.textContaining('validate-cart'), findsOneWidget);
    expect(find.textContaining('charge-payment'), findsOneWidget);
    expect(find.textContaining('ship-parcel'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await harness.close();
  });

  testWidgets('declined card releases the reservation', (tester) async {
    final harness = _CartHarness(tester);
    addTearDown(() {
      final host = harness.owned;
      harness.owned = null;
      if (host != null) host.close();
    });
    await harness.pumpPage();
    await harness.addFirstProduct();
    await tester.tap(find.text('Decline card'));
    await tester.pump();
    await harness.tapCheckout();
    await harness.waitFor('rollback complete');

    expect(find.textContaining('rollback complete'), findsOneWidget);
    // The raw framework error stays behind an expander instead of
    // flooding the screen.
    await harness.scrollTo('Technical details');
    expect(find.text('Technical details'), findsOneWidget);
    expect(find.textContaining('asynchronous suspension'), findsNothing);
    await tester.tap(find.text('Technical details'));
    await tester.pump();
    expect(find.textContaining('asynchronous suspension'), findsOneWidget);
    await harness.scrollTo('Compensation log');
    expect(find.textContaining('release-reservation'), findsOneWidget);
    expect(find.textContaining('refund-payment'), findsNothing);
    expect(tester.takeException(), isNull);
    await harness.close();
  });

  testWidgets('out-of-stock failure reports that no rollback was needed', (
    tester,
  ) async {
    final harness = _CartHarness(tester);
    addTearDown(() {
      final host = harness.owned;
      harness.owned = null;
      if (host != null) host.close();
    });
    await harness.pumpPage();
    await harness.addFirstProduct();
    await tester.tap(find.text('Empty stock'));
    await tester.pump();
    await harness.tapCheckout();
    await harness.waitFor('no rollback needed');

    expect(find.textContaining('no rollback needed'), findsOneWidget);
    await harness.close();
  });

  testWidgets('a prior run compensation log does not affect a later run', (
    tester,
  ) async {
    final harness = _CartHarness(tester);
    addTearDown(() {
      final host = harness.owned;
      harness.owned = null;
      if (host != null) host.close();
    });
    await harness.pumpPage();

    // Seed the shared display log with cleanup from a different run.
    await harness.addFirstProduct();
    await tester.tap(find.text('Decline card'));
    await tester.pump();
    await harness.tapCheckout();
    await harness.waitFor('rollback complete');

    // This run fails before reserve-inventory and has no compensation entries.
    await tester.tap(find.text('Empty stock'));
    await tester.pump();
    await harness.tapCheckout();
    await harness.waitFor('no rollback needed');

    expect(find.textContaining('no rollback needed'), findsOneWidget);
    await harness.close();
  });
}
