// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'stem_task_result.dart';

// **************************************************************************
// OrmModelGenerator
// **************************************************************************

const FieldDefinition _$StemTaskResultIdField = FieldDefinition(
  name: 'id',
  columnName: 'id',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: true,
  isNullable: false,
);

const FieldDefinition _$StemTaskResultStateField = FieldDefinition(
  name: 'state',
  columnName: 'state',
  dartType: 'String',
  resolvedType: 'String',
  isNullable: false,
);

const FieldDefinition _$StemTaskResultPayloadField = FieldDefinition(
  name: 'payload',
  columnName: 'payload',
  dartType: 'Object',
  resolvedType: 'Object?',
  isNullable: true,
  codecType: 'json',
);

const FieldDefinition _$StemTaskResultErrorField = FieldDefinition(
  name: 'error',
  columnName: 'error',
  dartType: 'Object',
  resolvedType: 'Object?',
  isNullable: true,
  codecType: 'json',
);

const FieldDefinition _$StemTaskResultAttemptField = FieldDefinition(
  name: 'attempt',
  columnName: 'attempt',
  dartType: 'int',
  resolvedType: 'int',
  isNullable: false,
);

const FieldDefinition _$StemTaskResultMetaField = FieldDefinition(
  name: 'meta',
  columnName: 'meta',
  dartType: 'Map<String, Object?>',
  resolvedType: 'Map<String, Object?>',
  isNullable: false,
  codecType: 'json',
);

const FieldDefinition _$StemTaskResultExpiresAtField = FieldDefinition(
  name: 'expiresAt',
  columnName: 'expires_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime',
  isNullable: false,
);

const FieldDefinition _$StemTaskResultCreatedAtField = FieldDefinition(
  name: 'createdAt',
  columnName: 'created_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime?',
  isNullable: true,
);

const FieldDefinition _$StemTaskResultUpdatedAtField = FieldDefinition(
  name: 'updatedAt',
  columnName: 'updated_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime?',
  isNullable: true,
);

Map<String, Object?> _encodeStemTaskResultUntracked(
  Object model,
  ValueCodecRegistry registry,
) {
  final m = model as StemTaskResult;
  return <String, Object?>{
    'id': registry.encodeField(_$StemTaskResultIdField, m.id),
    'state': registry.encodeField(_$StemTaskResultStateField, m.state),
    'payload': registry.encodeField(_$StemTaskResultPayloadField, m.payload),
    'error': registry.encodeField(_$StemTaskResultErrorField, m.error),
    'attempt': registry.encodeField(_$StemTaskResultAttemptField, m.attempt),
    'meta': registry.encodeField(_$StemTaskResultMetaField, m.meta),
    'expires_at': registry.encodeField(
      _$StemTaskResultExpiresAtField,
      m.expiresAt,
    ),
  };
}

const ModelDefinition<$StemTaskResult> _$StemTaskResultDefinition =
    ModelDefinition(
      modelName: 'StemTaskResult',
      tableName: 'stem_task_results',
      fields: [
        _$StemTaskResultIdField,
        _$StemTaskResultStateField,
        _$StemTaskResultPayloadField,
        _$StemTaskResultErrorField,
        _$StemTaskResultAttemptField,
        _$StemTaskResultMetaField,
        _$StemTaskResultExpiresAtField,
        _$StemTaskResultCreatedAtField,
        _$StemTaskResultUpdatedAtField,
      ],
      softDeleteColumn: 'deleted_at',
      metadata: ModelAttributesMetadata(
        fieldOverrides: {
          'payload': FieldAttributeMetadata(cast: 'json'),
          'error': FieldAttributeMetadata(cast: 'json'),
          'meta': FieldAttributeMetadata(cast: 'json'),
        },
      ),
      untrackedToMap: _encodeStemTaskResultUntracked,
      codec: _$StemTaskResultCodec(),
    );

