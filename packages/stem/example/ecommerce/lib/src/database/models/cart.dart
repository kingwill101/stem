import 'package:ormed/ormed.dart';

part 'cart.orm.dart';

@OrmModel(table: 'carts')
class CartModel extends Model<CartModel> with TimestampsTZ {
  const CartModel({
    required this.id,
    required this.customerId,
    required this.status,
  });

  @OrmField(isPrimaryKey: true)
  final String id;

  @OrmField(columnName: 'customer_id')
  final String customerId;

  final String status;
}
