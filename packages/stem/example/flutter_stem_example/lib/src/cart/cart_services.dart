/// Fake commerce backend for the mini-Medusa cart demo.
///
/// Deterministic and in-memory: the workflow steps are the system of record
/// here, mirroring how Medusa steps call module services. One instance is
/// shared by a page and its workflows; [reset] restores opening stock.
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.priceCents,
    required this.stock,
  });

  final String id;
  final String name;
  final int priceCents;
  final int stock;
}

class CartServices {
  CartServices() {
    reset();
  }

  static const catalog = [
    Product(id: 'tee', name: 'Stem Tee', priceCents: 2500, stock: 5),
    Product(id: 'mug', name: 'Workflow Mug', priceCents: 1800, stock: 3),
    Product(id: 'cap', name: 'Isolate Cap', priceCents: 3200, stock: 2),
  ];

  /// Toggles wired to demo switches.
  bool declineCard = false;
  bool emptyStock = false;

  /// SKU -> units currently reserved or on hand.
  final inventory = <String, int>{};

  /// Reservation id -> items held, so compensation can restock exactly.
  final reservations = <String, Map<String, int>>{};

  /// Human-readable traces rendered by the page.
  final stepLog = <String>[];
  final compensationLog = <String>[];
  final charges = <String>[];
  final shipments = <String>[];

  void reset() {
    reservations.clear();
    inventory
      ..clear()
      ..addEntries(catalog.map((p) => MapEntry(p.id, p.stock)));
    stepLog.clear();
    compensationLog.clear();
    charges.clear();
    shipments.clear();
    declineCard = false;
    emptyStock = false;
  }

  Product product(String id) => catalog.firstWhere((p) => p.id == id);

  int totalCents(Map<String, int> items) => items.entries.fold(
    0,
    (sum, e) => sum + product(e.key).priceCents * e.value,
  );
}