extension StemTaskResultOrmDefinition on StemTaskResult {
  static ModelDefinition<$StemTaskResult> get definition =>
      _$StemTaskResultDefinition;
}

class StemTaskResults {
  const StemTaskResults._();

  /// Starts building a query for [$StemTaskResult].
  ///
  /// {@macro ormed.query}
  static Query<$StemTaskResult> query([String? connection]) =>
      Model.query<$StemTaskResult>(connection: connection);

  static Future<$StemTaskResult?> find(Object id, {String? connection}) =>
      Model.find<$StemTaskResult>(id, connection: connection);

  static Future<$StemTaskResult> findOrFail(Object id, {String? connection}) =>
      Model.findOrFail<$StemTaskResult>(id, connection: connection);

  static Future<List<$StemTaskResult>> all({String? connection}) =>
      Model.all<$StemTaskResult>(connection: connection);

  static Future<int> count({String? connection}) =>
      Model.count<$StemTaskResult>(connection: connection);

  static Future<bool> anyExist({String? connection}) =>
      Model.anyExist<$StemTaskResult>(connection: connection);

  static Query<$StemTaskResult> where(
    String column,
    String operator,
    dynamic value, {
    String? connection,
  }) => Model.where<$StemTaskResult>(
    column,
    operator,
    value,
    connection: connection,
  );

  static Query<$StemTaskResult> whereIn(
    String column,
    List<dynamic> values, {
    String? connection,
  }) => Model.whereIn<$StemTaskResult>(column, values, connection: connection);

  static Query<$StemTaskResult> orderBy(
    String column, {
    String direction = 'asc',
    String? connection,
  }) => Model.orderBy<$StemTaskResult>(
    column,
    direction: direction,
    connection: connection,
  );

  static Query<$StemTaskResult> limit(int count, {String? connection}) =>
      Model.limit<$StemTaskResult>(count, connection: connection);

  /// Creates a [Repository] for [$StemTaskResult].
  ///
  /// {@macro ormed.repository}
  static Repository<$StemTaskResult> repo([String? connection]) =>
      Model.repository<$StemTaskResult>(connection: connection);
}

class StemTaskResultModelFactory {
  const StemTaskResultModelFactory._();

  static ModelDefinition<$StemTaskResult> get definition =>
      _$StemTaskResultDefinition;

  static ModelCodec<$StemTaskResult> get codec => definition.codec;

  static StemTaskResult fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => definition.fromMap(data, registry: registry);

  static Map<String, Object?> toMap(
    StemTaskResult model, {
    ValueCodecRegistry? registry,
  }) => definition.toMap(model.toTracked(), registry: registry);

  static void registerWith(ModelRegistry registry) =>
      registry.register(definition);

  static ModelFactoryConnection<StemTaskResult> withConnection(
    QueryContext context,
  ) => ModelFactoryConnection<StemTaskResult>(
    definition: definition,
    context: context,
  );

  static ModelFactoryBuilder<StemTaskResult> factory({
    GeneratorProvider? generatorProvider,
  }) => ModelFactoryBuilder<StemTaskResult>(
    definition: definition,
    generatorProvider: generatorProvider,
  );
}

class _$StemTaskResultCodec extends ModelCodec<$StemTaskResult> {
  const _$StemTaskResultCodec();
  @override
  Map<String, Object?> encode(
    $StemTaskResult model,
    ValueCodecRegistry registry,
  ) {
    return <String, Object?>{
      'id': registry.encodeField(_$StemTaskResultIdField, model.id),
      'state': registry.encodeField(_$StemTaskResultStateField, model.state),
      'payload': registry.encodeField(
        _$StemTaskResultPayloadField,
        model.payload,
      ),
      'error': registry.encodeField(_$StemTaskResultErrorField, model.error),
      'attempt': registry.encodeField(
        _$StemTaskResultAttemptField,
        model.attempt,
      ),
      'meta': registry.encodeField(_$StemTaskResultMetaField, model.meta),
      'expires_at': registry.encodeField(
        _$StemTaskResultExpiresAtField,
        model.expiresAt,
      ),
      if (model.hasAttribute('created_at'))
        'created_at': registry.encodeField(
          _$StemTaskResultCreatedAtField,
          model.getAttribute<DateTime?>('created_at'),
        ),
      if (model.hasAttribute('updated_at'))
        'updated_at': registry.encodeField(
          _$StemTaskResultUpdatedAtField,
          model.getAttribute<DateTime?>('updated_at'),
        ),
    };
  }

