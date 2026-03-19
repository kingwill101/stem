class CatalogSku {
  const CatalogSku({
    required this.sku,
    required this.title,
    required this.priceCents,
    required this.initialStock,
  });

  final String sku;
  final String title;
  final int priceCents;
  final int initialStock;

  Map<String, Object?> toJson() => {
    'sku': sku,
    'title': title,
    'priceCents': priceCents,
    'initialStock': initialStock,
  };
}

const defaultCatalog = <CatalogSku>[
  CatalogSku(
    sku: 'sku_tee',
    title: 'Stem Tee',
    priceCents: 2500,
    initialStock: 250,
  ),
  CatalogSku(
    sku: 'sku_mug',
    title: 'Stem Mug',
    priceCents: 1800,
    initialStock: 150,
  ),
  CatalogSku(
    sku: 'sku_sticker_pack',
    title: 'Sticker Pack',
    priceCents: 700,
    initialStock: 500,
  ),
];

CatalogSku? catalogSkuById(String sku) {
  for (final entry in defaultCatalog) {
    if (entry.sku == sku) {
      return entry;
    }
  }
  return null;
}
