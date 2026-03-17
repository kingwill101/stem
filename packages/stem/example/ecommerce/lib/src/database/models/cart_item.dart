import 'package:ormed/ormed.dart';

part 'cart_item.orm.dart';

@OrmModel(table: 'cart_items')
class CartItemModel extends Model<CartItemModel> with TimestampsTZ {
  const CartItemModel({
    required this.id,
    required this.cartId,
    required this.sku,
    required this.title,
    required this.quantity,
    required this.unitPriceCents,
    required this.lineTotalCents,
  });

  @OrmField(isPrimaryKey: true)
  final String id;

  @OrmField(columnName: 'cart_id')
  final String cartId;

  final String sku;

  final String title;

  final int quantity;

  @OrmField(columnName: 'unit_price_cents')
  final int unitPriceCents;

  @OrmField(columnName: 'line_total_cents')
  final int lineTotalCents;
}
