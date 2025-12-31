// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'stem_group_result.dart';

// **************************************************************************
// OrmModelGenerator
// **************************************************************************

const FieldDefinition _$StemGroupResultGroupIdField = FieldDefinition(
  name: 'groupId',
  columnName: 'group_id',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: true,
  isNullable: false,
);

const FieldDefinition _$StemGroupResultTaskIdField = FieldDefinition(
  name: 'taskId',
  columnName: 'task_id',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: true,
  isNullable: false,
);

const FieldDefinition _$StemGroupResultStateField = FieldDefinition(
  name: 'state',
  columnName: 'state',
  dartType: 'String',
  resolvedType: 'String',
  isNullable: false,
);

const FieldDefinition _$StemGroupResultPayloadField = FieldDefinition(
  name: 'payload',
  columnName: 'payload',
  dartType: 'Object',
  resolvedType: 'Object?',
  isNullable: true,
  codecType: 'json',
);

const FieldDefinition _$StemGroupResultErrorField = FieldDefinition(
  name: 'error',
  columnName: 'error',
  dartType: 'Object',
  resolvedType: 'Object?',
  isNullable: true,
  codecType: 'json',
);

const FieldDefinition _$StemGroupResultAttemptField = FieldDefinition(
  name: 'attempt',
  columnName: 'attempt',
  dartType: 'int',
  resolvedType: 'int',
  isNullable: false,
);

const FieldDefinition _$StemGroupResultMetaField = FieldDefinition(
  name: 'meta',
  columnName: 'meta',
  dartType: 'Map<String, Object?>',
  resolvedType: 'Map<String, Object?>',
  isNullable: false,
  codecType: 'json',
);

const FieldDefinition _$StemGroupResultCreatedAtField = FieldDefinition(
  name: 'createdAt',
  columnName: 'created_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime?',
  isNullable: true,
);

const FieldDefinition _$StemGroupResultUpdatedAtField = FieldDefinition(
  name: 'updatedAt',
  columnName: 'updated_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime?',
  isNullable: true,
);

const RelationDefinition _$StemGroupResultGroupRelation = RelationDefinition(
  name: 'group',
  kind: RelationKind.belongsTo,
  targetModel: 'StemGroup',
  foreignKey: 'group_id',
);

Map<String, Object?> _encodeStemGroupResultUntracked(
  Object model,
  ValueCodecRegistry registry,
) {
  final m = model as StemGroupResult;
  return <String, Object?>{
    'group_id': registry.encodeField(_$StemGroupResultGroupIdField, m.groupId),
    'task_id': registry.encodeField(_$StemGroupResultTaskIdField, m.taskId),
    'state': registry.encodeField(_$StemGroupResultStateField, m.state),
    'payload': registry.encodeField(_$StemGroupResultPayloadField, m.payload),
    'error': registry.encodeField(_$StemGroupResultErrorField, m.error),
    'attempt': registry.encodeField(_$StemGroupResultAttemptField, m.attempt),
    'meta': registry.encodeField(_$StemGroupResultMetaField, m.meta),
  };
}

const ModelDefinition<$StemGroupResult> _$StemGroupResultDefinition =
    ModelDefinition(
      modelName: 'StemGroupResult',
      tableName: 'stem_group_results',
      fields: [
        _$StemGroupResultGroupIdField,
        _$StemGroupResultTaskIdField,
        _$StemGroupResultStateField,
        _$StemGroupResultPayloadField,
        _$StemGroupResultErrorField,
        _$StemGroupResultAttemptField,
        _$StemGroupResultMetaField,
        _$StemGroupResultCreatedAtField,
        _$StemGroupResultUpdatedAtField,
      ],
      relations: [_$StemGroupResultGroupRelation],
      softDeleteColumn: 'deleted_at',
      metadata: ModelAttributesMetadata(
        fieldOverrides: {
          'payload': FieldAttributeMetadata(cast: 'json'),
          'error': FieldAttributeMetadata(cast: 'json'),
          'meta': FieldAttributeMetadata(cast: 'json'),
        },
      ),
      untrackedToMap: _encodeStemGroupResultUntracked,
      codec: _$StemGroupResultCodec(),
    );

extension StemGroupResultOrmDefinition on StemGroupResult {
  static ModelDefinition<$StemGroupResult> get definition =>
      _$StemGroupResultDefinition;
}

