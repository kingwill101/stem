// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'stem_broadcast_ack.dart';

// **************************************************************************
// OrmModelGenerator
// **************************************************************************

const FieldDefinition _$StemBroadcastAckMessageIdField = FieldDefinition(
  name: 'messageId',
  columnName: 'message_id',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: true,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemBroadcastAckWorkerIdField = FieldDefinition(
  name: 'workerId',
  columnName: 'worker_id',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: true,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemBroadcastAckAcknowledgedAtField = FieldDefinition(
  name: 'acknowledgedAt',
  columnName: 'acknowledged_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime?',
  isPrimaryKey: false,
  isNullable: true,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemBroadcastAckCreatedAtField = FieldDefinition(
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

const FieldDefinition _$StemBroadcastAckUpdatedAtField = FieldDefinition(
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

Map<String, Object?> _encodeStemBroadcastAckUntracked(
  Object model,
  ValueCodecRegistry registry,
) {
  final m = model as StemBroadcastAck;
  return <String, Object?>{
    'message_id': registry.encodeField(
      _$StemBroadcastAckMessageIdField,
      m.messageId,
    ),
    'worker_id': registry.encodeField(
      _$StemBroadcastAckWorkerIdField,
      m.workerId,
    ),
    'acknowledged_at': registry.encodeField(
      _$StemBroadcastAckAcknowledgedAtField,
      m.acknowledgedAt,
    ),
  };
}

final ModelDefinition<$StemBroadcastAck> _$StemBroadcastAckDefinition =
    ModelDefinition(
      modelName: 'StemBroadcastAck',
      tableName: 'stem_broadcast_ack',
      fields: const [
        _$StemBroadcastAckMessageIdField,
        _$StemBroadcastAckWorkerIdField,
        _$StemBroadcastAckAcknowledgedAtField,
        _$StemBroadcastAckCreatedAtField,
        _$StemBroadcastAckUpdatedAtField,
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
      untrackedToMap: _encodeStemBroadcastAckUntracked,
      codec: _$StemBroadcastAckCodec(),
    );

extension StemBroadcastAckOrmDefinition on StemBroadcastAck {
  static ModelDefinition<$StemBroadcastAck> get definition =>
      _$StemBroadcastAckDefinition;
}

class StemBroadcastAcks {
  const StemBroadcastAcks._();

  /// Starts building a query for [$StemBroadcastAck].
  ///
  /// {@macro ormed.query}
  static Query<$StemBroadcastAck> query([String? connection]) =>
      Model.query<$StemBroadcastAck>(connection: connection);

  static Future<$StemBroadcastAck?> find(Object id, {String? connection}) =>
      Model.find<$StemBroadcastAck>(id, connection: connection);

  static Future<$StemBroadcastAck> findOrFail(
    Object id, {
    String? connection,
  }) => Model.findOrFail<$StemBroadcastAck>(id, connection: connection);

  static Future<List<$StemBroadcastAck>> all({String? connection}) =>
      Model.all<$StemBroadcastAck>(connection: connection);

  static Future<int> count({String? connection}) =>
      Model.count<$StemBroadcastAck>(connection: connection);

  static Future<bool> anyExist({String? connection}) =>
      Model.anyExist<$StemBroadcastAck>(connection: connection);

  static Query<$StemBroadcastAck> where(
    String column,
    String operator,
    dynamic value, {
    String? connection,
  }) => Model.where<$StemBroadcastAck>(
    column,
    operator,
    value,
    connection: connection,
  );

  static Query<$StemBroadcastAck> whereIn(
    String column,
    List<dynamic> values, {
    String? connection,
  }) =>
      Model.whereIn<$StemBroadcastAck>(column, values, connection: connection);

  static Query<$StemBroadcastAck> orderBy(
    String column, {
    String direction = "asc",
    String? connection,
  }) => Model.orderBy<$StemBroadcastAck>(
    column,
    direction: direction,
    connection: connection,
  );

  static Query<$StemBroadcastAck> limit(int count, {String? connection}) =>
      Model.limit<$StemBroadcastAck>(count, connection: connection);

  /// Creates a [Repository] for [$StemBroadcastAck].
  ///
  /// {@macro ormed.repository}
  static Repository<$StemBroadcastAck> repo([String? connection]) =>
      Model.repository<$StemBroadcastAck>(connection: connection);
}

class StemBroadcastAckModelFactory {
  const StemBroadcastAckModelFactory._();

  static ModelDefinition<$StemBroadcastAck> get definition =>
      _$StemBroadcastAckDefinition;

  static ModelCodec<$StemBroadcastAck> get codec => definition.codec;

  static StemBroadcastAck fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => definition.fromMap(data, registry: registry);

  static Map<String, Object?> toMap(
    StemBroadcastAck model, {
    ValueCodecRegistry? registry,
  }) => definition.toMap(model.toTracked(), registry: registry);

  static void registerWith(ModelRegistry registry) =>
      registry.register(definition);

  static ModelFactoryConnection<StemBroadcastAck> withConnection(
    QueryContext context,
  ) => ModelFactoryConnection<StemBroadcastAck>(
    definition: definition,
    context: context,
  );

  static ModelFactoryBuilder<StemBroadcastAck> factory({
    GeneratorProvider? generatorProvider,
  }) => ModelFactoryBuilder<StemBroadcastAck>(
    definition: definition,
    generatorProvider: generatorProvider,
  );
}

class _$StemBroadcastAckCodec extends ModelCodec<$StemBroadcastAck> {
  const _$StemBroadcastAckCodec();
  @override
  Map<String, Object?> encode(
    $StemBroadcastAck model,
    ValueCodecRegistry registry,
  ) {
    return <String, Object?>{
      'message_id': registry.encodeField(
        _$StemBroadcastAckMessageIdField,
        model.messageId,
      ),
      'worker_id': registry.encodeField(
        _$StemBroadcastAckWorkerIdField,
        model.workerId,
      ),
      'acknowledged_at': registry.encodeField(
        _$StemBroadcastAckAcknowledgedAtField,
        model.acknowledgedAt,
      ),
      if (model.hasAttribute('created_at'))
        'created_at': registry.encodeField(
          _$StemBroadcastAckCreatedAtField,
          model.getAttribute<DateTime?>('created_at'),
        ),
      if (model.hasAttribute('updated_at'))
        'updated_at': registry.encodeField(
          _$StemBroadcastAckUpdatedAtField,
          model.getAttribute<DateTime?>('updated_at'),
        ),
    };
  }

  @override
  $StemBroadcastAck decode(
    Map<String, Object?> data,
    ValueCodecRegistry registry,
  ) {
    final String stemBroadcastAckMessageIdValue =
        registry.decodeField<String>(
          _$StemBroadcastAckMessageIdField,
          data['message_id'],
        ) ??
        (throw StateError(
          'Field messageId on StemBroadcastAck cannot be null.',
        ));
    final String stemBroadcastAckWorkerIdValue =
        registry.decodeField<String>(
          _$StemBroadcastAckWorkerIdField,
          data['worker_id'],
        ) ??
        (throw StateError(
          'Field workerId on StemBroadcastAck cannot be null.',
        ));
    final DateTime? stemBroadcastAckAcknowledgedAtValue = registry
        .decodeField<DateTime?>(
          _$StemBroadcastAckAcknowledgedAtField,
          data['acknowledged_at'],
        );
    final DateTime? stemBroadcastAckCreatedAtValue = registry
        .decodeField<DateTime?>(
          _$StemBroadcastAckCreatedAtField,
          data['created_at'],
        );
    final DateTime? stemBroadcastAckUpdatedAtValue = registry
        .decodeField<DateTime?>(
          _$StemBroadcastAckUpdatedAtField,
          data['updated_at'],
        );
    final model = $StemBroadcastAck(
      messageId: stemBroadcastAckMessageIdValue,
      workerId: stemBroadcastAckWorkerIdValue,
      acknowledgedAt: stemBroadcastAckAcknowledgedAtValue,
    );
    model._attachOrmRuntimeMetadata({
      'message_id': stemBroadcastAckMessageIdValue,
      'worker_id': stemBroadcastAckWorkerIdValue,
      'acknowledged_at': stemBroadcastAckAcknowledgedAtValue,
      if (data.containsKey('created_at'))
        'created_at': stemBroadcastAckCreatedAtValue,
      if (data.containsKey('updated_at'))
        'updated_at': stemBroadcastAckUpdatedAtValue,
    });
    return model;
  }
}

/// Insert DTO for [StemBroadcastAck].
///
/// Auto-increment/DB-generated fields are omitted by default.
class StemBroadcastAckInsertDto implements InsertDto<$StemBroadcastAck> {
  const StemBroadcastAckInsertDto({
    this.messageId,
    this.workerId,
    this.acknowledgedAt,
  });
  final String? messageId;
  final String? workerId;
  final DateTime? acknowledgedAt;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (messageId != null) 'message_id': messageId,
      if (workerId != null) 'worker_id': workerId,
      if (acknowledgedAt != null) 'acknowledged_at': acknowledgedAt,
    };
  }

  static const _StemBroadcastAckInsertDtoCopyWithSentinel _copyWithSentinel =
      _StemBroadcastAckInsertDtoCopyWithSentinel();
  StemBroadcastAckInsertDto copyWith({
    Object? messageId = _copyWithSentinel,
    Object? workerId = _copyWithSentinel,
    Object? acknowledgedAt = _copyWithSentinel,
  }) {
    return StemBroadcastAckInsertDto(
      messageId: identical(messageId, _copyWithSentinel)
          ? this.messageId
          : messageId as String?,
      workerId: identical(workerId, _copyWithSentinel)
          ? this.workerId
          : workerId as String?,
      acknowledgedAt: identical(acknowledgedAt, _copyWithSentinel)
          ? this.acknowledgedAt
          : acknowledgedAt as DateTime?,
    );
  }
}

class _StemBroadcastAckInsertDtoCopyWithSentinel {
  const _StemBroadcastAckInsertDtoCopyWithSentinel();
}

/// Update DTO for [StemBroadcastAck].
///
/// All fields are optional; only provided entries are used in SET clauses.
class StemBroadcastAckUpdateDto implements UpdateDto<$StemBroadcastAck> {
  const StemBroadcastAckUpdateDto({
    this.messageId,
    this.workerId,
    this.acknowledgedAt,
  });
  final String? messageId;
  final String? workerId;
  final DateTime? acknowledgedAt;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (messageId != null) 'message_id': messageId,
      if (workerId != null) 'worker_id': workerId,
      if (acknowledgedAt != null) 'acknowledged_at': acknowledgedAt,
    };
  }

  static const _StemBroadcastAckUpdateDtoCopyWithSentinel _copyWithSentinel =
      _StemBroadcastAckUpdateDtoCopyWithSentinel();
  StemBroadcastAckUpdateDto copyWith({
    Object? messageId = _copyWithSentinel,
    Object? workerId = _copyWithSentinel,
    Object? acknowledgedAt = _copyWithSentinel,
  }) {
    return StemBroadcastAckUpdateDto(
      messageId: identical(messageId, _copyWithSentinel)
          ? this.messageId
          : messageId as String?,
      workerId: identical(workerId, _copyWithSentinel)
          ? this.workerId
          : workerId as String?,
      acknowledgedAt: identical(acknowledgedAt, _copyWithSentinel)
          ? this.acknowledgedAt
          : acknowledgedAt as DateTime?,
    );
  }
}

class _StemBroadcastAckUpdateDtoCopyWithSentinel {
  const _StemBroadcastAckUpdateDtoCopyWithSentinel();
}

/// Partial projection for [StemBroadcastAck].
///
/// All fields are nullable; intended for subset SELECTs.
class StemBroadcastAckPartial implements PartialEntity<$StemBroadcastAck> {
  const StemBroadcastAckPartial({
    this.messageId,
    this.workerId,
    this.acknowledgedAt,
  });

  /// Creates a partial from a database row map.
  ///
  /// The [row] keys should be column names (snake_case).
  /// Missing columns will result in null field values.
  factory StemBroadcastAckPartial.fromRow(Map<String, Object?> row) {
    return StemBroadcastAckPartial(
      messageId: row['message_id'] as String?,
      workerId: row['worker_id'] as String?,
      acknowledgedAt: row['acknowledged_at'] as DateTime?,
    );
  }

  final String? messageId;
  final String? workerId;
  final DateTime? acknowledgedAt;

  @override
  $StemBroadcastAck toEntity() {
    // Basic required-field check: non-nullable fields must be present.
    final String? messageIdValue = messageId;
    if (messageIdValue == null) {
      throw StateError('Missing required field: messageId');
    }
    final String? workerIdValue = workerId;
    if (workerIdValue == null) {
      throw StateError('Missing required field: workerId');
    }
    return $StemBroadcastAck(
      messageId: messageIdValue,
      workerId: workerIdValue,
      acknowledgedAt: acknowledgedAt,
    );
  }

  @override
  Map<String, Object?> toMap() {
    return {
      if (messageId != null) 'message_id': messageId,
      if (workerId != null) 'worker_id': workerId,
      if (acknowledgedAt != null) 'acknowledged_at': acknowledgedAt,
    };
  }

  static const _StemBroadcastAckPartialCopyWithSentinel _copyWithSentinel =
      _StemBroadcastAckPartialCopyWithSentinel();
  StemBroadcastAckPartial copyWith({
    Object? messageId = _copyWithSentinel,
    Object? workerId = _copyWithSentinel,
    Object? acknowledgedAt = _copyWithSentinel,
  }) {
    return StemBroadcastAckPartial(
      messageId: identical(messageId, _copyWithSentinel)
          ? this.messageId
          : messageId as String?,
      workerId: identical(workerId, _copyWithSentinel)
          ? this.workerId
          : workerId as String?,
      acknowledgedAt: identical(acknowledgedAt, _copyWithSentinel)
          ? this.acknowledgedAt
          : acknowledgedAt as DateTime?,
    );
  }
}

class _StemBroadcastAckPartialCopyWithSentinel {
  const _StemBroadcastAckPartialCopyWithSentinel();
}

/// Generated tracked model class for [StemBroadcastAck].
///
/// This class extends the user-defined [StemBroadcastAck] model and adds
/// attribute tracking, change detection, and relationship management.
/// Instances of this class are returned by queries and repositories.
///
/// **Do not instantiate this class directly.** Use queries, repositories,
/// or model factories to create tracked model instances.
class $StemBroadcastAck extends StemBroadcastAck
    with ModelAttributes, TimestampsTZImpl
    implements OrmEntity {
  /// Internal constructor for [$StemBroadcastAck].
  $StemBroadcastAck({
    required String messageId,
    required String workerId,
    DateTime? acknowledgedAt,
  }) : super.new(
         messageId: messageId,
         workerId: workerId,
         acknowledgedAt: acknowledgedAt,
       ) {
    _attachOrmRuntimeMetadata({
      'message_id': messageId,
      'worker_id': workerId,
      'acknowledged_at': acknowledgedAt,
    });
  }

  /// Creates a tracked model instance from a user-defined model instance.
  factory $StemBroadcastAck.fromModel(StemBroadcastAck model) {
    return $StemBroadcastAck(
      messageId: model.messageId,
      workerId: model.workerId,
      acknowledgedAt: model.acknowledgedAt,
    );
  }

  $StemBroadcastAck copyWith({
    String? messageId,
    String? workerId,
    DateTime? acknowledgedAt,
  }) {
    return $StemBroadcastAck(
      messageId: messageId ?? this.messageId,
      workerId: workerId ?? this.workerId,
      acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
    );
  }

  /// Tracked getter for [messageId].
  @override
  String get messageId => getAttribute<String>('message_id') ?? super.messageId;

  /// Tracked setter for [messageId].
  set messageId(String value) => setAttribute('message_id', value);

  /// Tracked getter for [workerId].
  @override
  String get workerId => getAttribute<String>('worker_id') ?? super.workerId;

  /// Tracked setter for [workerId].
  set workerId(String value) => setAttribute('worker_id', value);

  /// Tracked getter for [acknowledgedAt].
  @override
  DateTime? get acknowledgedAt =>
      getAttribute<DateTime?>('acknowledged_at') ?? super.acknowledgedAt;

  /// Tracked setter for [acknowledgedAt].
  set acknowledgedAt(DateTime? value) => setAttribute('acknowledged_at', value);

  void _attachOrmRuntimeMetadata(Map<String, Object?> values) {
    replaceAttributes(values);
    attachModelDefinition(_$StemBroadcastAckDefinition);
  }
}

extension StemBroadcastAckOrmExtension on StemBroadcastAck {
  /// The Type of the generated ORM-managed model class.
  /// Use this when you need to specify the tracked model type explicitly,
  /// for example in generic type parameters.
  static Type get trackedType => $StemBroadcastAck;

  /// Converts this immutable model to a tracked ORM-managed model.
  /// The tracked model supports attribute tracking, change detection,
  /// and persistence operations like save() and touch().
  $StemBroadcastAck toTracked() {
    return $StemBroadcastAck.fromModel(this);
  }
}

void registerStemBroadcastAckEventHandlers(EventBus bus) {
  // No event handlers registered for StemBroadcastAck.
}