  @override
  $StemTaskResult decode(
    Map<String, Object?> data,
    ValueCodecRegistry registry,
  ) {
    final stemTaskResultIdValue =
        registry.decodeField<String>(_$StemTaskResultIdField, data['id']) ??
        (throw StateError('Field id on StemTaskResult cannot be null.'));
    final stemTaskResultStateValue =
        registry.decodeField<String>(
          _$StemTaskResultStateField,
          data['state'],
        ) ??
        (throw StateError('Field state on StemTaskResult cannot be null.'));
    final stemTaskResultPayloadValue = registry.decodeField<Object?>(
      _$StemTaskResultPayloadField,
      data['payload'],
    );
    final stemTaskResultErrorValue = registry.decodeField<Object?>(
      _$StemTaskResultErrorField,
      data['error'],
    );
    final stemTaskResultAttemptValue =
        registry.decodeField<int>(
          _$StemTaskResultAttemptField,
          data['attempt'],
        ) ??
        (throw StateError('Field attempt on StemTaskResult cannot be null.'));
    final stemTaskResultMetaValue =
        registry.decodeField<Map<String, Object?>>(
          _$StemTaskResultMetaField,
          data['meta'],
        ) ??
        (throw StateError('Field meta on StemTaskResult cannot be null.'));
    final stemTaskResultExpiresAtValue =
        registry.decodeField<DateTime>(
          _$StemTaskResultExpiresAtField,
          data['expires_at'],
        ) ??
        (throw StateError('Field expiresAt on StemTaskResult cannot be null.'));
    final stemTaskResultCreatedAtValue = registry.decodeField<DateTime?>(
      _$StemTaskResultCreatedAtField,
      data['created_at'],
    );
    final stemTaskResultUpdatedAtValue = registry.decodeField<DateTime?>(
      _$StemTaskResultUpdatedAtField,
      data['updated_at'],
    );
    final model = $StemTaskResult(
      id: stemTaskResultIdValue,
      state: stemTaskResultStateValue,
      payload: stemTaskResultPayloadValue,
      error: stemTaskResultErrorValue,
      attempt: stemTaskResultAttemptValue,
      meta: stemTaskResultMetaValue,
      expiresAt: stemTaskResultExpiresAtValue,
    );
    model._attachOrmRuntimeMetadata({
      'id': stemTaskResultIdValue,
      'state': stemTaskResultStateValue,
      'payload': stemTaskResultPayloadValue,
      'error': stemTaskResultErrorValue,
      'attempt': stemTaskResultAttemptValue,
      'meta': stemTaskResultMetaValue,
      'expires_at': stemTaskResultExpiresAtValue,
      if (data.containsKey('created_at'))
        'created_at': stemTaskResultCreatedAtValue,
      if (data.containsKey('updated_at'))
        'updated_at': stemTaskResultUpdatedAtValue,
    });
    return model;
  }
}

