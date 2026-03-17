// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'cart.dart';

// **************************************************************************
// OrmModelGenerator
// **************************************************************************

const FieldDefinition _$CartModelIdField = FieldDefinition(
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

const FieldDefinition _$CartModelCustomerIdField = FieldDefinition(
  name: 'customerId',
  columnName: 'customer_id',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$CartModelStatusField = FieldDefinition(
  name: 'status',
  columnName: 'status',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$CartModelCreatedAtField = FieldDefinition(
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

const FieldDefinition _$CartModelUpdatedAtField = FieldDefinition(
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

Map<String, Object?> _encodeCartModelUntracked(
  Object model,
  ValueCodecRegistry registry,
) {
  final m = model as CartModel;
  return <String, Object?>{
    'id': registry.encodeField(_$CartModelIdField, m.id),
    'customer_id': registry.encodeField(
      _$CartModelCustomerIdField,
      m.customerId,
    ),
    'status': registry.encodeField(_$CartModelStatusField, m.status),
  };
}

final ModelDefinition<$CartModel> _$CartModelDefinition = ModelDefinition(
  modelName: 'CartModel',
  tableName: 'carts',
  fields: const [
    _$CartModelIdField,
    _$CartModelCustomerIdField,
    _$CartModelStatusField,
    _$CartModelCreatedAtField,
    _$CartModelUpdatedAtField,
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
  untrackedToMap: _encodeCartModelUntracked,
  codec: _$CartModelCodec(),
);

extension CartModelOrmDefinition on CartModel {
  static ModelDefinition<$CartModel> get definition => _$CartModelDefinition;
}

class CartModels {
  const CartModels._();

  /// Starts building a query for [$CartModel].
  ///
  /// {@macro ormed.query}
  static Query<$CartModel> query([String? connection]) =>
      Model.query<$CartModel>(connection: connection);

  static Future<$CartModel?> find(Object id, {String? connection}) =>
      Model.find<$CartModel>(id, connection: connection);

  static Future<$CartModel> findOrFail(Object id, {String? connection}) =>
      Model.findOrFail<$CartModel>(id, connection: connection);

  static Future<List<$CartModel>> all({String? connection}) =>
      Model.all<$CartModel>(connection: connection);

  static Future<int> count({String? connection}) =>
      Model.count<$CartModel>(connection: connection);

  static Future<bool> anyExist({String? connection}) =>
      Model.anyExist<$CartModel>(connection: connection);

  static Query<$CartModel> where(
    String column,
    String operator,
    dynamic value, {
    String? connection,
  }) =>
      Model.where<$CartModel>(column, operator, value, connection: connection);

  static Query<$CartModel> whereIn(
    String column,
    List<dynamic> values, {
    String? connection,
  }) => Model.whereIn<$CartModel>(column, values, connection: connection);

  static Query<$CartModel> orderBy(
    String column, {
    String direction = "asc",
    String? connection,
  }) => Model.orderBy<$CartModel>(
    column,
    direction: direction,
    connection: connection,
  );

  static Query<$CartModel> limit(int count, {String? connection}) =>
      Model.limit<$CartModel>(count, connection: connection);

  /// Creates a [Repository] for [$CartModel].
  ///
  /// {@macro ormed.repository}
  static Repository<$CartModel> repo([String? connection]) =>
      Model.repository<$CartModel>(connection: connection);

  /// Builds a tracked model from a column/value map.
  static $CartModel fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$CartModelDefinition.fromMap(data, registry: registry);

  /// Converts a tracked model to a column/value map.
  static Map<String, Object?> toMap(
    $CartModel model, {
    ValueCodecRegistry? registry,
  }) => _$CartModelDefinition.toMap(model, registry: registry);
}

class CartModelFactory {
  const CartModelFactory._();

  static ModelDefinition<$CartModel> get definition => _$CartModelDefinition;

  static ModelCodec<$CartModel> get codec => definition.codec;

  static CartModel fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => definition.fromMap(data, registry: registry);

  static Map<String, Object?> toMap(
    CartModel model, {
    ValueCodecRegistry? registry,
  }) => definition.toMap(model.toTracked(), registry: registry);

  static void registerWith(ModelRegistry registry) =>
      registry.register(definition);

  static ModelFactoryConnection<CartModel> withConnection(
    QueryContext context,
  ) => ModelFactoryConnection<CartModel>(
    definition: definition,
    context: context,
  );

  static ModelFactoryBuilder<CartModel> factory({
    GeneratorProvider? generatorProvider,
  }) => ModelFactoryRegistry.factoryFor<CartModel>(
    generatorProvider: generatorProvider,
  );
}

class _$CartModelCodec extends ModelCodec<$CartModel> {
  const _$CartModelCodec();
  @override
  Map<String, Object?> encode($CartModel model, ValueCodecRegistry registry) {
    return <String, Object?>{
      'id': registry.encodeField(_$CartModelIdField, model.id),
      'customer_id': registry.encodeField(
        _$CartModelCustomerIdField,
        model.customerId,
      ),
      'status': registry.encodeField(_$CartModelStatusField, model.status),
      if (model.hasAttribute('created_at'))
        'created_at': registry.encodeField(
          _$CartModelCreatedAtField,
          model.getAttribute<DateTime?>('created_at'),
        ),
      if (model.hasAttribute('updated_at'))
        'updated_at': registry.encodeField(
          _$CartModelUpdatedAtField,
          model.getAttribute<DateTime?>('updated_at'),
        ),
    };
  }

  @override
  $CartModel decode(Map<String, Object?> data, ValueCodecRegistry registry) {
    final String cartModelIdValue =
        registry.decodeField<String>(_$CartModelIdField, data['id']) ??
        (throw StateError('Field id on CartModel cannot be null.'));
    final String cartModelCustomerIdValue =
        registry.decodeField<String>(
          _$CartModelCustomerIdField,
          data['customer_id'],
        ) ??
        (throw StateError('Field customerId on CartModel cannot be null.'));
    final String cartModelStatusValue =
        registry.decodeField<String>(_$CartModelStatusField, data['status']) ??
        (throw StateError('Field status on CartModel cannot be null.'));
    final DateTime? cartModelCreatedAtValue = registry.decodeField<DateTime?>(
      _$CartModelCreatedAtField,
      data['created_at'],
    );
    final DateTime? cartModelUpdatedAtValue = registry.decodeField<DateTime?>(
      _$CartModelUpdatedAtField,
      data['updated_at'],
    );
    final model = $CartModel(
      id: cartModelIdValue,
      customerId: cartModelCustomerIdValue,
      status: cartModelStatusValue,
    );
    model._attachOrmRuntimeMetadata({
      'id': cartModelIdValue,
      'customer_id': cartModelCustomerIdValue,
      'status': cartModelStatusValue,
      if (data.containsKey('created_at')) 'created_at': cartModelCreatedAtValue,
      if (data.containsKey('updated_at')) 'updated_at': cartModelUpdatedAtValue,
    });
    return model;
  }
}

/// Insert DTO for [CartModel].
///
/// Auto-increment/DB-generated fields are omitted by default.
class CartModelInsertDto implements InsertDto<$CartModel> {
  const CartModelInsertDto({this.id, this.customerId, this.status});
  final String? id;
  final String? customerId;
  final String? status;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      if (customerId != null) 'customer_id': customerId,
      if (status != null) 'status': status,
    };
  }

  static const _CartModelInsertDtoCopyWithSentinel _copyWithSentinel =
      _CartModelInsertDtoCopyWithSentinel();
  CartModelInsertDto copyWith({
    Object? id = _copyWithSentinel,
    Object? customerId = _copyWithSentinel,
    Object? status = _copyWithSentinel,
  }) {
    return CartModelInsertDto(
      id: identical(id, _copyWithSentinel) ? this.id : id as String?,
      customerId: identical(customerId, _copyWithSentinel)
          ? this.customerId
          : customerId as String?,
      status: identical(status, _copyWithSentinel)
          ? this.status
          : status as String?,
    );
  }
}

class _CartModelInsertDtoCopyWithSentinel {
  const _CartModelInsertDtoCopyWithSentinel();
}

/// Update DTO for [CartModel].
///
/// All fields are optional; only provided entries are used in SET clauses.
class CartModelUpdateDto implements UpdateDto<$CartModel> {
  const CartModelUpdateDto({this.id, this.customerId, this.status});
  final String? id;
  final String? customerId;
  final String? status;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      if (customerId != null) 'customer_id': customerId,
      if (status != null) 'status': status,
    };
  }

  static const _CartModelUpdateDtoCopyWithSentinel _copyWithSentinel =
      _CartModelUpdateDtoCopyWithSentinel();
  CartModelUpdateDto copyWith({
    Object? id = _copyWithSentinel,
    Object? customerId = _copyWithSentinel,
    Object? status = _copyWithSentinel,
  }) {
    return CartModelUpdateDto(
      id: identical(id, _copyWithSentinel) ? this.id : id as String?,
      customerId: identical(customerId, _copyWithSentinel)
          ? this.customerId
          : customerId as String?,
      status: identical(status, _copyWithSentinel)
          ? this.status
          : status as String?,
    );
  }
}

class _CartModelUpdateDtoCopyWithSentinel {
  const _CartModelUpdateDtoCopyWithSentinel();
}

/// Partial projection for [CartModel].
///
/// All fields are nullable; intended for subset SELECTs.
class CartModelPartial implements PartialEntity<$CartModel> {
  const CartModelPartial({this.id, this.customerId, this.status});

  /// Creates a partial from a database row map.
  ///
  /// The [row] keys should be column names (snake_case).
  /// Missing columns will result in null field values.
  factory CartModelPartial.fromRow(Map<String, Object?> row) {
    return CartModelPartial(
      id: row['id'] as String?,
      customerId: row['customer_id'] as String?,
      status: row['status'] as String?,
    );
  }

  final String? id;
  final String? customerId;
  final String? status;

  @override
  $CartModel toEntity() {
    // Basic required-field check: non-nullable fields must be present.
    final String? idValue = id;
    if (idValue == null) {
      throw StateError('Missing required field: id');
    }
    final String? customerIdValue = customerId;
    if (customerIdValue == null) {
      throw StateError('Missing required field: customerId');
    }
    final String? statusValue = status;
    if (statusValue == null) {
      throw StateError('Missing required field: status');
    }
    return $CartModel(
      id: idValue,
      customerId: customerIdValue,
      status: statusValue,
    );
  }

  @override
  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      if (customerId != null) 'customer_id': customerId,
      if (status != null) 'status': status,
    };
  }

  static const _CartModelPartialCopyWithSentinel _copyWithSentinel =
      _CartModelPartialCopyWithSentinel();
  CartModelPartial copyWith({
    Object? id = _copyWithSentinel,
    Object? customerId = _copyWithSentinel,
    Object? status = _copyWithSentinel,
  }) {
    return CartModelPartial(
      id: identical(id, _copyWithSentinel) ? this.id : id as String?,
      customerId: identical(customerId, _copyWithSentinel)
          ? this.customerId
          : customerId as String?,
      status: identical(status, _copyWithSentinel)
          ? this.status
          : status as String?,
    );
  }
}

