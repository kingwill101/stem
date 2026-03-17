// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'catalog_sku.dart';

// **************************************************************************
// OrmModelGenerator
// **************************************************************************

const FieldDefinition _$CatalogSkuModelSkuField = FieldDefinition(
  name: 'sku',
  columnName: 'sku',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: true,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$CatalogSkuModelTitleField = FieldDefinition(
  name: 'title',
  columnName: 'title',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$CatalogSkuModelPriceCentsField = FieldDefinition(
  name: 'priceCents',
  columnName: 'price_cents',
  dartType: 'int',
  resolvedType: 'int',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$CatalogSkuModelStockAvailableField = FieldDefinition(
  name: 'stockAvailable',
  columnName: 'stock_available',
  dartType: 'int',
  resolvedType: 'int',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$CatalogSkuModelCreatedAtField = FieldDefinition(
  name: 'createdAt',
  columnName: 'created_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime?',
  isPrimaryKey: false,
  isNullable: true,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$CatalogSkuModelUpdatedAtField = FieldDefinition(
  name: 'updatedAt',
  columnName: 'updated_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime?',
  isPrimaryKey: false,
  isNullable: true,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

Map<String, Object?> _encodeCatalogSkuModelUntracked(
  Object model,
  ValueCodecRegistry registry,
) {
  final m = model as CatalogSkuModel;
  return <String, Object?>{
    'sku': registry.encodeField(_$CatalogSkuModelSkuField, m.sku),
    'title': registry.encodeField(_$CatalogSkuModelTitleField, m.title),
    'price_cents': registry.encodeField(
      _$CatalogSkuModelPriceCentsField,
      m.priceCents,
    ),
    'stock_available': registry.encodeField(
      _$CatalogSkuModelStockAvailableField,
      m.stockAvailable,
    ),
  };
}

final ModelDefinition<$CatalogSkuModel> _$CatalogSkuModelDefinition =
    ModelDefinition(
      modelName: 'CatalogSkuModel',
      tableName: 'catalog_skus',
      fields: const [
        _$CatalogSkuModelSkuField,
        _$CatalogSkuModelTitleField,
        _$CatalogSkuModelPriceCentsField,
        _$CatalogSkuModelStockAvailableField,
        _$CatalogSkuModelCreatedAtField,
        _$CatalogSkuModelUpdatedAtField,
      ],
      relations: const [],
      softDeleteColumn: 'deleted_at',
      metadata: ModelAttributesMetadata(
        hidden: const <String>[],
        visible: const <String>[],
        fillable: const <String>[],
        guarded: const <String>[],
        casts: const <String, String>{},
        appends: const <String>[],
        touches: const <String>[],
        timestamps: true,
        softDeletes: false,
        softDeleteColumn: 'deleted_at',
      ),
      untrackedToMap: _encodeCatalogSkuModelUntracked,
      codec: _$CatalogSkuModelCodec(),
    );

extension CatalogSkuModelOrmDefinition on CatalogSkuModel {
  static ModelDefinition<$CatalogSkuModel> get definition =>
      _$CatalogSkuModelDefinition;
}

class CatalogSkuModels {
  const CatalogSkuModels._();

  /// Starts building a query for [$CatalogSkuModel].
  ///
  /// {@macro ormed.query}
  static Query<$CatalogSkuModel> query([String? connection]) =>
      Model.query<$CatalogSkuModel>(connection: connection);

  static Future<$CatalogSkuModel?> find(Object id, {String? connection}) =>
      Model.find<$CatalogSkuModel>(id, connection: connection);

  static Future<$CatalogSkuModel> findOrFail(Object id, {String? connection}) =>
      Model.findOrFail<$CatalogSkuModel>(id, connection: connection);

  static Future<List<$CatalogSkuModel>> all({String? connection}) =>
      Model.all<$CatalogSkuModel>(connection: connection);

  static Future<int> count({String? connection}) =>
      Model.count<$CatalogSkuModel>(connection: connection);

  static Future<bool> anyExist({String? connection}) =>
      Model.anyExist<$CatalogSkuModel>(connection: connection);

  static Query<$CatalogSkuModel> where(
    String column,
    String operator,
    dynamic value, {
    String? connection,
  }) => Model.where<$CatalogSkuModel>(
    column,
    operator,
    value,
    connection: connection,
  );

  static Query<$CatalogSkuModel> whereIn(
    String column,
    List<dynamic> values, {
    String? connection,
  }) => Model.whereIn<$CatalogSkuModel>(column, values, connection: connection);

  static Query<$CatalogSkuModel> orderBy(
    String column, {
    String direction = "asc",
    String? connection,
  }) => Model.orderBy<$CatalogSkuModel>(
    column,
    direction: direction,
    connection: connection,
  );

  static Query<$CatalogSkuModel> limit(int count, {String? connection}) =>
      Model.limit<$CatalogSkuModel>(count, connection: connection);

  /// Creates a [Repository] for [$CatalogSkuModel].
  ///
  /// {@macro ormed.repository}
  static Repository<$CatalogSkuModel> repo([String? connection]) =>
      Model.repository<$CatalogSkuModel>(connection: connection);

  /// Builds a tracked model from a column/value map.
  static $CatalogSkuModel fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$CatalogSkuModelDefinition.fromMap(data, registry: registry);

  /// Converts a tracked model to a column/value map.
  static Map<String, Object?> toMap(
    $CatalogSkuModel model, {
    ValueCodecRegistry? registry,
  }) => _$CatalogSkuModelDefinition.toMap(model, registry: registry);
}

class CatalogSkuModelFactory {
  const CatalogSkuModelFactory._();

  static ModelDefinition<$CatalogSkuModel> get definition =>
      _$CatalogSkuModelDefinition;

  static ModelCodec<$CatalogSkuModel> get codec => definition.codec;

  static CatalogSkuModel fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => definition.fromMap(data, registry: registry);

  static Map<String, Object?> toMap(
    CatalogSkuModel model, {
    ValueCodecRegistry? registry,
  }) => definition.toMap(model.toTracked(), registry: registry);

  static void registerWith(ModelRegistry registry) =>
      registry.register(definition);

  static ModelFactoryConnection<CatalogSkuModel> withConnection(
    QueryContext context,
  ) => ModelFactoryConnection<CatalogSkuModel>(
    definition: definition,
    context: context,
  );

  static ModelFactoryBuilder<CatalogSkuModel> factory({
    GeneratorProvider? generatorProvider,
  }) => ModelFactoryRegistry.factoryFor<CatalogSkuModel>(
    generatorProvider: generatorProvider,
  );
}

class _$CatalogSkuModelCodec extends ModelCodec<$CatalogSkuModel> {
  const _$CatalogSkuModelCodec();
  @override
  Map<String, Object?> encode(
    $CatalogSkuModel model,
    ValueCodecRegistry registry,
  ) {
    return <String, Object?>{
      'sku': registry.encodeField(_$CatalogSkuModelSkuField, model.sku),
      'title': registry.encodeField(_$CatalogSkuModelTitleField, model.title),
      'price_cents': registry.encodeField(
        _$CatalogSkuModelPriceCentsField,
        model.priceCents,
      ),
      'stock_available': registry.encodeField(
        _$CatalogSkuModelStockAvailableField,
        model.stockAvailable,
      ),
      if (model.hasAttribute('created_at'))
        'created_at': registry.encodeField(
          _$CatalogSkuModelCreatedAtField,
          model.getAttribute<DateTime?>('created_at'),
        ),
      if (model.hasAttribute('updated_at'))
        'updated_at': registry.encodeField(
          _$CatalogSkuModelUpdatedAtField,
          model.getAttribute<DateTime?>('updated_at'),
        ),
    };
  }

  @override
  $CatalogSkuModel decode(
    Map<String, Object?> data,
    ValueCodecRegistry registry,
  ) {
    final String catalogSkuModelSkuValue =
        registry.decodeField<String>(_$CatalogSkuModelSkuField, data['sku']) ??
        (throw StateError('Field sku on CatalogSkuModel cannot be null.'));
    final String catalogSkuModelTitleValue =
        registry.decodeField<String>(
          _$CatalogSkuModelTitleField,
          data['title'],
        ) ??
        (throw StateError('Field title on CatalogSkuModel cannot be null.'));
    final int catalogSkuModelPriceCentsValue =
        registry.decodeField<int>(
          _$CatalogSkuModelPriceCentsField,
          data['price_cents'],
        ) ??
        (throw StateError(
          'Field priceCents on CatalogSkuModel cannot be null.',
        ));
    final int catalogSkuModelStockAvailableValue =
        registry.decodeField<int>(
          _$CatalogSkuModelStockAvailableField,
          data['stock_available'],
        ) ??
        (throw StateError(
          'Field stockAvailable on CatalogSkuModel cannot be null.',
        ));
    final DateTime? catalogSkuModelCreatedAtValue = registry
        .decodeField<DateTime?>(
          _$CatalogSkuModelCreatedAtField,
          data['created_at'],
        );
    final DateTime? catalogSkuModelUpdatedAtValue = registry
        .decodeField<DateTime?>(
          _$CatalogSkuModelUpdatedAtField,
          data['updated_at'],
        );
    final model = $CatalogSkuModel(
      sku: catalogSkuModelSkuValue,
      title: catalogSkuModelTitleValue,
      priceCents: catalogSkuModelPriceCentsValue,
      stockAvailable: catalogSkuModelStockAvailableValue,
    );
    model._attachOrmRuntimeMetadata({
      'sku': catalogSkuModelSkuValue,
      'title': catalogSkuModelTitleValue,
      'price_cents': catalogSkuModelPriceCentsValue,
      'stock_available': catalogSkuModelStockAvailableValue,
      if (data.containsKey('created_at'))
        'created_at': catalogSkuModelCreatedAtValue,
      if (data.containsKey('updated_at'))
        'updated_at': catalogSkuModelUpdatedAtValue,
    });
    return model;
  }
}

/// Insert DTO for [CatalogSkuModel].
///
/// Auto-increment/DB-generated fields are omitted by default.
class CatalogSkuModelInsertDto implements InsertDto<$CatalogSkuModel> {
  const CatalogSkuModelInsertDto({
    this.sku,
    this.title,
    this.priceCents,
    this.stockAvailable,
  });
  final String? sku;
  final String? title;
  final int? priceCents;
  final int? stockAvailable;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (sku != null) 'sku': sku,
      if (title != null) 'title': title,
      if (priceCents != null) 'price_cents': priceCents,
      if (stockAvailable != null) 'stock_available': stockAvailable,
    };
  }

  static const _CatalogSkuModelInsertDtoCopyWithSentinel _copyWithSentinel =
      _CatalogSkuModelInsertDtoCopyWithSentinel();
  CatalogSkuModelInsertDto copyWith({
    Object? sku = _copyWithSentinel,
    Object? title = _copyWithSentinel,
    Object? priceCents = _copyWithSentinel,
    Object? stockAvailable = _copyWithSentinel,
  }) {
    return CatalogSkuModelInsertDto(
      sku: identical(sku, _copyWithSentinel) ? this.sku : sku as String?,
      title: identical(title, _copyWithSentinel)
          ? this.title
          : title as String?,
      priceCents: identical(priceCents, _copyWithSentinel)
          ? this.priceCents
          : priceCents as int?,
      stockAvailable: identical(stockAvailable, _copyWithSentinel)
          ? this.stockAvailable
          : stockAvailable as int?,
    );
  }
}

class _CatalogSkuModelInsertDtoCopyWithSentinel {
  const _CatalogSkuModelInsertDtoCopyWithSentinel();
}

/// Update DTO for [CatalogSkuModel].
///
/// All fields are optional; only provided entries are used in SET clauses.
class CatalogSkuModelUpdateDto implements UpdateDto<$CatalogSkuModel> {
  const CatalogSkuModelUpdateDto({
    this.sku,
    this.title,
    this.priceCents,
    this.stockAvailable,
  });
  final String? sku;
  final String? title;
  final int? priceCents;
  final int? stockAvailable;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (sku != null) 'sku': sku,
      if (title != null) 'title': title,
      if (priceCents != null) 'price_cents': priceCents,
      if (stockAvailable != null) 'stock_available': stockAvailable,
    };
  }

  static const _CatalogSkuModelUpdateDtoCopyWithSentinel _copyWithSentinel =
      _CatalogSkuModelUpdateDtoCopyWithSentinel();
  CatalogSkuModelUpdateDto copyWith({
    Object? sku = _copyWithSentinel,
    Object? title = _copyWithSentinel,
    Object? priceCents = _copyWithSentinel,
    Object? stockAvailable = _copyWithSentinel,
  }) {
    return CatalogSkuModelUpdateDto(
      sku: identical(sku, _copyWithSentinel) ? this.sku : sku as String?,
      title: identical(title, _copyWithSentinel)
          ? this.title
          : title as String?,
      priceCents: identical(priceCents, _copyWithSentinel)
          ? this.priceCents
          : priceCents as int?,
      stockAvailable: identical(stockAvailable, _copyWithSentinel)
          ? this.stockAvailable
          : stockAvailable as int?,
    );
  }
}

class _CatalogSkuModelUpdateDtoCopyWithSentinel {
  const _CatalogSkuModelUpdateDtoCopyWithSentinel();
}

/// Partial projection for [CatalogSkuModel].
///
/// All fields are nullable; intended for subset SELECTs.
class CatalogSkuModelPartial implements PartialEntity<$CatalogSkuModel> {
  const CatalogSkuModelPartial({
    this.sku,
    this.title,
    this.priceCents,
    this.stockAvailable,
  });

  /// Creates a partial from a database row map.
  ///
  /// The [row] keys should be column names (snake_case).
  /// Missing columns will result in null field values.
  factory CatalogSkuModelPartial.fromRow(Map<String, Object?> row) {
    return CatalogSkuModelPartial(
      sku: row['sku'] as String?,
      title: row['title'] as String?,
      priceCents: row['price_cents'] as int?,
      stockAvailable: row['stock_available'] as int?,
    );
  }

  final String? sku;
  final String? title;
  final int? priceCents;
  final int? stockAvailable;

  @override
  $CatalogSkuModel toEntity() {
    // Basic required-field check: non-nullable fields must be present.
    final String? skuValue = sku;
    if (skuValue == null) {
      throw StateError('Missing required field: sku');
    }
    final String? titleValue = title;
    if (titleValue == null) {
      throw StateError('Missing required field: title');
    }
    final int? priceCentsValue = priceCents;
    if (priceCentsValue == null) {
      throw StateError('Missing required field: priceCents');
    }
    final int? stockAvailableValue = stockAvailable;
    if (stockAvailableValue == null) {
      throw StateError('Missing required field: stockAvailable');
    }
    return $CatalogSkuModel(
      sku: skuValue,
      title: titleValue,
      priceCents: priceCentsValue,
      stockAvailable: stockAvailableValue,
    );
  }

  @override
  Map<String, Object?> toMap() {
    return {
      if (sku != null) 'sku': sku,
      if (title != null) 'title': title,
      if (priceCents != null) 'price_cents': priceCents,
      if (stockAvailable != null) 'stock_available': stockAvailable,
    };
  }

  static const _CatalogSkuModelPartialCopyWithSentinel _copyWithSentinel =
      _CatalogSkuModelPartialCopyWithSentinel();
  CatalogSkuModelPartial copyWith({
    Object? sku = _copyWithSentinel,
    Object? title = _copyWithSentinel,
    Object? priceCents = _copyWithSentinel,
    Object? stockAvailable = _copyWithSentinel,
  }) {
    return CatalogSkuModelPartial(
      sku: identical(sku, _copyWithSentinel) ? this.sku : sku as String?,
      title: identical(title, _copyWithSentinel)
          ? this.title
          : title as String?,
      priceCents: identical(priceCents, _copyWithSentinel)
          ? this.priceCents
          : priceCents as int?,
      stockAvailable: identical(stockAvailable, _copyWithSentinel)
          ? this.stockAvailable
          : stockAvailable as int?,
    );
  }
}

class _CatalogSkuModelPartialCopyWithSentinel {
  const _CatalogSkuModelPartialCopyWithSentinel();
}

/// Generated tracked model class for [CatalogSkuModel].
///
/// This class extends the user-defined [CatalogSkuModel] model and adds
/// attribute tracking, change detection, and relationship management.
/// Instances of this class are returned by queries and repositories.
///
/// **Do not instantiate this class directly.** Use queries, repositories,
/// or model factories to create tracked model instances.
class $CatalogSkuModel extends CatalogSkuModel
    with ModelAttributes, TimestampsTZImpl
    implements OrmEntity {
  /// Internal constructor for [$CatalogSkuModel].
  $CatalogSkuModel({
    required String sku,
    required String title,
    required int priceCents,
    required int stockAvailable,
  }) : super(
         sku: sku,
         title: title,
         priceCents: priceCents,
         stockAvailable: stockAvailable,
       ) {
    _attachOrmRuntimeMetadata({
      'sku': sku,
      'title': title,
      'price_cents': priceCents,
      'stock_available': stockAvailable,
    });
  }

  /// Creates a tracked model instance from a user-defined model instance.
  factory $CatalogSkuModel.fromModel(CatalogSkuModel model) {
    return $CatalogSkuModel(
      sku: model.sku,
      title: model.title,
      priceCents: model.priceCents,
      stockAvailable: model.stockAvailable,
    );
  }

  $CatalogSkuModel copyWith({
    String? sku,
    String? title,
    int? priceCents,
    int? stockAvailable,
  }) {
    return $CatalogSkuModel(
      sku: sku ?? this.sku,
      title: title ?? this.title,
      priceCents: priceCents ?? this.priceCents,
      stockAvailable: stockAvailable ?? this.stockAvailable,
    );
  }

  /// Builds a tracked model from a column/value map.
  static $CatalogSkuModel fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$CatalogSkuModelDefinition.fromMap(data, registry: registry);

  /// Converts this tracked model to a column/value map.
  Map<String, Object?> toMap({ValueCodecRegistry? registry}) =>
      _$CatalogSkuModelDefinition.toMap(this, registry: registry);

  /// Tracked getter for [sku].
  @override
  String get sku => getAttribute<String>('sku') ?? super.sku;

  /// Tracked setter for [sku].
  set sku(String value) => setAttribute('sku', value);

  /// Tracked getter for [title].
  @override
  String get title => getAttribute<String>('title') ?? super.title;

  /// Tracked setter for [title].
  set title(String value) => setAttribute('title', value);

  /// Tracked getter for [priceCents].
  @override
  int get priceCents => getAttribute<int>('price_cents') ?? super.priceCents;

  /// Tracked setter for [priceCents].
  set priceCents(int value) => setAttribute('price_cents', value);

  /// Tracked getter for [stockAvailable].
  @override
  int get stockAvailable =>
      getAttribute<int>('stock_available') ?? super.stockAvailable;

  /// Tracked setter for [stockAvailable].
  set stockAvailable(int value) => setAttribute('stock_available', value);

  void _attachOrmRuntimeMetadata(Map<String, Object?> values) {
    replaceAttributes(values);
    attachModelDefinition(_$CatalogSkuModelDefinition);
  }
}

class _CatalogSkuModelCopyWithSentinel {
  const _CatalogSkuModelCopyWithSentinel();
}

extension CatalogSkuModelOrmExtension on CatalogSkuModel {
  static const _CatalogSkuModelCopyWithSentinel _copyWithSentinel =
      _CatalogSkuModelCopyWithSentinel();
  CatalogSkuModel copyWith({
    Object? sku = _copyWithSentinel,
    Object? title = _copyWithSentinel,
    Object? priceCents = _copyWithSentinel,
    Object? stockAvailable = _copyWithSentinel,
  }) {
    return CatalogSkuModel(
      sku: identical(sku, _copyWithSentinel) ? this.sku : sku as String,
      title: identical(title, _copyWithSentinel) ? this.title : title as String,
      priceCents: identical(priceCents, _copyWithSentinel)
          ? this.priceCents
          : priceCents as int,
      stockAvailable: identical(stockAvailable, _copyWithSentinel)
          ? this.stockAvailable
          : stockAvailable as int,
    );
  }

  /// Converts this model to a column/value map.
  Map<String, Object?> toMap({ValueCodecRegistry? registry}) =>
      _$CatalogSkuModelDefinition.toMap(this, registry: registry);

  /// Builds a model from a column/value map.
  static CatalogSkuModel fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$CatalogSkuModelDefinition.fromMap(data, registry: registry);

  /// The Type of the generated ORM-managed model class.
  /// Use this when you need to specify the tracked model type explicitly,
  /// for example in generic type parameters.
  static Type get trackedType => $CatalogSkuModel;

  /// Converts this immutable model to a tracked ORM-managed model.
  /// The tracked model supports attribute tracking, change detection,
  /// and persistence operations like save() and touch().
  $CatalogSkuModel toTracked() {
    return $CatalogSkuModel.fromModel(this);
  }
}

extension CatalogSkuModelPredicateFields on PredicateBuilder<CatalogSkuModel> {
  PredicateField<CatalogSkuModel, String> get sku =>
      PredicateField<CatalogSkuModel, String>(this, 'sku');
  PredicateField<CatalogSkuModel, String> get title =>
      PredicateField<CatalogSkuModel, String>(this, 'title');
  PredicateField<CatalogSkuModel, int> get priceCents =>
      PredicateField<CatalogSkuModel, int>(this, 'priceCents');
  PredicateField<CatalogSkuModel, int> get stockAvailable =>
      PredicateField<CatalogSkuModel, int>(this, 'stockAvailable');
}

void registerCatalogSkuModelEventHandlers(EventBus bus) {
  // No event handlers registered for CatalogSkuModel.
}
