import 'package:ormed/ormed.dart';

part 'order.orm.dart';

@OrmModel(table: 'orders')
class OrderModel extends Model<OrderModel> with TimestampsTZ {
  const OrderModel({
    required this.id,
    required this.cartId,
    required this.customerId,
    required this.status,
    required this.totalCents,
    required this.paymentReference,
  });

  @OrmField(isPrimaryKey: true)
  final String id;

  @OrmField(columnName: 'cart_id')
  final String cartId;

  @OrmField(columnName: 'customer_id')
  final String customerId;

  final String status;

  @OrmField(columnName: 'total_cents')
  final int totalCents;

  @OrmField(columnName: 'payment_reference')
  final String paymentReference;
}