class _CartModelPartialCopyWithSentinel {
  const _CartModelPartialCopyWithSentinel();
}

/// Generated tracked model class for [CartModel].
///
/// This class extends the user-defined [CartModel] model and adds
/// attribute tracking, change detection, and relationship management.
/// Instances of this class are returned by queries and repositories.
///
/// **Do not instantiate this class directly.** Use queries, repositories,
/// or model factories to create tracked model instances.
class $CartModel extends CartModel
    with ModelAttributes, TimestampsTZImpl
    implements OrmEntity {
  /// Internal constructor for [$CartModel].
  $CartModel({
    required String id,
    required String customerId,
    required String status,
  }) : super(id: id, customerId: customerId, status: status) {
    _attachOrmRuntimeMetadata({
      'id': id,
      'customer_id': customerId,
      'status': status,
    });
  }

  /// Creates a tracked model instance from a user-defined model instance.
  factory $CartModel.fromModel(CartModel model) {
    return $CartModel(
      id: model.id,
      customerId: model.customerId,
      status: model.status,
    );
  }

  $CartModel copyWith({String? id, String? customerId, String? status}) {
    return $CartModel(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      status: status ?? this.status,
    );
  }

  /// Builds a tracked model from a column/value map.
  static $CartModel fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$CartModelDefinition.fromMap(data, registry: registry);

  /// Converts this tracked model to a column/value map.
  Map<String, Object?> toMap({ValueCodecRegistry? registry}) =>
      _$CartModelDefinition.toMap(this, registry: registry);

  /// Tracked getter for [id].
  @override
  String get id => getAttribute<String>('id') ?? super.id;

  /// Tracked setter for [id].
  set id(String value) => setAttribute('id', value);

  /// Tracked getter for [customerId].
  @override
  String get customerId =>
      getAttribute<String>('customer_id') ?? super.customerId;

  /// Tracked setter for [customerId].
  set customerId(String value) => setAttribute('customer_id', value);

  /// Tracked getter for [status].
  @override
  String get status => getAttribute<String>('status') ?? super.status;

  /// Tracked setter for [status].
  set status(String value) => setAttribute('status', value);

  void _attachOrmRuntimeMetadata(Map<String, Object?> values) {
    replaceAttributes(values);
    attachModelDefinition(_$CartModelDefinition);
  }
}