/// Insert DTO for [StemTaskResult].
///
/// Auto-increment/DB-generated fields are omitted by default.
class StemTaskResultInsertDto implements InsertDto<$StemTaskResult> {
  const StemTaskResultInsertDto({
    this.id,
    this.state,
    this.payload,
    this.error,
    this.attempt,
    this.meta,
    this.expiresAt,
  });
  final String? id;
  final String? state;
  final Object? payload;
  final Object? error;
  final int? attempt;
  final Map<String, Object?>? meta;
  final DateTime? expiresAt;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      if (state != null) 'state': state,
      if (payload != null) 'payload': payload,
      if (error != null) 'error': error,
      if (attempt != null) 'attempt': attempt,
      if (meta != null) 'meta': meta,
      if (expiresAt != null) 'expires_at': expiresAt,
    };
  }

  static const _StemTaskResultInsertDtoCopyWithSentinel _copyWithSentinel =
      _StemTaskResultInsertDtoCopyWithSentinel();
  StemTaskResultInsertDto copyWith({
    Object? id = _copyWithSentinel,
    Object? state = _copyWithSentinel,
    Object? payload = _copyWithSentinel,
    Object? error = _copyWithSentinel,
    Object? attempt = _copyWithSentinel,
    Object? meta = _copyWithSentinel,
    Object? expiresAt = _copyWithSentinel,
  }) {
    return StemTaskResultInsertDto(
      id: identical(id, _copyWithSentinel) ? this.id : id as String?,
      state: identical(state, _copyWithSentinel)
          ? this.state
          : state as String?,
      payload: identical(payload, _copyWithSentinel) ? this.payload : payload,
      error: identical(error, _copyWithSentinel) ? this.error : error,
      attempt: identical(attempt, _copyWithSentinel)
          ? this.attempt
          : attempt as int?,
      meta: identical(meta, _copyWithSentinel)
          ? this.meta
          : meta as Map<String, Object?>?,
      expiresAt: identical(expiresAt, _copyWithSentinel)
          ? this.expiresAt
          : expiresAt as DateTime?,
    );
  }
}

class _StemTaskResultInsertDtoCopyWithSentinel {
  const _StemTaskResultInsertDtoCopyWithSentinel();
}

/// Update DTO for [StemTaskResult].
///
/// All fields are optional; only provided entries are used in SET clauses.
class StemTaskResultUpdateDto implements UpdateDto<$StemTaskResult> {
  const StemTaskResultUpdateDto({
    this.id,
    this.state,
    this.payload,
    this.error,
    this.attempt,
    this.meta,
    this.expiresAt,
  });
  final String? id;
  final String? state;
  final Object? payload;
  final Object? error;
  final int? attempt;
  final Map<String, Object?>? meta;
  final DateTime? expiresAt;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      if (state != null) 'state': state,
      if (payload != null) 'payload': payload,
      if (error != null) 'error': error,
      if (attempt != null) 'attempt': attempt,
      if (meta != null) 'meta': meta,
      if (expiresAt != null) 'expires_at': expiresAt,
    };
  }

  static const _StemTaskResultUpdateDtoCopyWithSentinel _copyWithSentinel =
      _StemTaskResultUpdateDtoCopyWithSentinel();
  StemTaskResultUpdateDto copyWith({
    Object? id = _copyWithSentinel,
    Object? state = _copyWithSentinel,
    Object? payload = _copyWithSentinel,
    Object? error = _copyWithSentinel,
    Object? attempt = _copyWithSentinel,
    Object? meta = _copyWithSentinel,
    Object? expiresAt = _copyWithSentinel,
  }) {
    return StemTaskResultUpdateDto(
      id: identical(id, _copyWithSentinel) ? this.id : id as String?,
      state: identical(state, _copyWithSentinel)
          ? this.state
          : state as String?,
      payload: identical(payload, _copyWithSentinel) ? this.payload : payload,
      error: identical(error, _copyWithSentinel) ? this.error : error,
      attempt: identical(attempt, _copyWithSentinel)
          ? this.attempt
          : attempt as int?,
      meta: identical(meta, _copyWithSentinel)
          ? this.meta
          : meta as Map<String, Object?>?,
      expiresAt: identical(expiresAt, _copyWithSentinel)
          ? this.expiresAt
          : expiresAt as DateTime?,
    );
  }
}

class _StemTaskResultUpdateDtoCopyWithSentinel {
  const _StemTaskResultUpdateDtoCopyWithSentinel();
}

