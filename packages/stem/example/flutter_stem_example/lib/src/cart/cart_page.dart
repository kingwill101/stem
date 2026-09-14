import 'package:flutter/material.dart';
import 'package:stem/stem.dart';

import '../demos/workflow_error_card.dart';
import 'cart_services.dart';
import 'cart_workflows.dart';

/// Converts a run-scoped compensation journal snapshot into a user-facing
/// terminal status. A null result means cleanup is still in progress.
String? compensationStatusForJournal(Iterable<WorkflowJournalEntry> entries) {
  final list = entries.toList();
  if (list.isEmpty) return 'Checkout failed; no rollback needed.';
  final states = list.map((entry) => entry.data['state']).toSet();
  if (states.contains('exhausted')) {
    return 'Checkout failed; rollback failed and needs attention.';
  }
  if (states.every((state) => state == 'completed')) {
    return 'Checkout failed and rollback complete.';
  }
  if (!states.every(
    (state) => {'pending', 'waiting', 'running', 'completed'}.contains(state),
  )) {
    return 'Checkout failed; rollback status unavailable.';
  }
  return null;
}

/// Mini-Medusa storefront: a cart checkout workflow with compensation and a
/// reusable fulfillment workflow, mirroring Medusa's steps, rollback, and
/// nested-workflow composition.
///
/// Like [GreetingPage], this screen owns its [WorkflowHost] (or borrows one
/// via [createHost]) and awaits typed `run.result` on the current screen.
class CartPage extends StatefulWidget {
  const CartPage({super.key, this.createHost});

  /// Receives the page's services so the host registers matching workflows.
  /// A borrowed host is never closed here; an owned one is closed on dispose.
  final Future<WorkflowHost> Function(CartServices services)? createHost;

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  final services = CartServices();
  late final CartDemo demo = createCartDemo(services);
  WorkflowHost? _host;
  var _ownsHost = false;
  String? _hostError;

