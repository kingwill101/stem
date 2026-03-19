// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'order.dart';

// **************************************************************************
// OrmModelGenerator
// **************************************************************************

const FieldDefinition _$OrderModelIdField = FieldDefinition(
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

const FieldDefinition _$OrderModelCartIdField = FieldDefinition(
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

const FieldDefinition _$OrderModelCustomerIdField = FieldDefinition(
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

const FieldDefinition _$OrderModelStatusField = FieldDefinition(
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

const FieldDefinition _$OrderModelTotalCentsField = FieldDefinition(
  name: 'totalCents',
  columnName: 'total_cents',
  dartType: 'int',
  resolvedType: 'int',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$OrderModelPaymentReferenceField = FieldDefinition(
  name: 'paymentReference',
  columnName: 'payment_reference',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$OrderModelCreatedAtField = FieldDefinition(
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

const FieldDefinition _$OrderModelUpdatedAtField = FieldDefinition(
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

Map<String, Object?> _encodeOrderModelUntracked(
  Object model,
  ValueCodecRegistry registry,
) {
  final m = model as OrderModel;
  return <String, Object?>{
    'id': registry.encodeField(_$OrderModelIdField, m.id),
    'cart_id': registry.encodeField(_$OrderModelCartIdField, m.cartId),
    'customer_id': registry.encodeField(
      _$OrderModelCustomerIdField,
      m.customerId,
    ),
    'status': registry.encodeField(_$OrderModelStatusField, m.status),
    'total_cents': registry.encodeField(
      _$OrderModelTotalCentsField,
      m.totalCents,
    ),
    'payment_reference': registry.encodeField(
      _$OrderModelPaymentReferenceField,
      m.paymentReference,
    ),
  };
}

final ModelDefinition<$OrderModel> _$OrderModelDefinition = ModelDefinition(
  modelName: 'OrderModel',
  tableName: 'orders',
  fields: const [
    _$OrderModelIdField,
    _$OrderModelCartIdField,
    _$OrderModelCustomerIdField,
    _$OrderModelStatusField,
    _$OrderModelTotalCentsField,
    _$OrderModelPaymentReferenceField,
    _$OrderModelCreatedAtField,
    _$OrderModelUpdatedAtField,
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
  untrackedToMap: _encodeOrderModelUntracked,
  codec: _$OrderModelCodec(),
);

extension OrderModelOrmDefinition on OrderModel {
  static ModelDefinition<$OrderModel> get definition => _$OrderModelDefinition;
}

class OrderModels {
  const OrderModels._();

  /// Starts building a query for [$OrderModel].
  ///
  /// {@macro ormed.query}
  static Query<$OrderModel> query([String? connection]) =>
      Model.query<$OrderModel>(connection: connection);

  static Future<$OrderModel?> find(Object id, {String? connection}) =>
      Model.find<$OrderModel>(id, connection: connection);

  static Future<$OrderModel> findOrFail(Object id, {String? connection}) =>
      Model.findOrFail<$OrderModel>(id, connection: connection);

  static Future<List<$OrderModel>> all({String? connection}) =>
      Model.all<$OrderModel>(connection: connection);

  static Future<int> count({String? connection}) =>
      Model.count<$OrderModel>(connection: connection);

  static Future<bool> anyExist({String? connection}) =>
      Model.anyExist<$OrderModel>(connection: connection);

  static Query<$OrderModel> where(
    String column,
    String operator,
    dynamic value, {
    String? connection,
  }) =>
      Model.where<$OrderModel>(column, operator, value, connection: connection);

  static Query<$OrderModel> whereIn(
    String column,
    List<dynamic> values, {
    String? connection,
  }) => Model.whereIn<$OrderModel>(column, values, connection: connection);

  static Query<$OrderModel> orderBy(
    String column, {
    String direction = "asc",
    String? connection,
  }) => Model.orderBy<$OrderModel>(
    column,
    direction: direction,
    connection: connection,
  );

  static Query<$OrderModel> limit(int count, {String? connection}) =>
      Model.limit<$OrderModel>(count, connection: connection);

  /// Creates a [Repository] for [$OrderModel].
  ///
  /// {@macro ormed.repository}
  static Repository<$OrderModel> repo([String? connection]) =>
      Model.repository<$OrderModel>(connection: connection);

  /// Builds a tracked model from a column/value map.
  static $OrderModel fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$OrderModelDefinition.fromMap(data, registry: registry);

  /// Converts a tracked model to a column/value map.
  static Map<String, Object?> toMap(
    $OrderModel model, {
    ValueCodecRegistry? registry,
  }) => _$OrderModelDefinition.toMap(model, registry: registry);
}

class OrderModelFactory {
  const OrderModelFactory._();

  static ModelDefinition<$OrderModel> get definition => _$OrderModelDefinition;

  static ModelCodec<$OrderModel> get codec => definition.codec;

  static OrderModel fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => definition.fromMap(data, registry: registry);

  static Map<String, Object?> toMap(
    OrderModel model, {
    ValueCodecRegistry? registry,
  }) => definition.toMap(model.toTracked(), registry: registry);

  static void registerWith(ModelRegistry registry) =>
      registry.register(definition);

  static ModelFactoryConnection<OrderModel> withConnection(
    QueryContext context,
  ) => ModelFactoryConnection<OrderModel>(
    definition: definition,
    context: context,
  );

  static ModelFactoryBuilder<OrderModel> factory({
    GeneratorProvider? generatorProvider,
  }) => ModelFactoryRegistry.factoryFor<OrderModel>(
    generatorProvider: generatorProvider,
  );
}

class _$OrderModelCodec extends ModelCodec<$OrderModel> {
  const _$OrderModelCodec();
  @override
  Map<String, Object?> encode($OrderModel model, ValueCodecRegistry registry) {
    return <String, Object?>{
      'id': registry.encodeField(_$OrderModelIdField, model.id),
      'cart_id': registry.encodeField(_$OrderModelCartIdField, model.cartId),
      'customer_id': registry.encodeField(
        _$OrderModelCustomerIdField,
        model.customerId,
      ),
      'status': registry.encodeField(_$OrderModelStatusField, model.status),
      'total_cents': registry.encodeField(
        _$OrderModelTotalCentsField,
        model.totalCents,
      ),
      'payment_reference': registry.encodeField(
        _$OrderModelPaymentReferenceField,
        model.paymentReference,
      ),
      if (model.hasAttribute('created_at'))
        'created_at': registry.encodeField(
          _$OrderModelCreatedAtField,
          model.getAttribute<DateTime?>('created_at'),
        ),
      if (model.hasAttribute('updated_at'))
        'updated_at': registry.encodeField(
          _$OrderModelUpdatedAtField,
          model.getAttribute<DateTime?>('updated_at'),
        ),
    };
  }

  @override
  $OrderModel decode(Map<String, Object?> data, ValueCodecRegistry registry) {
    final String orderModelIdValue =
        registry.decodeField<String>(_$OrderModelIdField, data['id']) ??
        (throw StateError('Field id on OrderModel cannot be null.'));
    final String orderModelCartIdValue =
        registry.decodeField<String>(
          _$OrderModelCartIdField,
          data['cart_id'],
        ) ??
        (throw StateError('Field cartId on OrderModel cannot be null.'));
    final String orderModelCustomerIdValue =
        registry.decodeField<String>(
          _$OrderModelCustomerIdField,
          data['customer_id'],
        ) ??
        (throw StateError('Field customerId on OrderModel cannot be null.'));
    final String orderModelStatusValue =
        registry.decodeField<String>(_$OrderModelStatusField, data['status']) ??
        (throw StateError('Field status on OrderModel cannot be null.'));
    final int orderModelTotalCentsValue =
        registry.decodeField<int>(
          _$OrderModelTotalCentsField,
          data['total_cents'],
        ) ??
        (throw StateError('Field totalCents on OrderModel cannot be null.'));
    final String orderModelPaymentReferenceValue =
        registry.decodeField<String>(
          _$OrderModelPaymentReferenceField,
          data['payment_reference'],
        ) ??
        (throw StateError(
          'Field paymentReference on OrderModel cannot be null.',
        ));
    final DateTime? orderModelCreatedAtValue = registry.decodeField<DateTime?>(
      _$OrderModelCreatedAtField,
      data['created_at'],
    );
    final DateTime? orderModelUpdatedAtValue = registry.decodeField<DateTime?>(
      _$OrderModelUpdatedAtField,
      data['updated_at'],
    );
    final model = $OrderModel(
      id: orderModelIdValue,
      cartId: orderModelCartIdValue,
      customerId: orderModelCustomerIdValue,
      status: orderModelStatusValue,
      totalCents: orderModelTotalCentsValue,
      paymentReference: orderModelPaymentReferenceValue,
    );
    model._attachOrmRuntimeMetadata({
      'id': orderModelIdValue,
      'cart_id': orderModelCartIdValue,
      'customer_id': orderModelCustomerIdValue,
      'status': orderModelStatusValue,
      'total_cents': orderModelTotalCentsValue,
      'payment_reference': orderModelPaymentReferenceValue,
      if (data.containsKey('created_at'))
        'created_at': orderModelCreatedAtValue,
      if (data.containsKey('updated_at'))
        'updated_at': orderModelUpdatedAtValue,
    });
    return model;
  }
}

/// Insert DTO for [OrderModel].
///
/// Auto-increment/DB-generated fields are omitted by default.
class OrderModelInsertDto implements InsertDto<$OrderModel> {
  const OrderModelInsertDto({
    this.id,
    this.cartId,
    this.customerId,
    this.status,
    this.totalCents,
    this.paymentReference,
  });
  final String? id;
  final String? cartId;
  final String? customerId;
  final String? status;
  final int? totalCents;
  final String? paymentReference;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      if (cartId != null) 'cart_id': cartId,
      if (customerId != null) 'customer_id': customerId,
      if (status != null) 'status': status,
      if (totalCents != null) 'total_cents': totalCents,
      if (paymentReference != null) 'payment_reference': paymentReference,
    };
  }

  static const _OrderModelInsertDtoCopyWithSentinel _copyWithSentinel =
      _OrderModelInsertDtoCopyWithSentinel();
  OrderModelInsertDto copyWith({
    Object? id = _copyWithSentinel,
    Object? cartId = _copyWithSentinel,
    Object? customerId = _copyWithSentinel,
    Object? status = _copyWithSentinel,
    Object? totalCents = _copyWithSentinel,
    Object? paymentReference = _copyWithSentinel,
  }) {
    return OrderModelInsertDto(
      id: identical(id, _copyWithSentinel) ? this.id : id as String?,
      cartId: identical(cartId, _copyWithSentinel)
          ? this.cartId
          : cartId as String?,
      customerId: identical(customerId, _copyWithSentinel)
          ? this.customerId
          : customerId as String?,
      status: identical(status, _copyWithSentinel)
          ? this.status
          : status as String?,
      totalCents: identical(totalCents, _copyWithSentinel)
          ? this.totalCents
          : totalCents as int?,
      paymentReference: identical(paymentReference, _copyWithSentinel)
          ? this.paymentReference
          : paymentReference as String?,
    );
  }
}

class _OrderModelInsertDtoCopyWithSentinel {
  const _OrderModelInsertDtoCopyWithSentinel();
}

/// Update DTO for [OrderModel].
///
/// All fields are optional; only provided entries are used in SET clauses.
class OrderModelUpdateDto implements UpdateDto<$OrderModel> {
  const OrderModelUpdateDto({
    this.id,
    this.cartId,
    this.customerId,
    this.status,
    this.totalCents,
    this.paymentReference,
  });
  final String? id;
  final String? cartId;
  final String? customerId;
  final String? status;
  final int? totalCents;
  final String? paymentReference;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      if (cartId != null) 'cart_id': cartId,
      if (customerId != null) 'customer_id': customerId,
      if (status != null) 'status': status,
      if (totalCents != null) 'total_cents': totalCents,
      if (paymentReference != null) 'payment_reference': paymentReference,
    };
  }

  static const _OrderModelUpdateDtoCopyWithSentinel _copyWithSentinel =
      _OrderModelUpdateDtoCopyWithSentinel();
  OrderModelUpdateDto copyWith({
    Object? id = _copyWithSentinel,
    Object? cartId = _copyWithSentinel,
    Object? customerId = _copyWithSentinel,
    Object? status = _copyWithSentinel,
    Object? totalCents = _copyWithSentinel,
    Object? paymentReference = _copyWithSentinel,
  }) {
    return OrderModelUpdateDto(
      id: identical(id, _copyWithSentinel) ? this.id : id as String?,
      cartId: identical(cartId, _copyWithSentinel)
          ? this.cartId
          : cartId as String?,
      customerId: identical(customerId, _copyWithSentinel)
          ? this.customerId
          : customerId as String?,
      status: identical(status, _copyWithSentinel)
          ? this.status
          : status as String?,
      totalCents: identical(totalCents, _copyWithSentinel)
          ? this.totalCents
          : totalCents as int?,
      paymentReference: identical(paymentReference, _copyWithSentinel)
          ? this.paymentReference
          : paymentReference as String?,
    );
  }
}

class _OrderModelUpdateDtoCopyWithSentinel {
  const _OrderModelUpdateDtoCopyWithSentinel();
}

/// Partial projection for [OrderModel].
///
/// All fields are nullable; intended for subset SELECTs.
class OrderModelPartial implements PartialEntity<$OrderModel> {
  const OrderModelPartial({
    this.id,
    this.cartId,
    this.customerId,
    this.status,
    this.totalCents,
    this.paymentReference,
  });

  /// Creates a partial from a database row map.
  ///
  /// The [row] keys should be column names (snake_case).
  /// Missing columns will result in null field values.
  factory OrderModelPartial.fromRow(Map<String, Object?> row) {
    return OrderModelPartial(
      id: row['id'] as String?,
      cartId: row['cart_id'] as String?,
      customerId: row['customer_id'] as String?,
      status: row['status'] as String?,
      totalCents: row['total_cents'] as int?,
      paymentReference: row['payment_reference'] as String?,
    );
  }

  final String? id;
  final String? cartId;
  final String? customerId;
  final String? status;
  final int? totalCents;
  final String? paymentReference;

  @override
  $OrderModel toEntity() {
    // Basic required-field check: non-nullable fields must be present.
    final String? idValue = id;
    if (idValue == null) {
      throw StateError('Missing required field: id');
    }
    final String? cartIdValue = cartId;
    if (cartIdValue == null) {
      throw StateError('Missing required field: cartId');
    }
    final String? customerIdValue = customerId;
    if (customerIdValue == null) {
      throw StateError('Missing required field: customerId');
    }
    final String? statusValue = status;
    if (statusValue == null) {
      throw StateError('Missing required field: status');
    }
    final int? totalCentsValue = totalCents;
    if (totalCentsValue == null) {
      throw StateError('Missing required field: totalCents');
    }
    final String? paymentReferenceValue = paymentReference;
    if (paymentReferenceValue == null) {
      throw StateError('Missing required field: paymentReference');
    }
    return $OrderModel(
      id: idValue,
      cartId: cartIdValue,
      customerId: customerIdValue,
      status: statusValue,
      totalCents: totalCentsValue,
      paymentReference: paymentReferenceValue,
    );
  }

  @override
  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      if (cartId != null) 'cart_id': cartId,
      if (customerId != null) 'customer_id': customerId,
      if (status != null) 'status': status,
      if (totalCents != null) 'total_cents': totalCents,
      if (paymentReference != null) 'payment_reference': paymentReference,
    };
  }

  static const _OrderModelPartialCopyWithSentinel _copyWithSentinel =
      _OrderModelPartialCopyWithSentinel();
  OrderModelPartial copyWith({
    Object? id = _copyWithSentinel,
    Object? cartId = _copyWithSentinel,
    Object? customerId = _copyWithSentinel,
    Object? status = _copyWithSentinel,
    Object? totalCents = _copyWithSentinel,
    Object? paymentReference = _copyWithSentinel,
  }) {
    return OrderModelPartial(
      id: identical(id, _copyWithSentinel) ? this.id : id as String?,
      cartId: identical(cartId, _copyWithSentinel)
          ? this.cartId
          : cartId as String?,
      customerId: identical(customerId, _copyWithSentinel)
          ? this.customerId
          : customerId as String?,
      status: identical(status, _copyWithSentinel)
          ? this.status
          : status as String?,
      totalCents: identical(totalCents, _copyWithSentinel)
          ? this.totalCents
          : totalCents as int?,
      paymentReference: identical(paymentReference, _copyWithSentinel)
          ? this.paymentReference
          : paymentReference as String?,
    );
  }
}

class _OrderModelPartialCopyWithSentinel {
  const _OrderModelPartialCopyWithSentinel();
}

/// Generated tracked model class for [OrderModel].
///
/// This class extends the user-defined [OrderModel] model and adds
/// attribute tracking, change detection, and relationship management.
/// Instances of this class are returned by queries and repositories.
///
/// **Do not instantiate this class directly.** Use queries, repositories,
/// or model factories to create tracked model instances.
class $OrderModel extends OrderModel
    with ModelAttributes, TimestampsTZImpl
    implements OrmEntity {
  /// Internal constructor for [$OrderModel].
  $OrderModel({
    required String id,
    required String cartId,
    required String customerId,
    required String status,
    required int totalCents,
    required String paymentReference,
  }) : super(
         id: id,
         cartId: cartId,
         customerId: customerId,
         status: status,
         totalCents: totalCents,
         paymentReference: paymentReference,
       ) {
    _attachOrmRuntimeMetadata({
      'id': id,
      'cart_id': cartId,
      'customer_id': customerId,
      'status': status,
      'total_cents': totalCents,
      'payment_reference': paymentReference,
    });
  }

  /// Creates a tracked model instance from a user-defined model instance.
  factory $OrderModel.fromModel(OrderModel model) {
    return $OrderModel(
      id: model.id,
      cartId: model.cartId,
      customerId: model.customerId,
      status: model.status,
      totalCents: model.totalCents,
      paymentReference: model.paymentReference,
    );
  }

  $OrderModel copyWith({
    String? id,
    String? cartId,
    String? customerId,
    String? status,
    int? totalCents,
    String? paymentReference,
  }) {
    return $OrderModel(
      id: id ?? this.id,
      cartId: cartId ?? this.cartId,
      customerId: customerId ?? this.customerId,
      status: status ?? this.status,
      totalCents: totalCents ?? this.totalCents,
      paymentReference: paymentReference ?? this.paymentReference,
    );
  }

  /// Builds a tracked model from a column/value map.
  static $OrderModel fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$OrderModelDefinition.fromMap(data, registry: registry);

  /// Converts this tracked model to a column/value map.
  Map<String, Object?> toMap({ValueCodecRegistry? registry}) =>
      _$OrderModelDefinition.toMap(this, registry: registry);

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

  /// Tracked getter for [totalCents].
  @override
  int get totalCents => getAttribute<int>('total_cents') ?? super.totalCents;

  /// Tracked setter for [totalCents].
  set totalCents(int value) => setAttribute('total_cents', value);

  /// Tracked getter for [paymentReference].
  @override
  String get paymentReference =>
      getAttribute<String>('payment_reference') ?? super.paymentReference;

  /// Tracked setter for [paymentReference].
  set paymentReference(String value) =>
      setAttribute('payment_reference', value);

  void _attachOrmRuntimeMetadata(Map<String, Object?> values) {
    replaceAttributes(values);
    attachModelDefinition(_$OrderModelDefinition);
  }
}

class _OrderModelCopyWithSentinel {
  const _OrderModelCopyWithSentinel();
}

extension OrderModelOrmExtension on OrderModel {
  static const _OrderModelCopyWithSentinel _copyWithSentinel =
      _OrderModelCopyWithSentinel();
  OrderModel copyWith({
    Object? id = _copyWithSentinel,
    Object? cartId = _copyWithSentinel,
    Object? customerId = _copyWithSentinel,
    Object? status = _copyWithSentinel,
    Object? totalCents = _copyWithSentinel,
    Object? paymentReference = _copyWithSentinel,
  }) {
    return OrderModel(
      id: identical(id, _copyWithSentinel) ? this.id : id as String,
      cartId: identical(cartId, _copyWithSentinel)
          ? this.cartId
          : cartId as String,
      customerId: identical(customerId, _copyWithSentinel)
          ? this.customerId
          : customerId as String,
      status: identical(status, _copyWithSentinel)
          ? this.status
          : status as String,
      totalCents: identical(totalCents, _copyWithSentinel)
          ? this.totalCents
          : totalCents as int,
      paymentReference: identical(paymentReference, _copyWithSentinel)
          ? this.paymentReference
          : paymentReference as String,
    );
  }

  /// Converts this model to a column/value map.
  Map<String, Object?> toMap({ValueCodecRegistry? registry}) =>
      _$OrderModelDefinition.toMap(this, registry: registry);

  /// Builds a model from a column/value map.
  static OrderModel fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$OrderModelDefinition.fromMap(data, registry: registry);

  /// The Type of the generated ORM-managed model class.
  /// Use this when you need to specify the tracked model type explicitly,
  /// for example in generic type parameters.
  static Type get trackedType => $OrderModel;

  /// Converts this immutable model to a tracked ORM-managed model.
  /// The tracked model supports attribute tracking, change detection,
  /// and persistence operations like save() and touch().
  $OrderModel toTracked() {
    return $OrderModel.fromModel(this);
  }
}

extension OrderModelPredicateFields on PredicateBuilder<OrderModel> {
  PredicateField<OrderModel, String> get id =>
      PredicateField<OrderModel, String>(this, 'id');
  PredicateField<OrderModel, String> get cartId =>
      PredicateField<OrderModel, String>(this, 'cartId');
  PredicateField<OrderModel, String> get customerId =>
      PredicateField<OrderModel, String>(this, 'customerId');
  PredicateField<OrderModel, String> get status =>
      PredicateField<OrderModel, String>(this, 'status');
  PredicateField<OrderModel, int> get totalCents =>
      PredicateField<OrderModel, int>(this, 'totalCents');
  PredicateField<OrderModel, String> get paymentReference =>
      PredicateField<OrderModel, String>(this, 'paymentReference');
}

void registerOrderModelEventHandlers(EventBus bus) {
  // No event handlers registered for OrderModel.
}