class StemGroupResults {
  const StemGroupResults._();

  /// Starts building a query for [$StemGroupResult].
  ///
  /// {@macro ormed.query}
  static Query<$StemGroupResult> query([String? connection]) =>
      Model.query<$StemGroupResult>(connection: connection);

  static Future<$StemGroupResult?> find(Object id, {String? connection}) =>
      Model.find<$StemGroupResult>(id, connection: connection);

  static Future<$StemGroupResult> findOrFail(Object id, {String? connection}) =>
      Model.findOrFail<$StemGroupResult>(id, connection: connection);

  static Future<List<$StemGroupResult>> all({String? connection}) =>
      Model.all<$StemGroupResult>(connection: connection);

  static Future<int> count({String? connection}) =>
      Model.count<$StemGroupResult>(connection: connection);

  static Future<bool> anyExist({String? connection}) =>
      Model.anyExist<$StemGroupResult>(connection: connection);

  static Query<$StemGroupResult> where(
    String column,
    String operator,
    dynamic value, {
    String? connection,
  }) => Model.where<$StemGroupResult>(
    column,
    operator,
    value,
    connection: connection,
  );

  static Query<$StemGroupResult> whereIn(
    String column,
    List<dynamic> values, {
    String? connection,
  }) => Model.whereIn<$StemGroupResult>(column, values, connection: connection);

  static Query<$StemGroupResult> orderBy(
    String column, {
    String direction = 'asc',
    String? connection,
  }) => Model.orderBy<$StemGroupResult>(
    column,
    direction: direction,
    connection: connection,
  );

  static Query<$StemGroupResult> limit(int count, {String? connection}) =>
      Model.limit<$StemGroupResult>(count, connection: connection);

  /// Creates a [Repository] for [$StemGroupResult].
  ///
  /// {@macro ormed.repository}
  static Repository<$StemGroupResult> repo([String? connection]) =>
      Model.repository<$StemGroupResult>(connection: connection);
}

class StemGroupResultModelFactory {
  const StemGroupResultModelFactory._();

  static ModelDefinition<$StemGroupResult> get definition =>
      _$StemGroupResultDefinition;

  static ModelCodec<$StemGroupResult> get codec => definition.codec;

  static StemGroupResult fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => definition.fromMap(data, registry: registry);

  static Map<String, Object?> toMap(
    StemGroupResult model, {
    ValueCodecRegistry? registry,
  }) => definition.toMap(model.toTracked(), registry: registry);

  static void registerWith(ModelRegistry registry) =>
      registry.register(definition);

  static ModelFactoryConnection<StemGroupResult> withConnection(
    QueryContext context,
  ) => ModelFactoryConnection<StemGroupResult>(
    definition: definition,
    context: context,
  );

  static ModelFactoryBuilder<StemGroupResult> factory({
    GeneratorProvider? generatorProvider,
  }) => ModelFactoryBuilder<StemGroupResult>(
    definition: definition,
    generatorProvider: generatorProvider,
  );
}

class _$StemGroupResultCodec extends ModelCodec<$StemGroupResult> {
  const _$StemGroupResultCodec();
  @override
  Map<String, Object?> encode(
    $StemGroupResult model,
    ValueCodecRegistry registry,
  ) {
    return <String, Object?>{
      'group_id': registry.encodeField(
        _$StemGroupResultGroupIdField,
        model.groupId,
      ),
      'task_id': registry.encodeField(
        _$StemGroupResultTaskIdField,
        model.taskId,
      ),
      'state': registry.encodeField(_$StemGroupResultStateField, model.state),
      'payload': registry.encodeField(
        _$StemGroupResultPayloadField,
        model.payload,
      ),
      'error': registry.encodeField(_$StemGroupResultErrorField, model.error),
      'attempt': registry.encodeField(
        _$StemGroupResultAttemptField,
        model.attempt,
      ),
      'meta': registry.encodeField(_$StemGroupResultMetaField, model.meta),
      if (model.hasAttribute('created_at'))
        'created_at': registry.encodeField(
          _$StemGroupResultCreatedAtField,
          model.getAttribute<DateTime?>('created_at'),
        ),
      if (model.hasAttribute('updated_at'))
        'updated_at': registry.encodeField(
          _$StemGroupResultUpdatedAtField,
          model.getAttribute<DateTime?>('updated_at'),
        ),
    };
  }