/// Partial projection for [StemTaskResult].
///
/// All fields are nullable; intended for subset SELECTs.
class StemTaskResultPartial implements PartialEntity<$StemTaskResult> {
  const StemTaskResultPartial({
    this.id,
    this.state,
    this.payload,
    this.error,
    this.attempt,
    this.meta,
    this.expiresAt,
  });

  /// Creates a partial from a database row map.
  ///
  /// The [row] keys should be column names (snake_case).
  /// Missing columns will result in null field values.
  factory StemTaskResultPartial.fromRow(Map<String, Object?> row) {
    return StemTaskResultPartial(
      id: row['id'] as String?,
      state: row['state'] as String?,
      payload: row['payload'],
      error: row['error'],
      attempt: row['attempt'] as int?,
      meta: row['meta'] as Map<String, Object?>?,
      expiresAt: row['expires_at'] as DateTime?,
    );
  }

  final String? id;
  final String? state;
  final Object? payload;
  final Object? error;
  final int? attempt;
  final Map<String, Object?>? meta;
  final DateTime? expiresAt;

  @override
  $StemTaskResult toEntity() {
    // Basic required-field check: non-nullable fields must be present.
    final idValue = id;
    if (idValue == null) {
      throw StateError('Missing required field: id');
    }
    final stateValue = state;
    if (stateValue == null) {
      throw StateError('Missing required field: state');
    }
    final attemptValue = attempt;
    if (attemptValue == null) {
      throw StateError('Missing required field: attempt');
    }
    final metaValue = meta;
    if (metaValue == null) {
      throw StateError('Missing required field: meta');
    }
    final expiresAtValue = expiresAt;
    if (expiresAtValue == null) {
      throw StateError('Missing required field: expiresAt');
    }
    return $StemTaskResult(
      id: idValue,
      state: stateValue,
      payload: payload,
      error: error,
      attempt: attemptValue,
      meta: metaValue,
      expiresAt: expiresAtValue,
    );
  }

  @override
  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      if (state != null) 'state': state,
      if (payload != null) 'payload': payload,
      if (error != null) 'error': error,
      if (attempt != null) 'attempt': attempt,
      if (meta != null) 'meta': meta,
      if (expiresAt != null) 'expires_at': expiresAt,
    };
  }

  static const _StemTaskResultPartialCopyWithSentinel _copyWithSentinel =
      _StemTaskResultPartialCopyWithSentinel();
  StemTaskResultPartial copyWith({
    Object? id = _copyWithSentinel,
    Object? state = _copyWithSentinel,
    Object? payload = _copyWithSentinel,
    Object? error = _copyWithSentinel,
    Object? attempt = _copyWithSentinel,
    Object? meta = _copyWithSentinel,
    Object? expiresAt = _copyWithSentinel,
  }) {
    return StemTaskResultPartial(
      id: identical(id, _copyWithSentinel) ? this.id : id as String?,
      state: identical(state, _copyWithSentinel)
          ? this.state
          : state as String?,
      payload: identical(payload, _copyWithSentinel) ? this.payload : payload,
      error: identical(error, _copyWithSentinel) ? this.error : error,
      attempt: identical(attempt, _copyWithSentinel)
          ? this.attempt
          : attempt as int?,
      meta: identical(meta, _copyWithSentinel)
          ? this.meta
          : meta as Map<String, Object?>?,
      expiresAt: identical(expiresAt, _copyWithSentinel)
          ? this.expiresAt
          : expiresAt as DateTime?,
    );
  }
}

class _StemTaskResultPartialCopyWithSentinel {
  const _StemTaskResultPartialCopyWithSentinel();
}

