// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'cart_item.dart';

// **************************************************************************
// OrmModelGenerator
// **************************************************************************

const FieldDefinition _$CartItemModelIdField = FieldDefinition(
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

const FieldDefinition _$CartItemModelCartIdField = FieldDefinition(
  name: 'cartId',
  columnName: 'cart_id',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$CartItemModelSkuField = FieldDefinition(
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

const FieldDefinition _$CartItemModelTitleField = FieldDefinition(
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

const FieldDefinition _$CartItemModelQuantityField = FieldDefinition(
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

const FieldDefinition _$CartItemModelUnitPriceCentsField = FieldDefinition(
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

const FieldDefinition _$CartItemModelLineTotalCentsField = FieldDefinition(
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

const FieldDefinition _$CartItemModelCreatedAtField = FieldDefinition(
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

const FieldDefinition _$CartItemModelUpdatedAtField = FieldDefinition(
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

Map<String, Object?> _encodeCartItemModelUntracked(
  Object model,
  ValueCodecRegistry registry,
) {
  final m = model as CartItemModel;
  return <String, Object?>{
    'id': registry.encodeField(_$CartItemModelIdField, m.id),
    'cart_id': registry.encodeField(_$CartItemModelCartIdField, m.cartId),
    'sku': registry.encodeField(_$CartItemModelSkuField, m.sku),
    'title': registry.encodeField(_$CartItemModelTitleField, m.title),
    'quantity': registry.encodeField(_$CartItemModelQuantityField, m.quantity),
    'unit_price_cents': registry.encodeField(
      _$CartItemModelUnitPriceCentsField,
      m.unitPriceCents,
    ),
    'line_total_cents': registry.encodeField(
      _$CartItemModelLineTotalCentsField,
      m.lineTotalCents,
    ),
  };
}

final ModelDefinition<$CartItemModel> _$CartItemModelDefinition =
    ModelDefinition(
      modelName: 'CartItemModel',
      tableName: 'cart_items',
      fields: const [
        _$CartItemModelIdField,
        _$CartItemModelCartIdField,
        _$CartItemModelSkuField,
        _$CartItemModelTitleField,
        _$CartItemModelQuantityField,
        _$CartItemModelUnitPriceCentsField,
        _$CartItemModelLineTotalCentsField,
        _$CartItemModelCreatedAtField,
        _$CartItemModelUpdatedAtField,
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
      untrackedToMap: _encodeCartItemModelUntracked,
      codec: _$CartItemModelCodec(),
    );

extension CartItemModelOrmDefinition on CartItemModel {
  static ModelDefinition<$CartItemModel> get definition =>
      _$CartItemModelDefinition;
}

class CartItemModels {
  const CartItemModels._();

  /// Starts building a query for [$CartItemModel].
  ///
  /// {@macro ormed.query}
  static Query<$CartItemModel> query([String? connection]) =>
      Model.query<$CartItemModel>(connection: connection);

  static Future<$CartItemModel?> find(Object id, {String? connection}) =>
      Model.find<$CartItemModel>(id, connection: connection);

  static Future<$CartItemModel> findOrFail(Object id, {String? connection}) =>
      Model.findOrFail<$CartItemModel>(id, connection: connection);

  static Future<List<$CartItemModel>> all({String? connection}) =>
      Model.all<$CartItemModel>(connection: connection);

  static Future<int> count({String? connection}) =>
      Model.count<$CartItemModel>(connection: connection);

  static Future<bool> anyExist({String? connection}) =>
      Model.anyExist<$CartItemModel>(connection: connection);

  static Query<$CartItemModel> where(
    String column,
    String operator,
    dynamic value, {
    String? connection,
  }) => Model.where<$CartItemModel>(
    column,
    operator,
    value,
    connection: connection,
  );

  static Query<$CartItemModel> whereIn(
    String column,
    List<dynamic> values, {
    String? connection,
  }) => Model.whereIn<$CartItemModel>(column, values, connection: connection);

  static Query<$CartItemModel> orderBy(
    String column, {
    String direction = "asc",
    String? connection,
  }) => Model.orderBy<$CartItemModel>(
    column,
    direction: direction,
    connection: connection,
  );

  static Query<$CartItemModel> limit(int count, {String? connection}) =>
      Model.limit<$CartItemModel>(count, connection: connection);

  /// Creates a [Repository] for [$CartItemModel].
  ///
  /// {@macro ormed.repository}
  static Repository<$CartItemModel> repo([String? connection]) =>
      Model.repository<$CartItemModel>(connection: connection);

  /// Builds a tracked model from a column/value map.
  static $CartItemModel fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$CartItemModelDefinition.fromMap(data, registry: registry);

  /// Converts a tracked model to a column/value map.
  static Map<String, Object?> toMap(
    $CartItemModel model, {
    ValueCodecRegistry? registry,
  }) => _$CartItemModelDefinition.toMap(model, registry: registry);
}

class CartItemModelFactory {
  const CartItemModelFactory._();

  static ModelDefinition<$CartItemModel> get definition =>
      _$CartItemModelDefinition;

  static ModelCodec<$CartItemModel> get codec => definition.codec;

  static CartItemModel fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => definition.fromMap(data, registry: registry);

  static Map<String, Object?> toMap(
    CartItemModel model, {
    ValueCodecRegistry? registry,
  }) => definition.toMap(model.toTracked(), registry: registry);

  static void registerWith(ModelRegistry registry) =>
      registry.register(definition);

  static ModelFactoryConnection<CartItemModel> withConnection(
    QueryContext context,
  ) => ModelFactoryConnection<CartItemModel>(
    definition: definition,
    context: context,
  );

  static ModelFactoryBuilder<CartItemModel> factory({
    GeneratorProvider? generatorProvider,
  }) => ModelFactoryRegistry.factoryFor<CartItemModel>(
    generatorProvider: generatorProvider,
  );
}

class _$CartItemModelCodec extends ModelCodec<$CartItemModel> {
  const _$CartItemModelCodec();
  @override
  Map<String, Object?> encode(
    $CartItemModel model,
    ValueCodecRegistry registry,
  ) {
    return <String, Object?>{
      'id': registry.encodeField(_$CartItemModelIdField, model.id),
      'cart_id': registry.encodeField(_$CartItemModelCartIdField, model.cartId),
      'sku': registry.encodeField(_$CartItemModelSkuField, model.sku),
      'title': registry.encodeField(_$CartItemModelTitleField, model.title),
      'quantity': registry.encodeField(
        _$CartItemModelQuantityField,
        model.quantity,
      ),
      'unit_price_cents': registry.encodeField(
        _$CartItemModelUnitPriceCentsField,
        model.unitPriceCents,
      ),
      'line_total_cents': registry.encodeField(
        _$CartItemModelLineTotalCentsField,
        model.lineTotalCents,
      ),
      if (model.hasAttribute('created_at'))
        'created_at': registry.encodeField(
          _$CartItemModelCreatedAtField,
          model.getAttribute<DateTime?>('created_at'),
        ),
      if (model.hasAttribute('updated_at'))
        'updated_at': registry.encodeField(
          _$CartItemModelUpdatedAtField,
          model.getAttribute<DateTime?>('updated_at'),
        ),
    };
  }

  @override
  $CartItemModel decode(
    Map<String, Object?> data,
    ValueCodecRegistry registry,
  ) {
    final String cartItemModelIdValue =
        registry.decodeField<String>(_$CartItemModelIdField, data['id']) ??
        (throw StateError('Field id on CartItemModel cannot be null.'));
    final String cartItemModelCartIdValue =
        registry.decodeField<String>(
          _$CartItemModelCartIdField,
          data['cart_id'],
        ) ??
        (throw StateError('Field cartId on CartItemModel cannot be null.'));
    final String cartItemModelSkuValue =
        registry.decodeField<String>(_$CartItemModelSkuField, data['sku']) ??
        (throw StateError('Field sku on CartItemModel cannot be null.'));
    final String cartItemModelTitleValue =
        registry.decodeField<String>(
          _$CartItemModelTitleField,
          data['title'],
        ) ??
        (throw StateError('Field title on CartItemModel cannot be null.'));
    final int cartItemModelQuantityValue =
        registry.decodeField<int>(
          _$CartItemModelQuantityField,
          data['quantity'],
        ) ??
        (throw StateError('Field quantity on CartItemModel cannot be null.'));
    final int cartItemModelUnitPriceCentsValue =
        registry.decodeField<int>(
          _$CartItemModelUnitPriceCentsField,
          data['unit_price_cents'],
        ) ??
        (throw StateError(
          'Field unitPriceCents on CartItemModel cannot be null.',
        ));
    final int cartItemModelLineTotalCentsValue =
        registry.decodeField<int>(
          _$CartItemModelLineTotalCentsField,
          data['line_total_cents'],
        ) ??
        (throw StateError(
          'Field lineTotalCents on CartItemModel cannot be null.',
        ));
    final DateTime? cartItemModelCreatedAtValue = registry
        .decodeField<DateTime?>(
          _$CartItemModelCreatedAtField,
          data['created_at'],
        );
    final DateTime? cartItemModelUpdatedAtValue = registry
        .decodeField<DateTime?>(
          _$CartItemModelUpdatedAtField,
          data['updated_at'],
        );
    final model = $CartItemModel(
      id: cartItemModelIdValue,
      cartId: cartItemModelCartIdValue,
      sku: cartItemModelSkuValue,
      title: cartItemModelTitleValue,
      quantity: cartItemModelQuantityValue,
      unitPriceCents: cartItemModelUnitPriceCentsValue,
      lineTotalCents: cartItemModelLineTotalCentsValue,
    );
    model._attachOrmRuntimeMetadata({
      'id': cartItemModelIdValue,
      'cart_id': cartItemModelCartIdValue,
      'sku': cartItemModelSkuValue,
      'title': cartItemModelTitleValue,
      'quantity': cartItemModelQuantityValue,
      'unit_price_cents': cartItemModelUnitPriceCentsValue,
      'line_total_cents': cartItemModelLineTotalCentsValue,
      if (data.containsKey('created_at'))
        'created_at': cartItemModelCreatedAtValue,
      if (data.containsKey('updated_at'))
        'updated_at': cartItemModelUpdatedAtValue,
    });
    return model;
  }
}

/// Insert DTO for [CartItemModel].
///
/// Auto-increment/DB-generated fields are omitted by default.
class CartItemModelInsertDto implements InsertDto<$CartItemModel> {
  const CartItemModelInsertDto({
    this.id,
    this.cartId,
    this.sku,
    this.title,
    this.quantity,
    this.unitPriceCents,
    this.lineTotalCents,
  });
  final String? id;
  final String? cartId;
  final String? sku;
  final String? title;
  final int? quantity;
  final int? unitPriceCents;
  final int? lineTotalCents;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      if (cartId != null) 'cart_id': cartId,
      if (sku != null) 'sku': sku,
      if (title != null) 'title': title,
      if (quantity != null) 'quantity': quantity,
      if (unitPriceCents != null) 'unit_price_cents': unitPriceCents,
      if (lineTotalCents != null) 'line_total_cents': lineTotalCents,
    };
  }

  static const _CartItemModelInsertDtoCopyWithSentinel _copyWithSentinel =
      _CartItemModelInsertDtoCopyWithSentinel();
  CartItemModelInsertDto copyWith({
    Object? id = _copyWithSentinel,
    Object? cartId = _copyWithSentinel,
    Object? sku = _copyWithSentinel,
    Object? title = _copyWithSentinel,
    Object? quantity = _copyWithSentinel,
    Object? unitPriceCents = _copyWithSentinel,
    Object? lineTotalCents = _copyWithSentinel,
  }) {
    return CartItemModelInsertDto(
      id: identical(id, _copyWithSentinel) ? this.id : id as String?,
      cartId: identical(cartId, _copyWithSentinel)
          ? this.cartId
          : cartId as String?,
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

class _CartItemModelInsertDtoCopyWithSentinel {
  const _CartItemModelInsertDtoCopyWithSentinel();
}

/// Update DTO for [CartItemModel].
///
/// All fields are optional; only provided entries are used in SET clauses.
class CartItemModelUpdateDto implements UpdateDto<$CartItemModel> {
  const CartItemModelUpdateDto({
    this.id,
    this.cartId,
    this.sku,
    this.title,
    this.quantity,
    this.unitPriceCents,
    this.lineTotalCents,
  });
  final String? id;
  final String? cartId;
  final String? sku;
  final String? title;
  final int? quantity;
  final int? unitPriceCents;
  final int? lineTotalCents;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      if (cartId != null) 'cart_id': cartId,
      if (sku != null) 'sku': sku,
      if (title != null) 'title': title,
      if (quantity != null) 'quantity': quantity,
      if (unitPriceCents != null) 'unit_price_cents': unitPriceCents,
      if (lineTotalCents != null) 'line_total_cents': lineTotalCents,
    };
  }

  static const _CartItemModelUpdateDtoCopyWithSentinel _copyWithSentinel =
      _CartItemModelUpdateDtoCopyWithSentinel();
  CartItemModelUpdateDto copyWith({
    Object? id = _copyWithSentinel,
    Object? cartId = _copyWithSentinel,
    Object? sku = _copyWithSentinel,
    Object? title = _copyWithSentinel,
    Object? quantity = _copyWithSentinel,
    Object? unitPriceCents = _copyWithSentinel,
    Object? lineTotalCents = _copyWithSentinel,
  }) {
    return CartItemModelUpdateDto(
      id: identical(id, _copyWithSentinel) ? this.id : id as String?,
      cartId: identical(cartId, _copyWithSentinel)
          ? this.cartId
          : cartId as String?,
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

class _CartItemModelUpdateDtoCopyWithSentinel {
  const _CartItemModelUpdateDtoCopyWithSentinel();
}

/// Partial projection for [CartItemModel].
///
/// All fields are nullable; intended for subset SELECTs.
class CartItemModelPartial implements PartialEntity<$CartItemModel> {
  const CartItemModelPartial({
    this.id,
    this.cartId,
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
  factory CartItemModelPartial.fromRow(Map<String, Object?> row) {
    return CartItemModelPartial(
      id: row['id'] as String?,
      cartId: row['cart_id'] as String?,
      sku: row['sku'] as String?,
      title: row['title'] as String?,
      quantity: row['quantity'] as int?,
      unitPriceCents: row['unit_price_cents'] as int?,
      lineTotalCents: row['line_total_cents'] as int?,
    );
  }

  final String? id;
  final String? cartId;
  final String? sku;
  final String? title;
  final int? quantity;
  final int? unitPriceCents;
  final int? lineTotalCents;

  @override
  $CartItemModel toEntity() {
    // Basic required-field check: non-nullable fields must be present.
    final String? idValue = id;
    if (idValue == null) {
      throw StateError('Missing required field: id');
    }
    final String? cartIdValue = cartId;
    if (cartIdValue == null) {
      throw StateError('Missing required field: cartId');
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
    return $CartItemModel(
      id: idValue,
      cartId: cartIdValue,
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
      if (cartId != null) 'cart_id': cartId,
      if (sku != null) 'sku': sku,
      if (title != null) 'title': title,
      if (quantity != null) 'quantity': quantity,
      if (unitPriceCents != null) 'unit_price_cents': unitPriceCents,
      if (lineTotalCents != null) 'line_total_cents': lineTotalCents,
    };
  }

  static const _CartItemModelPartialCopyWithSentinel _copyWithSentinel =
      _CartItemModelPartialCopyWithSentinel();
  CartItemModelPartial copyWith({
    Object? id = _copyWithSentinel,
    Object? cartId = _copyWithSentinel,
    Object? sku = _copyWithSentinel,
    Object? title = _copyWithSentinel,
    Object? quantity = _copyWithSentinel,
    Object? unitPriceCents = _copyWithSentinel,
    Object? lineTotalCents = _copyWithSentinel,
  }) {
    return CartItemModelPartial(
      id: identical(id, _copyWithSentinel) ? this.id : id as String?,
      cartId: identical(cartId, _copyWithSentinel)
          ? this.cartId
          : cartId as String?,
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

class _CartItemModelPartialCopyWithSentinel {
  const _CartItemModelPartialCopyWithSentinel();
}

/// Generated tracked model class for [CartItemModel].
///
/// This class extends the user-defined [CartItemModel] model and adds
/// attribute tracking, change detection, and relationship management.
/// Instances of this class are returned by queries and repositories.
///
/// **Do not instantiate this class directly.** Use queries, repositories,
/// or model factories to create tracked model instances.
class $CartItemModel extends CartItemModel
    with ModelAttributes, TimestampsTZImpl
    implements OrmEntity {
  /// Internal constructor for [$CartItemModel].
  $CartItemModel({
    required String id,
    required String cartId,
    required String sku,
    required String title,
    required int quantity,
    required int unitPriceCents,
    required int lineTotalCents,
  }) : super(
         id: id,
         cartId: cartId,
         sku: sku,
         title: title,
         quantity: quantity,
         unitPriceCents: unitPriceCents,
         lineTotalCents: lineTotalCents,
       ) {
    _attachOrmRuntimeMetadata({
      'id': id,
      'cart_id': cartId,
      'sku': sku,
      'title': title,
      'quantity': quantity,
      'unit_price_cents': unitPriceCents,
      'line_total_cents': lineTotalCents,
    });
  }

  /// Creates a tracked model instance from a user-defined model instance.
  factory $CartItemModel.fromModel(CartItemModel model) {
    return $CartItemModel(
      id: model.id,
      cartId: model.cartId,
      sku: model.sku,
      title: model.title,
      quantity: model.quantity,
      unitPriceCents: model.unitPriceCents,
      lineTotalCents: model.lineTotalCents,
    );
  }

  $CartItemModel copyWith({
    String? id,
    String? cartId,
    String? sku,
    String? title,
    int? quantity,
    int? unitPriceCents,
    int? lineTotalCents,
  }) {
    return $CartItemModel(
      id: id ?? this.id,
      cartId: cartId ?? this.cartId,
      sku: sku ?? this.sku,
      title: title ?? this.title,
      quantity: quantity ?? this.quantity,
      unitPriceCents: unitPriceCents ?? this.unitPriceCents,
      lineTotalCents: lineTotalCents ?? this.lineTotalCents,
    );
  }

  /// Builds a tracked model from a column/value map.
  static $CartItemModel fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$CartItemModelDefinition.fromMap(data, registry: registry);

  /// Converts this tracked model to a column/value map.
  Map<String, Object?> toMap({ValueCodecRegistry? registry}) =>
      _$CartItemModelDefinition.toMap(this, registry: registry);

  /// Tracked getter for [id].
  @override
  String get id => getAttribute<String>('id') ?? super.id;

  /// Tracked setter for [id].
  set id(String value) => setAttribute('id', value);

  /// Tracked getter for [cartId].
  @override
  String get cartId => getAttribute<String>('cart_id') ?? super.cartId;

  /// Tracked setter for [cartId].
  set cartId(String value) => setAttribute('cart_id', value);

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
    attachModelDefinition(_$CartItemModelDefinition);
  }
}

class _CartItemModelCopyWithSentinel {
  const _CartItemModelCopyWithSentinel();
}

extension CartItemModelOrmExtension on CartItemModel {
  static const _CartItemModelCopyWithSentinel _copyWithSentinel =
      _CartItemModelCopyWithSentinel();
  CartItemModel copyWith({
    Object? id = _copyWithSentinel,
    Object? cartId = _copyWithSentinel,
    Object? sku = _copyWithSentinel,
    Object? title = _copyWithSentinel,
    Object? quantity = _copyWithSentinel,
    Object? unitPriceCents = _copyWithSentinel,
    Object? lineTotalCents = _copyWithSentinel,
  }) {
    return CartItemModel(
      id: identical(id, _copyWithSentinel) ? this.id : id as String,
      cartId: identical(cartId, _copyWithSentinel)
          ? this.cartId
          : cartId as String,
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
      _$CartItemModelDefinition.toMap(this, registry: registry);

  /// Builds a model from a column/value map.
  static CartItemModel fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$CartItemModelDefinition.fromMap(data, registry: registry);

  /// The Type of the generated ORM-managed model class.
  /// Use this when you need to specify the tracked model type explicitly,
  /// for example in generic type parameters.
  static Type get trackedType => $CartItemModel;

  /// Converts this immutable model to a tracked ORM-managed model.
  /// The tracked model supports attribute tracking, change detection,
  /// and persistence operations like save() and touch().
  $CartItemModel toTracked() {
    return $CartItemModel.fromModel(this);
  }
}

extension CartItemModelPredicateFields on PredicateBuilder<CartItemModel> {
  PredicateField<CartItemModel, String> get id =>
      PredicateField<CartItemModel, String>(this, 'id');
  PredicateField<CartItemModel, String> get cartId =>
      PredicateField<CartItemModel, String>(this, 'cartId');
  PredicateField<CartItemModel, String> get sku =>
      PredicateField<CartItemModel, String>(this, 'sku');
  PredicateField<CartItemModel, String> get title =>
      PredicateField<CartItemModel, String>(this, 'title');
  PredicateField<CartItemModel, int> get quantity =>
      PredicateField<CartItemModel, int>(this, 'quantity');
  PredicateField<CartItemModel, int> get unitPriceCents =>
      PredicateField<CartItemModel, int>(this, 'unitPriceCents');
  PredicateField<CartItemModel, int> get lineTotalCents =>
      PredicateField<CartItemModel, int>(this, 'lineTotalCents');
}

void registerCartItemModelEventHandlers(EventBus bus) {
  // No event handlers registered for CartItemModel.
}