  @override
  $StemGroupResult decode(
    Map<String, Object?> data,
    ValueCodecRegistry registry,
  ) {
    final stemGroupResultGroupIdValue =
        registry.decodeField<String>(
          _$StemGroupResultGroupIdField,
          data['group_id'],
        ) ??
        (throw StateError('Field groupId on StemGroupResult cannot be null.'));
    final stemGroupResultTaskIdValue =
        registry.decodeField<String>(
          _$StemGroupResultTaskIdField,
          data['task_id'],
        ) ??
        (throw StateError('Field taskId on StemGroupResult cannot be null.'));
    final stemGroupResultStateValue =
        registry.decodeField<String>(
          _$StemGroupResultStateField,
          data['state'],
        ) ??
        (throw StateError('Field state on StemGroupResult cannot be null.'));
    final stemGroupResultPayloadValue = registry.decodeField<Object?>(
      _$StemGroupResultPayloadField,
      data['payload'],
    );
    final stemGroupResultErrorValue = registry.decodeField<Object?>(
      _$StemGroupResultErrorField,
      data['error'],
    );
    final stemGroupResultAttemptValue =
        registry.decodeField<int>(
          _$StemGroupResultAttemptField,
          data['attempt'],
        ) ??
        (throw StateError('Field attempt on StemGroupResult cannot be null.'));
    final stemGroupResultMetaValue =
        registry.decodeField<Map<String, Object?>>(
          _$StemGroupResultMetaField,
          data['meta'],
        ) ??
        (throw StateError('Field meta on StemGroupResult cannot be null.'));
    final stemGroupResultCreatedAtValue = registry.decodeField<DateTime?>(
      _$StemGroupResultCreatedAtField,
      data['created_at'],
    );
    final stemGroupResultUpdatedAtValue = registry.decodeField<DateTime?>(
      _$StemGroupResultUpdatedAtField,
      data['updated_at'],
    );
    final model = $StemGroupResult(
      groupId: stemGroupResultGroupIdValue,
      taskId: stemGroupResultTaskIdValue,
      state: stemGroupResultStateValue,
      payload: stemGroupResultPayloadValue,
      error: stemGroupResultErrorValue,
      attempt: stemGroupResultAttemptValue,
      meta: stemGroupResultMetaValue,
    );
    model._attachOrmRuntimeMetadata({
      'group_id': stemGroupResultGroupIdValue,
      'task_id': stemGroupResultTaskIdValue,
      'state': stemGroupResultStateValue,
      'payload': stemGroupResultPayloadValue,
      'error': stemGroupResultErrorValue,
      'attempt': stemGroupResultAttemptValue,
      'meta': stemGroupResultMetaValue,
      if (data.containsKey('created_at'))
        'created_at': stemGroupResultCreatedAtValue,
      if (data.containsKey('updated_at'))
        'updated_at': stemGroupResultUpdatedAtValue,
    });
    return model;
  }
}

/// Insert DTO for [StemGroupResult].
///
/// Auto-increment/DB-generated fields are omitted by default.
class StemGroupResultInsertDto implements InsertDto<$StemGroupResult> {
  const StemGroupResultInsertDto({
    this.groupId,
    this.taskId,
    this.state,
    this.payload,
    this.error,
    this.attempt,
    this.meta,
  });
  final String? groupId;
  final String? taskId;
  final String? state;
  final Object? payload;
  final Object? error;
  final int? attempt;
  final Map<String, Object?>? meta;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (groupId != null) 'group_id': groupId,
      if (taskId != null) 'task_id': taskId,
      if (state != null) 'state': state,
      if (payload != null) 'payload': payload,
      if (error != null) 'error': error,
      if (attempt != null) 'attempt': attempt,
      if (meta != null) 'meta': meta,
    };
  }

  static const _StemGroupResultInsertDtoCopyWithSentinel _copyWithSentinel =
      _StemGroupResultInsertDtoCopyWithSentinel();
  StemGroupResultInsertDto copyWith({
    Object? groupId = _copyWithSentinel,
    Object? taskId = _copyWithSentinel,
    Object? state = _copyWithSentinel,
    Object? payload = _copyWithSentinel,
    Object? error = _copyWithSentinel,
    Object? attempt = _copyWithSentinel,
    Object? meta = _copyWithSentinel,
  }) {
    return StemGroupResultInsertDto(
      groupId: identical(groupId, _copyWithSentinel)
          ? this.groupId
          : groupId as String?,
      taskId: identical(taskId, _copyWithSentinel)
          ? this.taskId
          : taskId as String?,
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
    );
  }
}