/// Generated tracked model class for [StemTaskResult].
///
/// This class extends the user-defined [StemTaskResult] model and adds
/// attribute tracking, change detection, and relationship management.
/// Instances of this class are returned by queries and repositories.
///
/// **Do not instantiate this class directly.** Use queries, repositories,
/// or model factories to create tracked model instances.
class $StemTaskResult extends StemTaskResult
    with ModelAttributes, TimestampsTZImpl
    implements OrmEntity {
  /// Internal constructor for [$StemTaskResult].
  $StemTaskResult({
    required String id,
    required String state,
    required int attempt,
    required Map<String, Object?> meta,
    required DateTime expiresAt,
    Object? payload,
    Object? error,
  }) : super.new(
         id: id,
         state: state,
         payload: payload,
         error: error,
         attempt: attempt,
         meta: meta,
         expiresAt: expiresAt,
       ) {
    _attachOrmRuntimeMetadata({
      'id': id,
      'state': state,
      'payload': payload,
      'error': error,
      'attempt': attempt,
      'meta': meta,
      'expires_at': expiresAt,
    });
  }

  /// Creates a tracked model instance from a user-defined model instance.
  factory $StemTaskResult.fromModel(StemTaskResult model) {
    return $StemTaskResult(
      id: model.id,
      state: model.state,
      payload: model.payload,
      error: model.error,
      attempt: model.attempt,
      meta: model.meta,
      expiresAt: model.expiresAt,
    );
  }

  $StemTaskResult copyWith({
    String? id,
    String? state,
    Object? payload,
    Object? error,
    int? attempt,
    Map<String, Object?>? meta,
    DateTime? expiresAt,
  }) {
    return $StemTaskResult(
      id: id ?? this.id,
      state: state ?? this.state,
      payload: payload ?? this.payload,
      error: error ?? this.error,
      attempt: attempt ?? this.attempt,
      meta: meta ?? this.meta,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  /// Tracked getter for [id].
  @override
  String get id => getAttribute<String>('id') ?? super.id;

  /// Tracked setter for [id].
  set id(String value) => setAttribute('id', value);

  /// Tracked getter for [state].
  @override
  String get state => getAttribute<String>('state') ?? super.state;

  /// Tracked setter for [state].
  set state(String value) => setAttribute('state', value);

  /// Tracked getter for [payload].
  @override
  Object? get payload => getAttribute<Object?>('payload') ?? super.payload;

  /// Tracked setter for [payload].
  set payload(Object? value) => setAttribute('payload', value);

  /// Tracked getter for [error].
  @override
  Object? get error => getAttribute<Object?>('error') ?? super.error;

  /// Tracked setter for [error].
  set error(Object? value) => setAttribute('error', value);

  /// Tracked getter for [attempt].
  @override
  int get attempt => getAttribute<int>('attempt') ?? super.attempt;

  /// Tracked setter for [attempt].
  set attempt(int value) => setAttribute('attempt', value);

  /// Tracked getter for [meta].
  @override
  Map<String, Object?> get meta =>
      getAttribute<Map<String, Object?>>('meta') ?? super.meta;

  /// Tracked setter for [meta].
  set meta(Map<String, Object?> value) => setAttribute('meta', value);

  /// Tracked getter for [expiresAt].
  @override
  DateTime get expiresAt =>
      getAttribute<DateTime>('expires_at') ?? super.expiresAt;

  /// Tracked setter for [expiresAt].
  set expiresAt(DateTime value) => setAttribute('expires_at', value);

  void _attachOrmRuntimeMetadata(Map<String, Object?> values) {
    replaceAttributes(values);
    attachModelDefinition(_$StemTaskResultDefinition);
  }
}

extension StemTaskResultOrmExtension on StemTaskResult {
  /// The Type of the generated ORM-managed model class.
  /// Use this when you need to specify the tracked model type explicitly,
  /// for example in generic type parameters.
  static Type get trackedType => $StemTaskResult;

  /// Converts this immutable model to a tracked ORM-managed model.
  /// The tracked model supports attribute tracking, change detection,
  /// and persistence operations like save() and touch().
  $StemTaskResult toTracked() {
    return $StemTaskResult.fromModel(this);
  }
}

void registerStemTaskResultEventHandlers(EventBus bus) {
  // No event handlers registered for StemTaskResult.
}
