import 'package:ormed/migrations.dart';

class CreateEcommerceTables extends Migration {
  const CreateEcommerceTables();

  @override
  void up(SchemaBuilder schema) {
    schema
      ..create('catalog_skus', (table) {
        table.text('sku').primaryKey();
        table.text('title');
        table.integer('price_cents');
        table.integer('stock_available');
        table
          ..timestampsTz()
          ..index(['sku'], name: 'catalog_skus_sku_idx');
      })
      ..create('carts', (table) {
        table.text('id').primaryKey();
        table.text('customer_id');
        table.text('status');
        table
          ..timestampsTz()
          ..index(['status'], name: 'carts_status_idx')
          ..index(['customer_id'], name: 'carts_customer_id_idx');
      })
      ..create('cart_items', (table) {
        table.text('id').primaryKey();
        table.text('cart_id');
        table.text('sku');
        table.text('title');
        table.integer('quantity');
        table.integer('unit_price_cents');
        table.integer('line_total_cents');
        table
          ..timestampsTz()
          ..unique(['cart_id', 'sku'], name: 'cart_items_cart_id_sku_unique')
          ..index(['cart_id'], name: 'cart_items_cart_id_idx')
          ..foreign(
            ['cart_id'],
            references: 'carts',
            referencedColumns: ['id'],
            onDelete: ReferenceAction.cascade,
          )
          ..foreign(
            ['sku'],
            references: 'catalog_skus',
            referencedColumns: ['sku'],
            onDelete: ReferenceAction.restrict,
          );
      })
      ..create('orders', (table) {
        table.text('id').primaryKey();
        table.text('cart_id');
        table.text('customer_id');
        table.text('status');
        table.integer('total_cents');
        table.text('payment_reference');
        table
          ..timestampsTz()
          ..index(['cart_id'], name: 'orders_cart_id_idx')
          ..index(['customer_id'], name: 'orders_customer_id_idx')
          ..foreign(
            ['cart_id'],
            references: 'carts',
            referencedColumns: ['id'],
            onDelete: ReferenceAction.restrict,
          );
      })
      ..create('order_items', (table) {
        table.text('id').primaryKey();
        table.text('order_id');
        table.text('sku');
        table.text('title');
        table.integer('quantity');
        table.integer('unit_price_cents');
        table.integer('line_total_cents');
        table
          ..timestampsTz()
          ..index(['order_id'], name: 'order_items_order_id_idx')
          ..foreign(
            ['order_id'],
            references: 'orders',
            referencedColumns: ['id'],
            onDelete: ReferenceAction.cascade,
          );
      });
  }

  @override
  void down(SchemaBuilder schema) {
    schema
      ..drop('order_items', ifExists: true)
      ..drop('orders', ifExists: true)
      ..drop('cart_items', ifExists: true)
      ..drop('carts', ifExists: true)
      ..drop('catalog_skus', ifExists: true);
  }
}
