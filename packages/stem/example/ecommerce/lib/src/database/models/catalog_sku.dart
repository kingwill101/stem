import 'package:ormed/ormed.dart';

part 'catalog_sku.orm.dart';

@OrmModel(table: 'catalog_skus')
class CatalogSkuModel extends Model<CatalogSkuModel> with TimestampsTZ {
  const CatalogSkuModel({
    required this.sku,
    required this.title,
    required this.priceCents,
    required this.stockAvailable,
  });

  @OrmField(isPrimaryKey: true)
  final String sku;

  final String title;

  @OrmField(columnName: 'price_cents')
  final int priceCents;

  @OrmField(columnName: 'stock_available')
  final int stockAvailable;
}