  final _cart = <String, int>{};
  bool _running = false;
  String? _status;
  Map<String, Object?>? _order;
  Object? _runError;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final borrowed = widget.createHost != null;
      final host = borrowed
          ? await widget.createHost!(services)
          : await WorkflowHost.inMemory(
              workflows: [demo.checkoutWorkflow, demo.fulfillOrderWorkflow],
            );
      _ownsHost = !borrowed;
      if (!mounted) {
        if (!borrowed) await host.close();
        return;
      }
      setState(() => _host = host);
    } catch (error) {
      if (!mounted) return;
      setState(() => _hostError = '$error');
    }
  }

  int get _totalCents => services.totalCents(_cart);

  /// Clamped to on-hand stock so normal taps can't over-reserve; the
  /// workflow still guards stock itself for races and stale carts.
  void _add(String id) => setState(() {
    final max = services.product(id).stock;
    final next = (_cart[id] ?? 0) + 1;
    _cart[id] = next > max ? max : next;
  });

  void _remove(String id) => setState(() {
    final qty = (_cart[id] ?? 0) - 1;
    if (qty <= 0) {
      _cart.remove(id);
    } else {
      _cart[id] = qty;
    }
  });

  /// Observes this run's durable compensation journal until cleanup settles.
  ///
  /// A failed run has already committed all compensation registrations before
  /// its terminal failure is published, so an empty journal is authoritative:
  /// the failure happened before any side effect that needed cleanup. The
  /// in-memory service log is deliberately not consulted; it is shared by
  /// runs and is only a display trace.
  Future<String> _awaitCompensation(HostedRun<Map<String, Object?>> run) async {
    for (var i = 0; i < 60; i++) {
      if (!mounted) return 'Checkout failed; rollback status unknown.';
      try {
        final entries = await run.compensations();
        final status = compensationStatusForJournal(entries);
        if (status != null) return status;
        // pending, waiting, and running are all non-terminal cleanup states.
      } on Object {
        return 'Checkout failed; rollback status unavailable.';
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return 'Checkout failed; rollback status unknown.';
  }

  Future<void> _checkout() async {
    final host = _host;
    if (host == null || _running || _cart.isEmpty) return;
    setState(() {
      _running = true;
      _status = 'Running checkout…';
      _order = null;
      _runError = null;
    });
    HostedRun<Map<String, Object?>>? run;
    try {
      run = await host.submit(demo.checkoutWorkflow, {
        'items': Map<String, int>.of(_cart),
      });
      final order = await run.result;
      if (!mounted) return;
      setState(() {
        _order = order;
        _status = 'Order ${order['orderId']} confirmed.';
        _cart.clear();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Checkout failed. Rolling back…');
      // Compensation handlers run asynchronously after the terminal failure;
      // observe their run-specific journal before rendering the final state.
      final failed = run;
      final compensationStatus = failed == null
          ? 'Checkout failed; rollback status unknown.'
          : await _awaitCompensation(failed);
      if (!mounted) return;
      setState(() {
        _runError = error;
        _status = compensationStatus;
      });
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _fulfillAlone() async {
    final host = _host;
    final order = _order;
    if (host == null || _running || order == null) return;
    setState(() {
      _running = true;
      _status = 'Running fulfillment alone…';
      _runError = null;
    });
    try {
      final result = await host.execute(demo.fulfillOrderWorkflow, {
        'orderId': '${order['orderId']}',
        'reservationId': '${order['reservationId']}',
      });
      if (!mounted) return;
      setState(() => _status = 'Fulfilled alone: ${result['trackingId']}.');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _runError = error;
        _status = 'Standalone fulfillment failed.';
      });
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  void dispose() {
    final host = _ownsHost ? _host : null;
    _host = null;
    _ownsHost = false;
    if (host != null) {
      // ignore: discarded_futures
      host.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hostError = _hostError;
    final host = _host;
    return Scaffold(
      appBar: AppBar(title: const Text('Mini Medusa: cart checkout')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (hostError != null)
            Text('Host failed to start: $hostError')
          else if (host == null)
            const Center(child: CircularProgressIndicator())
          else ...[
            const Text(
              'Catalog',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            for (final product in CartServices.catalog)
              ListTile(
                title: Text(product.name),
                subtitle: Text(
                  '${product.priceCents}¢ · ${_cart[product.id] ?? 0} in cart',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove),
                      onPressed: _running ? null : () => _remove(product.id),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed:
                          _running || (_cart[product.id] ?? 0) >= product.stock
                          ? null
                          : () => _add(product.id),
                    ),
                  ],
                ),
              ),
            SwitchListTile(
              title: const Text('Decline card'),
              subtitle: const Text(
                'Fails charge-payment, refunds nothing,'
                ' releases the reservation',
              ),
              value: services.declineCard,
              onChanged: _running
                  ? null
                  : (value) => setState(() => services.declineCard = value),
            ),
            SwitchListTile(
              title: const Text('Empty stock'),
              subtitle: const Text(
                'Fails reserve-inventory before any side effect',
              ),
              value: services.emptyStock,
              onChanged: _running
                  ? null
                  : (value) => setState(() => services.emptyStock = value),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _running || _cart.isEmpty ? null : _checkout,
              child: Text(
                _running
                    ? 'Running…'
                    : 'Checkout $_totalCents¢ (${_cart.values.fold(0, (a, b) => a + b)} items)',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _running || _order == null ? null : _fulfillAlone,
              child: const Text('Run fulfillment workflow alone'),
            ),
            const SizedBox(height: 16),
            if (_running) const Center(child: CircularProgressIndicator()),
            if (_status != null) Text(_status!),
            if (_order != null) ...[
              const SizedBox(height: 8),
              Text(
                'Tracking: ${_order!['trackingId']} · '
                'Charge: ${_order!['chargeId']}',
              ),
            ],
            if (_runError != null) ...[
              const SizedBox(height: 8),
              WorkflowErrorCard(
                title: _status ?? 'Workflow failed.',
                error: _runError!,
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Step log',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            for (final line in services.stepLog) Text('· $line'),
            if (services.compensationLog.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Compensation log',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              for (final line in services.compensationLog) Text('· $line'),
            ],
          ],
        ],
      ),
    );
  }
}
