// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'order_item.dart';

// **************************************************************************
// OrmModelGenerator
// **************************************************************************

const FieldDefinition _$OrderItemModelIdField = FieldDefinition(
  name: 'id',
  columnName: 'id',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: true,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$OrderItemModelOrderIdField = FieldDefinition(
  name: 'orderId',
  columnName: 'order_id',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$OrderItemModelSkuField = FieldDefinition(
  name: 'sku',
  columnName: 'sku',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$OrderItemModelTitleField = FieldDefinition(
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

const FieldDefinition _$OrderItemModelQuantityField = FieldDefinition(
  name: 'quantity',
  columnName: 'quantity',
  dartType: 'int',
  resolvedType: 'int',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$OrderItemModelUnitPriceCentsField = FieldDefinition(
  name: 'unitPriceCents',
  columnName: 'unit_price_cents',
  dartType: 'int',
  resolvedType: 'int',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$OrderItemModelLineTotalCentsField = FieldDefinition(
  name: 'lineTotalCents',
  columnName: 'line_total_cents',
  dartType: 'int',
  resolvedType: 'int',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$OrderItemModelCreatedAtField = FieldDefinition(
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

const FieldDefinition _$OrderItemModelUpdatedAtField = FieldDefinition(
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

Map<String, Object?> _encodeOrderItemModelUntracked(
  Object model,
  ValueCodecRegistry registry,
) {
  final m = model as OrderItemModel;
  return <String, Object?>{
    'id': registry.encodeField(_$OrderItemModelIdField, m.id),
    'order_id': registry.encodeField(_$OrderItemModelOrderIdField, m.orderId),
    'sku': registry.encodeField(_$OrderItemModelSkuField, m.sku),
    'title': registry.encodeField(_$OrderItemModelTitleField, m.title),
    'quantity': registry.encodeField(_$OrderItemModelQuantityField, m.quantity),
    'unit_price_cents': registry.encodeField(
      _$OrderItemModelUnitPriceCentsField,
      m.unitPriceCents,
    ),
    'line_total_cents': registry.encodeField(
      _$OrderItemModelLineTotalCentsField,
      m.lineTotalCents,
    ),
  };
}

final ModelDefinition<$OrderItemModel> _$OrderItemModelDefinition =
    ModelDefinition(
      modelName: 'OrderItemModel',
      tableName: 'order_items',
      fields: const [
        _$OrderItemModelIdField,
        _$OrderItemModelOrderIdField,
        _$OrderItemModelSkuField,
        _$OrderItemModelTitleField,
        _$OrderItemModelQuantityField,
        _$OrderItemModelUnitPriceCentsField,
        _$OrderItemModelLineTotalCentsField,
        _$OrderItemModelCreatedAtField,
        _$OrderItemModelUpdatedAtField,
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
      untrackedToMap: _encodeOrderItemModelUntracked,
      codec: _$OrderItemModelCodec(),
    );

extension OrderItemModelOrmDefinition on OrderItemModel {
  static ModelDefinition<$OrderItemModel> get definition =>
      _$OrderItemModelDefinition;
}

class OrderItemModels {
  const OrderItemModels._();

  /// Starts building a query for [$OrderItemModel].
  ///
  /// {@macro ormed.query}
  static Query<$OrderItemModel> query([String? connection]) =>
      Model.query<$OrderItemModel>(connection: connection);

  static Future<$OrderItemModel?> find(Object id, {String? connection}) =>
      Model.find<$OrderItemModel>(id, connection: connection);

  static Future<$OrderItemModel> findOrFail(Object id, {String? connection}) =>
      Model.findOrFail<$OrderItemModel>(id, connection: connection);

  static Future<List<$OrderItemModel>> all({String? connection}) =>
      Model.all<$OrderItemModel>(connection: connection);

  static Future<int> count({String? connection}) =>
      Model.count<$OrderItemModel>(connection: connection);

  static Future<bool> anyExist({String? connection}) =>
      Model.anyExist<$OrderItemModel>(connection: connection);

  static Query<$OrderItemModel> where(
    String column,
    String operator,
    dynamic value, {
    String? connection,
  }) => Model.where<$OrderItemModel>(
    column,
    operator,
    value,
    connection: connection,
  );

  static Query<$OrderItemModel> whereIn(
    String column,
    List<dynamic> values, {
    String? connection,
  }) => Model.whereIn<$OrderItemModel>(column, values, connection: connection);

  static Query<$OrderItemModel> orderBy(
    String column, {
    String direction = "asc",
    String? connection,
  }) => Model.orderBy<$OrderItemModel>(
    column,
    direction: direction,
    connection: connection,
  );

  static Query<$OrderItemModel> limit(int count, {String? connection}) =>
      Model.limit<$OrderItemModel>(count, connection: connection);

  /// Creates a [Repository] for [$OrderItemModel].
  ///
  /// {@macro ormed.repository}
  static Repository<$OrderItemModel> repo([String? connection]) =>
      Model.repository<$OrderItemModel>(connection: connection);

  /// Builds a tracked model from a column/value map.
  static $OrderItemModel fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$OrderItemModelDefinition.fromMap(data, registry: registry);

  /// Converts a tracked model to a column/value map.
  static Map<String, Object?> toMap(
    $OrderItemModel model, {
    ValueCodecRegistry? registry,
  }) => _$OrderItemModelDefinition.toMap(model, registry: registry);
}

class OrderItemModelFactory {
  const OrderItemModelFactory._();

  static ModelDefinition<$OrderItemModel> get definition =>
      _$OrderItemModelDefinition;

  static ModelCodec<$OrderItemModel> get codec => definition.codec;

  static OrderItemModel fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => definition.fromMap(data, registry: registry);

  static Map<String, Object?> toMap(
    OrderItemModel model, {
    ValueCodecRegistry? registry,
  }) => definition.toMap(model.toTracked(), registry: registry);

  static void registerWith(ModelRegistry registry) =>
      registry.register(definition);

  static ModelFactoryConnection<OrderItemModel> withConnection(
    QueryContext context,
  ) => ModelFactoryConnection<OrderItemModel>(
    definition: definition,
    context: context,
  );

  static ModelFactoryBuilder<OrderItemModel> factory({
    GeneratorProvider? generatorProvider,
  }) => ModelFactoryRegistry.factoryFor<OrderItemModel>(
    generatorProvider: generatorProvider,
  );
}

class _$OrderItemModelCodec extends ModelCodec<$OrderItemModel> {
  const _$OrderItemModelCodec();
  @override
  Map<String, Object?> encode(
    $OrderItemModel model,
    ValueCodecRegistry registry,
  ) {
    return <String, Object?>{
      'id': registry.encodeField(_$OrderItemModelIdField, model.id),
      'order_id': registry.encodeField(
        _$OrderItemModelOrderIdField,
        model.orderId,
      ),
      'sku': registry.encodeField(_$OrderItemModelSkuField, model.sku),
      'title': registry.encodeField(_$OrderItemModelTitleField, model.title),
      'quantity': registry.encodeField(
        _$OrderItemModelQuantityField,
        model.quantity,
      ),
      'unit_price_cents': registry.encodeField(
        _$OrderItemModelUnitPriceCentsField,
        model.unitPriceCents,
      ),
      'line_total_cents': registry.encodeField(
        _$OrderItemModelLineTotalCentsField,
        model.lineTotalCents,
      ),
      if (model.hasAttribute('created_at'))
        'created_at': registry.encodeField(
          _$OrderItemModelCreatedAtField,
          model.getAttribute<DateTime?>('created_at'),
        ),
      if (model.hasAttribute('updated_at'))
        'updated_at': registry.encodeField(
          _$OrderItemModelUpdatedAtField,
          model.getAttribute<DateTime?>('updated_at'),
        ),
    };
  }

  @override
  $OrderItemModel decode(
    Map<String, Object?> data,
    ValueCodecRegistry registry,
  ) {
    final String orderItemModelIdValue =
        registry.decodeField<String>(_$OrderItemModelIdField, data['id']) ??
        (throw StateError('Field id on OrderItemModel cannot be null.'));
    final String orderItemModelOrderIdValue =
        registry.decodeField<String>(
          _$OrderItemModelOrderIdField,
          data['order_id'],
        ) ??
        (throw StateError('Field orderId on OrderItemModel cannot be null.'));
    final String orderItemModelSkuValue =
        registry.decodeField<String>(_$OrderItemModelSkuField, data['sku']) ??
        (throw StateError('Field sku on OrderItemModel cannot be null.'));
    final String orderItemModelTitleValue =
        registry.decodeField<String>(
          _$OrderItemModelTitleField,
          data['title'],
        ) ??
        (throw StateError('Field title on OrderItemModel cannot be null.'));
    final int orderItemModelQuantityValue =
        registry.decodeField<int>(
          _$OrderItemModelQuantityField,
          data['quantity'],
        ) ??
        (throw StateError('Field quantity on OrderItemModel cannot be null.'));
    final int orderItemModelUnitPriceCentsValue =
        registry.decodeField<int>(
          _$OrderItemModelUnitPriceCentsField,
          data['unit_price_cents'],
        ) ??
        (throw StateError(
          'Field unitPriceCents on OrderItemModel cannot be null.',
        ));
    final int orderItemModelLineTotalCentsValue =
        registry.decodeField<int>(
          _$OrderItemModelLineTotalCentsField,
          data['line_total_cents'],
        ) ??
        (throw StateError(
          'Field lineTotalCents on OrderItemModel cannot be null.',
        ));
    final DateTime? orderItemModelCreatedAtValue = registry
        .decodeField<DateTime?>(
          _$OrderItemModelCreatedAtField,
          data['created_at'],
        );
    final DateTime? orderItemModelUpdatedAtValue = registry
        .decodeField<DateTime?>(
          _$OrderItemModelUpdatedAtField,
          data['updated_at'],
        );
    final model = $OrderItemModel(
      id: orderItemModelIdValue,
      orderId: orderItemModelOrderIdValue,
      sku: orderItemModelSkuValue,
      title: orderItemModelTitleValue,
      quantity: orderItemModelQuantityValue,
      unitPriceCents: orderItemModelUnitPriceCentsValue,
      lineTotalCents: orderItemModelLineTotalCentsValue,
    );
    model._attachOrmRuntimeMetadata({
      'id': orderItemModelIdValue,
      'order_id': orderItemModelOrderIdValue,
      'sku': orderItemModelSkuValue,
      'title': orderItemModelTitleValue,
      'quantity': orderItemModelQuantityValue,
      'unit_price_cents': orderItemModelUnitPriceCentsValue,
      'line_total_cents': orderItemModelLineTotalCentsValue,
      if (data.containsKey('created_at'))
        'created_at': orderItemModelCreatedAtValue,
      if (data.containsKey('updated_at'))
        'updated_at': orderItemModelUpdatedAtValue,
    });
    return model;
  }
}

/// Insert DTO for [OrderItemModel].
///
/// Auto-increment/DB-generated fields are omitted by default.
class OrderItemModelInsertDto implements InsertDto<$OrderItemModel> {
  const OrderItemModelInsertDto({
    this.id,
    this.orderId,
    this.sku,
    this.title,
    this.quantity,
    this.unitPriceCents,
    this.lineTotalCents,
  });
  final String? id;
  final String? orderId;
  final String? sku;
  final String? title;
  final int? quantity;
  final int? unitPriceCents;
  final int? lineTotalCents;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      if (orderId != null) 'order_id': orderId,
      if (sku != null) 'sku': sku,
      if (title != null) 'title': title,
      if (quantity != null) 'quantity': quantity,
      if (unitPriceCents != null) 'unit_price_cents': unitPriceCents,
      if (lineTotalCents != null) 'line_total_cents': lineTotalCents,
    };
  }

  static const _OrderItemModelInsertDtoCopyWithSentinel _copyWithSentinel =
      _OrderItemModelInsertDtoCopyWithSentinel();
  OrderItemModelInsertDto copyWith({
    Object? id = _copyWithSentinel,
    Object? orderId = _copyWithSentinel,
    Object? sku = _copyWithSentinel,
    Object? title = _copyWithSentinel,
    Object? quantity = _copyWithSentinel,
    Object? unitPriceCents = _copyWithSentinel,
    Object? lineTotalCents = _copyWithSentinel,
  }) {
    return OrderItemModelInsertDto(
      id: identical(id, _copyWithSentinel) ? this.id : id as String?,
      orderId: identical(orderId, _copyWithSentinel)
          ? this.orderId
          : orderId as String?,
      sku: identical(sku, _copyWithSentinel) ? this.sku : sku as String?,
      title: identical(title, _copyWithSentinel)
          ? this.title
          : title as String?,
      quantity: identical(quantity, _copyWithSentinel)
          ? this.quantity
          : quantity as int?,
      unitPriceCents: identical(unitPriceCents, _copyWithSentinel)
          ? this.unitPriceCents
          : unitPriceCents as int?,
      lineTotalCents: identical(lineTotalCents, _copyWithSentinel)
          ? this.lineTotalCents
          : lineTotalCents as int?,
    );
  }
}

class _OrderItemModelInsertDtoCopyWithSentinel {
  const _OrderItemModelInsertDtoCopyWithSentinel();
}

/// Update DTO for [OrderItemModel].
///
/// All fields are optional; only provided entries are used in SET clauses.
class OrderItemModelUpdateDto implements UpdateDto<$OrderItemModel> {
  const OrderItemModelUpdateDto({
    this.id,
    this.orderId,
    this.sku,
    this.title,
    this.quantity,
    this.unitPriceCents,
    this.lineTotalCents,
  });
  final String? id;
  final String? orderId;
  final String? sku;
  final String? title;
  final int? quantity;
  final int? unitPriceCents;
  final int? lineTotalCents;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      if (orderId != null) 'order_id': orderId,
      if (sku != null) 'sku': sku,
      if (title != null) 'title': title,
      if (quantity != null) 'quantity': quantity,
      if (unitPriceCents != null) 'unit_price_cents': unitPriceCents,
      if (lineTotalCents != null) 'line_total_cents': lineTotalCents,
    };
  }

  static const _OrderItemModelUpdateDtoCopyWithSentinel _copyWithSentinel =
      _OrderItemModelUpdateDtoCopyWithSentinel();
  OrderItemModelUpdateDto copyWith({
    Object? id = _copyWithSentinel,
    Object? orderId = _copyWithSentinel,
    Object? sku = _copyWithSentinel,
    Object? title = _copyWithSentinel,
    Object? quantity = _copyWithSentinel,
    Object? unitPriceCents = _copyWithSentinel,
    Object? lineTotalCents = _copyWithSentinel,
  }) {
    return OrderItemModelUpdateDto(
      id: identical(id, _copyWithSentinel) ? this.id : id as String?,
      orderId: identical(orderId, _copyWithSentinel)
          ? this.orderId
          : orderId as String?,
      sku: identical(sku, _copyWithSentinel) ? this.sku : sku as String?,
      title: identical(title, _copyWithSentinel)
          ? this.title
          : title as String?,
      quantity: identical(quantity, _copyWithSentinel)
          ? this.quantity
          : quantity as int?,
      unitPriceCents: identical(unitPriceCents, _copyWithSentinel)
          ? this.unitPriceCents
          : unitPriceCents as int?,
      lineTotalCents: identical(lineTotalCents, _copyWithSentinel)
          ? this.lineTotalCents
          : lineTotalCents as int?,
    );
  }
}

class _OrderItemModelUpdateDtoCopyWithSentinel {
  const _OrderItemModelUpdateDtoCopyWithSentinel();
}

/// Partial projection for [OrderItemModel].
///
/// All fields are nullable; intended for subset SELECTs.
class OrderItemModelPartial implements PartialEntity<$OrderItemModel> {
  const OrderItemModelPartial({
    this.id,
    this.orderId,
    this.sku,
    this.title,
    this.quantity,
    this.unitPriceCents,
    this.lineTotalCents,
  });

  /// Creates a partial from a database row map.
  ///
  /// The [row] keys should be column names (snake_case).
  /// Missing columns will result in null field values.
  factory OrderItemModelPartial.fromRow(Map<String, Object?> row) {
    return OrderItemModelPartial(
      id: row['id'] as String?,
      orderId: row['order_id'] as String?,
      sku: row['sku'] as String?,
      title: row['title'] as String?,
      quantity: row['quantity'] as int?,
      unitPriceCents: row['unit_price_cents'] as int?,
      lineTotalCents: row['line_total_cents'] as int?,
    );
  }

  final String? id;
  final String? orderId;
  final String? sku;
  final String? title;
  final int? quantity;
  final int? unitPriceCents;
  final int? lineTotalCents;

  @override
  $OrderItemModel toEntity() {
    // Basic required-field check: non-nullable fields must be present.
    final String? idValue = id;
    if (idValue == null) {
      throw StateError('Missing required field: id');
    }
    final String? orderIdValue = orderId;
    if (orderIdValue == null) {
      throw StateError('Missing required field: orderId');
    }
    final String? skuValue = sku;
    if (skuValue == null) {
      throw StateError('Missing required field: sku');
    }
    final String? titleValue = title;
    if (titleValue == null) {
      throw StateError('Missing required field: title');
    }
    final int? quantityValue = quantity;
    if (quantityValue == null) {
      throw StateError('Missing required field: quantity');
    }
    final int? unitPriceCentsValue = unitPriceCents;
    if (unitPriceCentsValue == null) {
      throw StateError('Missing required field: unitPriceCents');
    }
    final int? lineTotalCentsValue = lineTotalCents;
    if (lineTotalCentsValue == null) {
      throw StateError('Missing required field: lineTotalCents');
    }
    return $OrderItemModel(
      id: idValue,
      orderId: orderIdValue,
      sku: skuValue,
      title: titleValue,
      quantity: quantityValue,
      unitPriceCents: unitPriceCentsValue,
      lineTotalCents: lineTotalCentsValue,
    );
  }

  @override
  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      if (orderId != null) 'order_id': orderId,
      if (sku != null) 'sku': sku,
      if (title != null) 'title': title,
      if (quantity != null) 'quantity': quantity,
      if (unitPriceCents != null) 'unit_price_cents': unitPriceCents,
      if (lineTotalCents != null) 'line_total_cents': lineTotalCents,
    };
  }

  static const _OrderItemModelPartialCopyWithSentinel _copyWithSentinel =
      _OrderItemModelPartialCopyWithSentinel();
  OrderItemModelPartial copyWith({
    Object? id = _copyWithSentinel,
    Object? orderId = _copyWithSentinel,
    Object? sku = _copyWithSentinel,
    Object? title = _copyWithSentinel,
    Object? quantity = _copyWithSentinel,
    Object? unitPriceCents = _copyWithSentinel,
    Object? lineTotalCents = _copyWithSentinel,
  }) {
    return OrderItemModelPartial(
      id: identical(id, _copyWithSentinel) ? this.id : id as String?,
      orderId: identical(orderId, _copyWithSentinel)
          ? this.orderId
          : orderId as String?,
      sku: identical(sku, _copyWithSentinel) ? this.sku : sku as String?,
      title: identical(title, _copyWithSentinel)
          ? this.title
          : title as String?,
      quantity: identical(quantity, _copyWithSentinel)
          ? this.quantity
          : quantity as int?,
      unitPriceCents: identical(unitPriceCents, _copyWithSentinel)
          ? this.unitPriceCents
          : unitPriceCents as int?,
      lineTotalCents: identical(lineTotalCents, _copyWithSentinel)
          ? this.lineTotalCents
          : lineTotalCents as int?,
    );
  }
}

class _OrderItemModelPartialCopyWithSentinel {
  const _OrderItemModelPartialCopyWithSentinel();
}

/// Generated tracked model class for [OrderItemModel].
///
/// This class extends the user-defined [OrderItemModel] model and adds
/// attribute tracking, change detection, and relationship management.
/// Instances of this class are returned by queries and repositories.
///
/// **Do not instantiate this class directly.** Use queries, repositories,
/// or model factories to create tracked model instances.
class $OrderItemModel extends OrderItemModel
    with ModelAttributes, TimestampsTZImpl
    implements OrmEntity {
  /// Internal constructor for [$OrderItemModel].
  $OrderItemModel({
    required String id,
    required String orderId,
    required String sku,
    required String title,
    required int quantity,
    required int unitPriceCents,
    required int lineTotalCents,
  }) : super(
         id: id,
         orderId: orderId,
         sku: sku,
         title: title,
         quantity: quantity,
         unitPriceCents: unitPriceCents,
         lineTotalCents: lineTotalCents,
       ) {
    _attachOrmRuntimeMetadata({
      'id': id,
      'order_id': orderId,
      'sku': sku,
      'title': title,
      'quantity': quantity,
      'unit_price_cents': unitPriceCents,
      'line_total_cents': lineTotalCents,
    });
  }

  /// Creates a tracked model instance from a user-defined model instance.
  factory $OrderItemModel.fromModel(OrderItemModel model) {
    return $OrderItemModel(
      id: model.id,
      orderId: model.orderId,
      sku: model.sku,
      title: model.title,
      quantity: model.quantity,
      unitPriceCents: model.unitPriceCents,
      lineTotalCents: model.lineTotalCents,
    );
  }

  $OrderItemModel copyWith({
    String? id,
    String? orderId,
    String? sku,
    String? title,
    int? quantity,
    int? unitPriceCents,
    int? lineTotalCents,
  }) {
    return $OrderItemModel(
      id: id ?? this.id,
      orderId: orderId ?? this.orderId,
      sku: sku ?? this.sku,
      title: title ?? this.title,
      quantity: quantity ?? this.quantity,
      unitPriceCents: unitPriceCents ?? this.unitPriceCents,
      lineTotalCents: lineTotalCents ?? this.lineTotalCents,
    );
  }

  /// Builds a tracked model from a column/value map.
  static $OrderItemModel fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$OrderItemModelDefinition.fromMap(data, registry: registry);

  /// Converts this tracked model to a column/value map.
  Map<String, Object?> toMap({ValueCodecRegistry? registry}) =>
      _$OrderItemModelDefinition.toMap(this, registry: registry);

  /// Tracked getter for [id].
  @override
  String get id => getAttribute<String>('id') ?? super.id;

  /// Tracked setter for [id].
  set id(String value) => setAttribute('id', value);

  /// Tracked getter for [orderId].
  @override
  String get orderId => getAttribute<String>('order_id') ?? super.orderId;

  /// Tracked setter for [orderId].
  set orderId(String value) => setAttribute('order_id', value);

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

  /// Tracked getter for [quantity].
  @override
  int get quantity => getAttribute<int>('quantity') ?? super.quantity;

  /// Tracked setter for [quantity].
  set quantity(int value) => setAttribute('quantity', value);

  /// Tracked getter for [unitPriceCents].
  @override
  int get unitPriceCents =>
      getAttribute<int>('unit_price_cents') ?? super.unitPriceCents;

  /// Tracked setter for [unitPriceCents].
  set unitPriceCents(int value) => setAttribute('unit_price_cents', value);

  /// Tracked getter for [lineTotalCents].
  @override
  int get lineTotalCents =>
      getAttribute<int>('line_total_cents') ?? super.lineTotalCents;

  /// Tracked setter for [lineTotalCents].
  set lineTotalCents(int value) => setAttribute('line_total_cents', value);

  void _attachOrmRuntimeMetadata(Map<String, Object?> values) {
    replaceAttributes(values);
    attachModelDefinition(_$OrderItemModelDefinition);
  }
}

class _OrderItemModelCopyWithSentinel {
  const _OrderItemModelCopyWithSentinel();
}

extension OrderItemModelOrmExtension on OrderItemModel {
  static const _OrderItemModelCopyWithSentinel _copyWithSentinel =
      _OrderItemModelCopyWithSentinel();
  OrderItemModel copyWith({
    Object? id = _copyWithSentinel,
    Object? orderId = _copyWithSentinel,
    Object? sku = _copyWithSentinel,
    Object? title = _copyWithSentinel,
    Object? quantity = _copyWithSentinel,
    Object? unitPriceCents = _copyWithSentinel,
    Object? lineTotalCents = _copyWithSentinel,
  }) {
    return OrderItemModel(
      id: identical(id, _copyWithSentinel) ? this.id : id as String,
      orderId: identical(orderId, _copyWithSentinel)
          ? this.orderId
          : orderId as String,
      sku: identical(sku, _copyWithSentinel) ? this.sku : sku as String,
      title: identical(title, _copyWithSentinel) ? this.title : title as String,
      quantity: identical(quantity, _copyWithSentinel)
          ? this.quantity
          : quantity as int,
      unitPriceCents: identical(unitPriceCents, _copyWithSentinel)
          ? this.unitPriceCents
          : unitPriceCents as int,
      lineTotalCents: identical(lineTotalCents, _copyWithSentinel)
          ? this.lineTotalCents
          : lineTotalCents as int,
    );
  }

  /// Converts this model to a column/value map.
  Map<String, Object?> toMap({ValueCodecRegistry? registry}) =>
      _$OrderItemModelDefinition.toMap(this, registry: registry);

  /// Builds a model from a column/value map.
  static OrderItemModel fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$OrderItemModelDefinition.fromMap(data, registry: registry);

  /// The Type of the generated ORM-managed model class.
  /// Use this when you need to specify the tracked model type explicitly,
  /// for example in generic type parameters.
  static Type get trackedType => $OrderItemModel;

  /// Converts this immutable model to a tracked ORM-managed model.
  /// The tracked model supports attribute tracking, change detection,
  /// and persistence operations like save() and touch().
  $OrderItemModel toTracked() {
    return $OrderItemModel.fromModel(this);
  }
}

extension OrderItemModelPredicateFields on PredicateBuilder<OrderItemModel> {
  PredicateField<OrderItemModel, String> get id =>
      PredicateField<OrderItemModel, String>(this, 'id');
  PredicateField<OrderItemModel, String> get orderId =>
      PredicateField<OrderItemModel, String>(this, 'orderId');
  PredicateField<OrderItemModel, String> get sku =>
      PredicateField<OrderItemModel, String>(this, 'sku');
  PredicateField<OrderItemModel, String> get title =>
      PredicateField<OrderItemModel, String>(this, 'title');
  PredicateField<OrderItemModel, int> get quantity =>
      PredicateField<OrderItemModel, int>(this, 'quantity');
  PredicateField<OrderItemModel, int> get unitPriceCents =>
      PredicateField<OrderItemModel, int>(this, 'unitPriceCents');
  PredicateField<OrderItemModel, int> get lineTotalCents =>
      PredicateField<OrderItemModel, int>(this, 'lineTotalCents');
}

void registerOrderItemModelEventHandlers(EventBus bus) {
  // No event handlers registered for OrderItemModel.
}