class _StemGroupResultInsertDtoCopyWithSentinel {
  const _StemGroupResultInsertDtoCopyWithSentinel();
}

/// Update DTO for [StemGroupResult].
///
/// All fields are optional; only provided entries are used in SET clauses.
class StemGroupResultUpdateDto implements UpdateDto<$StemGroupResult> {
  const StemGroupResultUpdateDto({
    this.groupId,
    this.taskId,
    this.state,
    this.payload,
    this.error,
    this.attempt,
    this.meta,
  });
  final String? groupId;
  final String? taskId;
  final String? state;
  final Object? payload;
  final Object? error;
  final int? attempt;
  final Map<String, Object?>? meta;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (groupId != null) 'group_id': groupId,
      if (taskId != null) 'task_id': taskId,
      if (state != null) 'state': state,
      if (payload != null) 'payload': payload,
      if (error != null) 'error': error,
      if (attempt != null) 'attempt': attempt,
      if (meta != null) 'meta': meta,
    };
  }

  static const _StemGroupResultUpdateDtoCopyWithSentinel _copyWithSentinel =
      _StemGroupResultUpdateDtoCopyWithSentinel();
  StemGroupResultUpdateDto copyWith({
    Object? groupId = _copyWithSentinel,
    Object? taskId = _copyWithSentinel,
    Object? state = _copyWithSentinel,
    Object? payload = _copyWithSentinel,
    Object? error = _copyWithSentinel,
    Object? attempt = _copyWithSentinel,
    Object? meta = _copyWithSentinel,
  }) {
    return StemGroupResultUpdateDto(
      groupId: identical(groupId, _copyWithSentinel)
          ? this.groupId
          : groupId as String?,
      taskId: identical(taskId, _copyWithSentinel)
          ? this.taskId
          : taskId as String?,
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
    );
  }
}

class _StemGroupResultUpdateDtoCopyWithSentinel {
  const _StemGroupResultUpdateDtoCopyWithSentinel();
}

/// Partial projection for [StemGroupResult].
///
/// All fields are nullable; intended for subset SELECTs.
class StemGroupResultPartial implements PartialEntity<$StemGroupResult> {
  const StemGroupResultPartial({
    this.groupId,
    this.taskId,
    this.state,
    this.payload,
    this.error,
    this.attempt,
    this.meta,
  });

  /// Creates a partial from a database row map.
  ///
  /// The [row] keys should be column names (snake_case).
  /// Missing columns will result in null field values.
  factory StemGroupResultPartial.fromRow(Map<String, Object?> row) {
    return StemGroupResultPartial(
      groupId: row['group_id'] as String?,
      taskId: row['task_id'] as String?,
      state: row['state'] as String?,
      payload: row['payload'],
      error: row['error'],
      attempt: row['attempt'] as int?,
      meta: row['meta'] as Map<String, Object?>?,
    );
  }

  final String? groupId;
  final String? taskId;
  final String? state;
  final Object? payload;
  final Object? error;
  final int? attempt;
  final Map<String, Object?>? meta;