class _CartModelCopyWithSentinel {
  const _CartModelCopyWithSentinel();
}

extension CartModelOrmExtension on CartModel {
  static const _CartModelCopyWithSentinel _copyWithSentinel =
      _CartModelCopyWithSentinel();
  CartModel copyWith({
    Object? id = _copyWithSentinel,
    Object? customerId = _copyWithSentinel,
    Object? status = _copyWithSentinel,
  }) {
    return CartModel(
      id: identical(id, _copyWithSentinel) ? this.id : id as String,
      customerId: identical(customerId, _copyWithSentinel)
          ? this.customerId
          : customerId as String,
      status: identical(status, _copyWithSentinel)
          ? this.status
          : status as String,
    );
  }

  /// Converts this model to a column/value map.
  Map<String, Object?> toMap({ValueCodecRegistry? registry}) =>
      _$CartModelDefinition.toMap(this, registry: registry);

  /// Builds a model from a column/value map.
  static CartModel fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$CartModelDefinition.fromMap(data, registry: registry);

  /// The Type of the generated ORM-managed model class.
  /// Use this when you need to specify the tracked model type explicitly,
  /// for example in generic type parameters.
  static Type get trackedType => $CartModel;

  /// Converts this immutable model to a tracked ORM-managed model.
  /// The tracked model supports attribute tracking, change detection,
  /// and persistence operations like save() and touch().
  $CartModel toTracked() {
    return $CartModel.fromModel(this);
  }
}

extension CartModelPredicateFields on PredicateBuilder<CartModel> {
  PredicateField<CartModel, String> get id =>
      PredicateField<CartModel, String>(this, 'id');
  PredicateField<CartModel, String> get customerId =>
      PredicateField<CartModel, String>(this, 'customerId');
  PredicateField<CartModel, String> get status =>
      PredicateField<CartModel, String>(this, 'status');
}

void registerCartModelEventHandlers(EventBus bus) {
  // No event handlers registered for CartModel.
}
