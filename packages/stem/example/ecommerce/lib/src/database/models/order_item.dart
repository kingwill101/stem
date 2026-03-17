import 'package:ormed/ormed.dart';

part 'order_item.orm.dart';

@OrmModel(table: 'order_items')
class OrderItemModel extends Model<OrderItemModel> with TimestampsTZ {
  const OrderItemModel({
    required this.id,
    required this.orderId,
    required this.sku,
    required this.title,
    required this.quantity,
    required this.unitPriceCents,
    required this.lineTotalCents,
  });

  @OrmField(isPrimaryKey: true)
  final String id;

  @OrmField(columnName: 'order_id')
  final String orderId;

  final String sku;

  final String title;

  final int quantity;

  @OrmField(columnName: 'unit_price_cents')
  final int unitPriceCents;

  @OrmField(columnName: 'line_total_cents')
  final int lineTotalCents;
}