  @override
  $StemGroupResult toEntity() {
    // Basic required-field check: non-nullable fields must be present.
    final groupIdValue = groupId;
    if (groupIdValue == null) {
      throw StateError('Missing required field: groupId');
    }
    final taskIdValue = taskId;
    if (taskIdValue == null) {
      throw StateError('Missing required field: taskId');
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
    return $StemGroupResult(
      groupId: groupIdValue,
      taskId: taskIdValue,
      state: stateValue,
      payload: payload,
      error: error,
      attempt: attemptValue,
      meta: metaValue,
    );
  }

  @override
  Map<String, Object?> toMap() {
    return {
      if (groupId != null) 'group_id': groupId,
      if (taskId != null) 'task_id': taskId,
      if (state != null) 'state': state,
      if (payload != null) 'payload': payload,
      if (error != null) 'error': error,
      if (attempt != null) 'attempt': attempt,
      if (meta != null) 'meta': meta,
    };
  }

  static const _StemGroupResultPartialCopyWithSentinel _copyWithSentinel =
      _StemGroupResultPartialCopyWithSentinel();
  StemGroupResultPartial copyWith({
    Object? groupId = _copyWithSentinel,
    Object? taskId = _copyWithSentinel,
    Object? state = _copyWithSentinel,
    Object? payload = _copyWithSentinel,
    Object? error = _copyWithSentinel,
    Object? attempt = _copyWithSentinel,
    Object? meta = _copyWithSentinel,
  }) {
    return StemGroupResultPartial(
      groupId: identical(groupId, _copyWithSentinel)
          ? this.groupId
          : groupId as String?,
      taskId: identical(taskId, _copyWithSentinel)
          ? this.taskId
          : taskId as String?,
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
    );
  }
}

class _StemGroupResultPartialCopyWithSentinel {
  const _StemGroupResultPartialCopyWithSentinel();
}

/// Generated tracked model class for [StemGroupResult].
///
/// This class extends the user-defined [StemGroupResult] model and adds
/// attribute tracking, change detection, and relationship management.
/// Instances of this class are returned by queries and repositories.
///
/// **Do not instantiate this class directly.** Use queries, repositories,
/// or model factories to create tracked model instances.
class $StemGroupResult extends StemGroupResult
    with ModelAttributes, TimestampsTZImpl
    implements OrmEntity {
  /// Internal constructor for [$StemGroupResult].
  $StemGroupResult({
    required String groupId,
    required String taskId,
    required String state,
    required int attempt,
    required Map<String, Object?> meta,
    Object? payload,
    Object? error,
  }) : super.new(
         groupId: groupId,
         taskId: taskId,
         state: state,
         payload: payload,
         error: error,
         attempt: attempt,
         meta: meta,
       ) {
    _attachOrmRuntimeMetadata({
      'group_id': groupId,
      'task_id': taskId,
      'state': state,
      'payload': payload,
      'error': error,
      'attempt': attempt,
      'meta': meta,
    });
  }

  /// Creates a tracked model instance from a user-defined model instance.
  factory $StemGroupResult.fromModel(StemGroupResult model) {
    return $StemGroupResult(
      groupId: model.groupId,
      taskId: model.taskId,
      state: model.state,
      payload: model.payload,
      error: model.error,
      attempt: model.attempt,
      meta: model.meta,
    );
  }

  $StemGroupResult copyWith({
    String? groupId,
    String? taskId,
    String? state,
    Object? payload,
    Object? error,
    int? attempt,
    Map<String, Object?>? meta,
  }) {
    return $StemGroupResult(
      groupId: groupId ?? this.groupId,
      taskId: taskId ?? this.taskId,
      state: state ?? this.state,
      payload: payload ?? this.payload,
      error: error ?? this.error,
      attempt: attempt ?? this.attempt,
      meta: meta ?? this.meta,
    );
  }

  /// Tracked getter for [groupId].
  @override
  String get groupId => getAttribute<String>('group_id') ?? super.groupId;

  /// Tracked setter for [groupId].
  set groupId(String value) => setAttribute('group_id', value);

  /// Tracked getter for [taskId].
  @override
  String get taskId => getAttribute<String>('task_id') ?? super.taskId;

  /// Tracked setter for [taskId].
  set taskId(String value) => setAttribute('task_id', value);

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

  void _attachOrmRuntimeMetadata(Map<String, Object?> values) {
    replaceAttributes(values);
    attachModelDefinition(_$StemGroupResultDefinition);
  }

  @override
  StemGroup? get group {
    if (relationLoaded('group')) {
      return getRelation<StemGroup>('group');
    }
    return super.group;
  }
}

extension StemGroupResultRelationQueries on StemGroupResult {
  Query<StemGroup> groupQuery() {
    return Model.query<StemGroup>().where('null', groupId);
  }
}

extension StemGroupResultOrmExtension on StemGroupResult {
  /// The Type of the generated ORM-managed model class.
  /// Use this when you need to specify the tracked model type explicitly,
  /// for example in generic type parameters.
  static Type get trackedType => $StemGroupResult;

  /// Converts this immutable model to a tracked ORM-managed model.
  /// The tracked model supports attribute tracking, change detection,
  /// and persistence operations like save() and touch().
  $StemGroupResult toTracked() {
    return $StemGroupResult.fromModel(this);
  }
}

void registerStemGroupResultEventHandlers(EventBus bus) {
  // No event handlers registered for StemGroupResult.
}
