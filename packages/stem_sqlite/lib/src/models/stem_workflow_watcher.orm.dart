// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'stem_workflow_watcher.dart';

// **************************************************************************
// OrmModelGenerator
// **************************************************************************

const FieldDefinition _$StemWorkflowWatcherRunIdField = FieldDefinition(
  name: 'runId',
  columnName: 'run_id',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: true,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemWorkflowWatcherStepNameField = FieldDefinition(
  name: 'stepName',
  columnName: 'step_name',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemWorkflowWatcherTopicField = FieldDefinition(
  name: 'topic',
  columnName: 'topic',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemWorkflowWatcherNamespaceField = FieldDefinition(
  name: 'namespace',
  columnName: 'namespace',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemWorkflowWatcherDataField = FieldDefinition(
  name: 'data',
  columnName: 'data',
  dartType: 'String',
  resolvedType: 'String?',
  isPrimaryKey: false,
  isNullable: true,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemWorkflowWatcherCreatedAtField = FieldDefinition(
  name: 'createdAt',
  columnName: 'created_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemWorkflowWatcherDeadlineField = FieldDefinition(
  name: 'deadline',
  columnName: 'deadline',
  dartType: 'DateTime',
  resolvedType: 'DateTime?',
  isPrimaryKey: false,
  isNullable: true,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

Map<String, Object?> _encodeStemWorkflowWatcherUntracked(
  Object model,
  ValueCodecRegistry registry,
) {
  final m = model as StemWorkflowWatcher;
  return <String, Object?>{
    'run_id': registry.encodeField(_$StemWorkflowWatcherRunIdField, m.runId),
    'step_name': registry.encodeField(
      _$StemWorkflowWatcherStepNameField,
      m.stepName,
    ),
    'topic': registry.encodeField(_$StemWorkflowWatcherTopicField, m.topic),
    'namespace': registry.encodeField(
      _$StemWorkflowWatcherNamespaceField,
      m.namespace,
    ),
    'data': registry.encodeField(_$StemWorkflowWatcherDataField, m.data),
    'created_at': registry.encodeField(
      _$StemWorkflowWatcherCreatedAtField,
      m.createdAt,
    ),
    'deadline': registry.encodeField(
      _$StemWorkflowWatcherDeadlineField,
      m.deadline,
    ),
  };
}

final ModelDefinition<$StemWorkflowWatcher> _$StemWorkflowWatcherDefinition =
    ModelDefinition(
      modelName: 'StemWorkflowWatcher',
      tableName: 'wf_watchers',
      fields: const [
        _$StemWorkflowWatcherRunIdField,
        _$StemWorkflowWatcherStepNameField,
        _$StemWorkflowWatcherTopicField,
        _$StemWorkflowWatcherNamespaceField,
        _$StemWorkflowWatcherDataField,
        _$StemWorkflowWatcherCreatedAtField,
        _$StemWorkflowWatcherDeadlineField,
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
      untrackedToMap: _encodeStemWorkflowWatcherUntracked,
      codec: _$StemWorkflowWatcherCodec(),
    );

extension StemWorkflowWatcherOrmDefinition on StemWorkflowWatcher {
  static ModelDefinition<$StemWorkflowWatcher> get definition =>
      _$StemWorkflowWatcherDefinition;
}

class StemWorkflowWatchers {
  const StemWorkflowWatchers._();

  /// Starts building a query for [$StemWorkflowWatcher].
  ///
  /// {@macro ormed.query}
  static Query<$StemWorkflowWatcher> query([String? connection]) =>
      Model.query<$StemWorkflowWatcher>(connection: connection);

  static Future<$StemWorkflowWatcher?> find(Object id, {String? connection}) =>
      Model.find<$StemWorkflowWatcher>(id, connection: connection);

  static Future<$StemWorkflowWatcher> findOrFail(
    Object id, {
    String? connection,
  }) => Model.findOrFail<$StemWorkflowWatcher>(id, connection: connection);

  static Future<List<$StemWorkflowWatcher>> all({String? connection}) =>
      Model.all<$StemWorkflowWatcher>(connection: connection);

  static Future<int> count({String? connection}) =>
      Model.count<$StemWorkflowWatcher>(connection: connection);

  static Future<bool> anyExist({String? connection}) =>
      Model.anyExist<$StemWorkflowWatcher>(connection: connection);

  static Query<$StemWorkflowWatcher> where(
    String column,
    String operator,
    dynamic value, {
    String? connection,
  }) => Model.where<$StemWorkflowWatcher>(
    column,
    operator,
    value,
    connection: connection,
  );

  static Query<$StemWorkflowWatcher> whereIn(
    String column,
    List<dynamic> values, {
    String? connection,
  }) => Model.whereIn<$StemWorkflowWatcher>(
    column,
    values,
    connection: connection,
  );

  static Query<$StemWorkflowWatcher> orderBy(
    String column, {
    String direction = "asc",
    String? connection,
  }) => Model.orderBy<$StemWorkflowWatcher>(
    column,
    direction: direction,
    connection: connection,
  );

  static Query<$StemWorkflowWatcher> limit(int count, {String? connection}) =>
      Model.limit<$StemWorkflowWatcher>(count, connection: connection);

  /// Creates a [Repository] for [$StemWorkflowWatcher].
  ///
  /// {@macro ormed.repository}
  static Repository<$StemWorkflowWatcher> repo([String? connection]) =>
      Model.repository<$StemWorkflowWatcher>(connection: connection);

  /// Builds a tracked model from a column/value map.
  static $StemWorkflowWatcher fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$StemWorkflowWatcherDefinition.fromMap(data, registry: registry);

  /// Converts a tracked model to a column/value map.
  static Map<String, Object?> toMap(
    $StemWorkflowWatcher model, {
    ValueCodecRegistry? registry,
  }) => _$StemWorkflowWatcherDefinition.toMap(model, registry: registry);
}

class StemWorkflowWatcherModelFactory {
  const StemWorkflowWatcherModelFactory._();

  static ModelDefinition<$StemWorkflowWatcher> get definition =>
      _$StemWorkflowWatcherDefinition;

  static ModelCodec<$StemWorkflowWatcher> get codec => definition.codec;

  static StemWorkflowWatcher fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => definition.fromMap(data, registry: registry);

  static Map<String, Object?> toMap(
    StemWorkflowWatcher model, {
    ValueCodecRegistry? registry,
  }) => definition.toMap(model.toTracked(), registry: registry);

  static void registerWith(ModelRegistry registry) =>
      registry.register(definition);

  static ModelFactoryConnection<StemWorkflowWatcher> withConnection(
    QueryContext context,
  ) => ModelFactoryConnection<StemWorkflowWatcher>(
    definition: definition,
    context: context,
  );

  static ModelFactoryBuilder<StemWorkflowWatcher> factory({
    GeneratorProvider? generatorProvider,
  }) => ModelFactoryRegistry.factoryFor<StemWorkflowWatcher>(
    generatorProvider: generatorProvider,
  );
}

class _$StemWorkflowWatcherCodec extends ModelCodec<$StemWorkflowWatcher> {
  const _$StemWorkflowWatcherCodec();
  @override
  Map<String, Object?> encode(
    $StemWorkflowWatcher model,
    ValueCodecRegistry registry,
  ) {
    return <String, Object?>{
      'run_id': registry.encodeField(
        _$StemWorkflowWatcherRunIdField,
        model.runId,
      ),
      'step_name': registry.encodeField(
        _$StemWorkflowWatcherStepNameField,
        model.stepName,
      ),
      'topic': registry.encodeField(
        _$StemWorkflowWatcherTopicField,
        model.topic,
      ),
      'namespace': registry.encodeField(
        _$StemWorkflowWatcherNamespaceField,
        model.namespace,
      ),
      'data': registry.encodeField(_$StemWorkflowWatcherDataField, model.data),
      'created_at': registry.encodeField(
        _$StemWorkflowWatcherCreatedAtField,
        model.createdAt,
      ),
      'deadline': registry.encodeField(
        _$StemWorkflowWatcherDeadlineField,
        model.deadline,
      ),
    };
  }

  @override
  $StemWorkflowWatcher decode(
    Map<String, Object?> data,
    ValueCodecRegistry registry,
  ) {
    final String stemWorkflowWatcherRunIdValue =
        registry.decodeField<String>(
          _$StemWorkflowWatcherRunIdField,
          data['run_id'],
        ) ??
        (throw StateError(
          'Field runId on StemWorkflowWatcher cannot be null.',
        ));
    final String stemWorkflowWatcherStepNameValue =
        registry.decodeField<String>(
          _$StemWorkflowWatcherStepNameField,
          data['step_name'],
        ) ??
        (throw StateError(
          'Field stepName on StemWorkflowWatcher cannot be null.',
        ));
    final String stemWorkflowWatcherTopicValue =
        registry.decodeField<String>(
          _$StemWorkflowWatcherTopicField,
          data['topic'],
        ) ??
        (throw StateError(
          'Field topic on StemWorkflowWatcher cannot be null.',
        ));
    final String stemWorkflowWatcherNamespaceValue =
        registry.decodeField<String>(
          _$StemWorkflowWatcherNamespaceField,
          data['namespace'],
        ) ??
        (throw StateError(
          'Field namespace on StemWorkflowWatcher cannot be null.',
        ));
    final String? stemWorkflowWatcherDataValue = registry.decodeField<String?>(
      _$StemWorkflowWatcherDataField,
      data['data'],
    );
    final DateTime stemWorkflowWatcherCreatedAtValue =
        registry.decodeField<DateTime>(
          _$StemWorkflowWatcherCreatedAtField,
          data['created_at'],
        ) ??
        (throw StateError(
          'Field createdAt on StemWorkflowWatcher cannot be null.',
        ));
    final DateTime? stemWorkflowWatcherDeadlineValue = registry
        .decodeField<DateTime?>(
          _$StemWorkflowWatcherDeadlineField,
          data['deadline'],
        );
    final model = $StemWorkflowWatcher(
      runId: stemWorkflowWatcherRunIdValue,
      stepName: stemWorkflowWatcherStepNameValue,
      topic: stemWorkflowWatcherTopicValue,
      namespace: stemWorkflowWatcherNamespaceValue,
      createdAt: stemWorkflowWatcherCreatedAtValue,
      data: stemWorkflowWatcherDataValue,
      deadline: stemWorkflowWatcherDeadlineValue,
    );
    model._attachOrmRuntimeMetadata({
      'run_id': stemWorkflowWatcherRunIdValue,
      'step_name': stemWorkflowWatcherStepNameValue,
      'topic': stemWorkflowWatcherTopicValue,
      'namespace': stemWorkflowWatcherNamespaceValue,
      'data': stemWorkflowWatcherDataValue,
      'created_at': stemWorkflowWatcherCreatedAtValue,
      'deadline': stemWorkflowWatcherDeadlineValue,
    });
    return model;
  }
}

/// Insert DTO for [StemWorkflowWatcher].
///
/// Auto-increment/DB-generated fields are omitted by default.
class StemWorkflowWatcherInsertDto implements InsertDto<$StemWorkflowWatcher> {
  const StemWorkflowWatcherInsertDto({
    this.runId,
    this.stepName,
    this.topic,
    this.namespace,
    this.data,
    this.createdAt,
    this.deadline,
  });
  final String? runId;
  final String? stepName;
  final String? topic;
  final String? namespace;
  final String? data;
  final DateTime? createdAt;
  final DateTime? deadline;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (runId != null) 'run_id': runId,
      if (stepName != null) 'step_name': stepName,
      if (topic != null) 'topic': topic,
      if (namespace != null) 'namespace': namespace,
      if (data != null) 'data': data,
      if (createdAt != null) 'created_at': createdAt,
      if (deadline != null) 'deadline': deadline,
    };
  }

  static const _StemWorkflowWatcherInsertDtoCopyWithSentinel _copyWithSentinel =
      _StemWorkflowWatcherInsertDtoCopyWithSentinel();
  StemWorkflowWatcherInsertDto copyWith({
    Object? runId = _copyWithSentinel,
    Object? stepName = _copyWithSentinel,
    Object? topic = _copyWithSentinel,
    Object? namespace = _copyWithSentinel,
    Object? data = _copyWithSentinel,
    Object? createdAt = _copyWithSentinel,
    Object? deadline = _copyWithSentinel,
  }) {
    return StemWorkflowWatcherInsertDto(
      runId: identical(runId, _copyWithSentinel)
          ? this.runId
          : runId as String?,
      stepName: identical(stepName, _copyWithSentinel)
          ? this.stepName
          : stepName as String?,
      topic: identical(topic, _copyWithSentinel)
          ? this.topic
          : topic as String?,
      namespace: identical(namespace, _copyWithSentinel)
          ? this.namespace
          : namespace as String?,
      data: identical(data, _copyWithSentinel) ? this.data : data as String?,
      createdAt: identical(createdAt, _copyWithSentinel)
          ? this.createdAt
          : createdAt as DateTime?,
      deadline: identical(deadline, _copyWithSentinel)
          ? this.deadline
          : deadline as DateTime?,
    );
  }
}

class _StemWorkflowWatcherInsertDtoCopyWithSentinel {
  const _StemWorkflowWatcherInsertDtoCopyWithSentinel();
}

/// Update DTO for [StemWorkflowWatcher].
///
/// All fields are optional; only provided entries are used in SET clauses.
class StemWorkflowWatcherUpdateDto implements UpdateDto<$StemWorkflowWatcher> {
  const StemWorkflowWatcherUpdateDto({
    this.runId,
    this.stepName,
    this.topic,
    this.namespace,
    this.data,
    this.createdAt,
    this.deadline,
  });
  final String? runId;
  final String? stepName;
  final String? topic;
  final String? namespace;
  final String? data;
  final DateTime? createdAt;
  final DateTime? deadline;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (runId != null) 'run_id': runId,
      if (stepName != null) 'step_name': stepName,
      if (topic != null) 'topic': topic,
      if (namespace != null) 'namespace': namespace,
      if (data != null) 'data': data,
      if (createdAt != null) 'created_at': createdAt,
      if (deadline != null) 'deadline': deadline,
    };
  }

  static const _StemWorkflowWatcherUpdateDtoCopyWithSentinel _copyWithSentinel =
      _StemWorkflowWatcherUpdateDtoCopyWithSentinel();
  StemWorkflowWatcherUpdateDto copyWith({
    Object? runId = _copyWithSentinel,
    Object? stepName = _copyWithSentinel,
    Object? topic = _copyWithSentinel,
    Object? namespace = _copyWithSentinel,
    Object? data = _copyWithSentinel,
    Object? createdAt = _copyWithSentinel,
    Object? deadline = _copyWithSentinel,
  }) {
    return StemWorkflowWatcherUpdateDto(
      runId: identical(runId, _copyWithSentinel)
          ? this.runId
          : runId as String?,
      stepName: identical(stepName, _copyWithSentinel)
          ? this.stepName
          : stepName as String?,
      topic: identical(topic, _copyWithSentinel)
          ? this.topic
          : topic as String?,
      namespace: identical(namespace, _copyWithSentinel)
          ? this.namespace
          : namespace as String?,
      data: identical(data, _copyWithSentinel) ? this.data : data as String?,
      createdAt: identical(createdAt, _copyWithSentinel)
          ? this.createdAt
          : createdAt as DateTime?,
      deadline: identical(deadline, _copyWithSentinel)
          ? this.deadline
          : deadline as DateTime?,
    );
  }
}

class _StemWorkflowWatcherUpdateDtoCopyWithSentinel {
  const _StemWorkflowWatcherUpdateDtoCopyWithSentinel();
}

/// Partial projection for [StemWorkflowWatcher].
///
/// All fields are nullable; intended for subset SELECTs.
class StemWorkflowWatcherPartial
    implements PartialEntity<$StemWorkflowWatcher> {
  const StemWorkflowWatcherPartial({
    this.runId,
    this.stepName,
    this.topic,
    this.namespace,
    this.data,
    this.createdAt,
    this.deadline,
  });

  /// Creates a partial from a database row map.
  ///
  /// The [row] keys should be column names (snake_case).
  /// Missing columns will result in null field values.
  factory StemWorkflowWatcherPartial.fromRow(Map<String, Object?> row) {
    return StemWorkflowWatcherPartial(
      runId: row['run_id'] as String?,
      stepName: row['step_name'] as String?,
      topic: row['topic'] as String?,
      namespace: row['namespace'] as String?,
      data: row['data'] as String?,
      createdAt: row['created_at'] as DateTime?,
      deadline: row['deadline'] as DateTime?,
    );
  }

  final String? runId;
  final String? stepName;
  final String? topic;
  final String? namespace;
  final String? data;
  final DateTime? createdAt;
  final DateTime? deadline;

  @override
  $StemWorkflowWatcher toEntity() {
    // Basic required-field check: non-nullable fields must be present.
    final String? runIdValue = runId;
    if (runIdValue == null) {
      throw StateError('Missing required field: runId');
    }
    final String? stepNameValue = stepName;
    if (stepNameValue == null) {
      throw StateError('Missing required field: stepName');
    }
    final String? topicValue = topic;
    if (topicValue == null) {
      throw StateError('Missing required field: topic');
    }
    final String? namespaceValue = namespace;
    if (namespaceValue == null) {
      throw StateError('Missing required field: namespace');
    }
    final DateTime? createdAtValue = createdAt;
    if (createdAtValue == null) {
      throw StateError('Missing required field: createdAt');
    }
    return $StemWorkflowWatcher(
      runId: runIdValue,
      stepName: stepNameValue,
      topic: topicValue,
      namespace: namespaceValue,
      data: data,
      createdAt: createdAtValue,
      deadline: deadline,
    );
  }

  @override
  Map<String, Object?> toMap() {
    return {
      if (runId != null) 'run_id': runId,
      if (stepName != null) 'step_name': stepName,
      if (topic != null) 'topic': topic,
      if (namespace != null) 'namespace': namespace,
      if (data != null) 'data': data,
      if (createdAt != null) 'created_at': createdAt,
      if (deadline != null) 'deadline': deadline,
    };
  }

  static const _StemWorkflowWatcherPartialCopyWithSentinel _copyWithSentinel =
      _StemWorkflowWatcherPartialCopyWithSentinel();
  StemWorkflowWatcherPartial copyWith({
    Object? runId = _copyWithSentinel,
    Object? stepName = _copyWithSentinel,
    Object? topic = _copyWithSentinel,
    Object? namespace = _copyWithSentinel,
    Object? data = _copyWithSentinel,
    Object? createdAt = _copyWithSentinel,
    Object? deadline = _copyWithSentinel,
  }) {
    return StemWorkflowWatcherPartial(
      runId: identical(runId, _copyWithSentinel)
          ? this.runId
          : runId as String?,
      stepName: identical(stepName, _copyWithSentinel)
          ? this.stepName
          : stepName as String?,
      topic: identical(topic, _copyWithSentinel)
          ? this.topic
          : topic as String?,
      namespace: identical(namespace, _copyWithSentinel)
          ? this.namespace
          : namespace as String?,
      data: identical(data, _copyWithSentinel) ? this.data : data as String?,
      createdAt: identical(createdAt, _copyWithSentinel)
          ? this.createdAt
          : createdAt as DateTime?,
      deadline: identical(deadline, _copyWithSentinel)
          ? this.deadline
          : deadline as DateTime?,
    );
  }
}

class _StemWorkflowWatcherPartialCopyWithSentinel {
  const _StemWorkflowWatcherPartialCopyWithSentinel();
}

/// Generated tracked model class for [StemWorkflowWatcher].
///
/// This class extends the user-defined [StemWorkflowWatcher] model and adds
/// attribute tracking, change detection, and relationship management.
/// Instances of this class are returned by queries and repositories.
///
/// **Do not instantiate this class directly.** Use queries, repositories,
/// or model factories to create tracked model instances.
class $StemWorkflowWatcher extends StemWorkflowWatcher
    with ModelAttributes
    implements OrmEntity {
  /// Internal constructor for [$StemWorkflowWatcher].
  $StemWorkflowWatcher({
    required String runId,
    required String stepName,
    required String topic,
    required String namespace,
    required DateTime createdAt,
    String? data,
    DateTime? deadline,
  }) : super(
         runId: runId,
         stepName: stepName,
         topic: topic,
         namespace: namespace,
         createdAt: createdAt,
         data: data,
         deadline: deadline,
       ) {
    _attachOrmRuntimeMetadata({
      'run_id': runId,
      'step_name': stepName,
      'topic': topic,
      'namespace': namespace,
      'data': data,
      'created_at': createdAt,
      'deadline': deadline,
    });
  }

  /// Creates a tracked model instance from a user-defined model instance.
  factory $StemWorkflowWatcher.fromModel(StemWorkflowWatcher model) {
    return $StemWorkflowWatcher(
      runId: model.runId,
      stepName: model.stepName,
      topic: model.topic,
      namespace: model.namespace,
      data: model.data,
      createdAt: model.createdAt,
      deadline: model.deadline,
    );
  }

  $StemWorkflowWatcher copyWith({
    String? runId,
    String? stepName,
    String? topic,
    String? namespace,
    String? data,
    DateTime? createdAt,
    DateTime? deadline,
  }) {
    return $StemWorkflowWatcher(
      runId: runId ?? this.runId,
      stepName: stepName ?? this.stepName,
      topic: topic ?? this.topic,
      namespace: namespace ?? this.namespace,
      data: data ?? this.data,
      createdAt: createdAt ?? this.createdAt,
      deadline: deadline ?? this.deadline,
    );
  }

  /// Builds a tracked model from a column/value map.
  static $StemWorkflowWatcher fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$StemWorkflowWatcherDefinition.fromMap(data, registry: registry);

  /// Converts this tracked model to a column/value map.
  Map<String, Object?> toMap({ValueCodecRegistry? registry}) =>
      _$StemWorkflowWatcherDefinition.toMap(this, registry: registry);

  /// Tracked getter for [runId].
  @override
  String get runId => getAttribute<String>('run_id') ?? super.runId;

  /// Tracked setter for [runId].
  set runId(String value) => setAttribute('run_id', value);

  /// Tracked getter for [stepName].
  @override
  String get stepName => getAttribute<String>('step_name') ?? super.stepName;

  /// Tracked setter for [stepName].
  set stepName(String value) => setAttribute('step_name', value);

  /// Tracked getter for [topic].
  @override
  String get topic => getAttribute<String>('topic') ?? super.topic;

  /// Tracked setter for [topic].
  set topic(String value) => setAttribute('topic', value);

  /// Tracked getter for [namespace].
  @override
  String get namespace => getAttribute<String>('namespace') ?? super.namespace;

  /// Tracked setter for [namespace].
  set namespace(String value) => setAttribute('namespace', value);

  /// Tracked getter for [data].
  @override
  String? get data => getAttribute<String?>('data') ?? super.data;

  /// Tracked setter for [data].
  set data(String? value) => setAttribute('data', value);

  /// Tracked getter for [createdAt].
  @override
  DateTime get createdAt =>
      getAttribute<DateTime>('created_at') ?? super.createdAt;

  /// Tracked setter for [createdAt].
  set createdAt(DateTime value) => setAttribute('created_at', value);

  /// Tracked getter for [deadline].
  @override
  DateTime? get deadline =>
      getAttribute<DateTime?>('deadline') ?? super.deadline;

  /// Tracked setter for [deadline].
  set deadline(DateTime? value) => setAttribute('deadline', value);

  void _attachOrmRuntimeMetadata(Map<String, Object?> values) {
    replaceAttributes(values);
    attachModelDefinition(_$StemWorkflowWatcherDefinition);
  }
}

class _StemWorkflowWatcherCopyWithSentinel {
  const _StemWorkflowWatcherCopyWithSentinel();
}

extension StemWorkflowWatcherOrmExtension on StemWorkflowWatcher {
  static const _StemWorkflowWatcherCopyWithSentinel _copyWithSentinel =
      _StemWorkflowWatcherCopyWithSentinel();
  StemWorkflowWatcher copyWith({
    Object? runId = _copyWithSentinel,
    Object? stepName = _copyWithSentinel,
    Object? topic = _copyWithSentinel,
    Object? namespace = _copyWithSentinel,
    Object? createdAt = _copyWithSentinel,
    Object? data = _copyWithSentinel,
    Object? deadline = _copyWithSentinel,
  }) {
    return StemWorkflowWatcher(
      runId: identical(runId, _copyWithSentinel) ? this.runId : runId as String,
      stepName: identical(stepName, _copyWithSentinel)
          ? this.stepName
          : stepName as String,
      topic: identical(topic, _copyWithSentinel) ? this.topic : topic as String,
      namespace: identical(namespace, _copyWithSentinel)
          ? this.namespace
          : namespace as String,
      createdAt: identical(createdAt, _copyWithSentinel)
          ? this.createdAt
          : createdAt as DateTime,
      data: identical(data, _copyWithSentinel) ? this.data : data as String?,
      deadline: identical(deadline, _copyWithSentinel)
          ? this.deadline
          : deadline as DateTime?,
    );
  }

  /// Converts this model to a column/value map.
  Map<String, Object?> toMap({ValueCodecRegistry? registry}) =>
      _$StemWorkflowWatcherDefinition.toMap(this, registry: registry);

  /// Builds a model from a column/value map.
  static StemWorkflowWatcher fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$StemWorkflowWatcherDefinition.fromMap(data, registry: registry);

  /// The Type of the generated ORM-managed model class.
  /// Use this when you need to specify the tracked model type explicitly,
  /// for example in generic type parameters.
  static Type get trackedType => $StemWorkflowWatcher;

  /// Converts this immutable model to a tracked ORM-managed model.
  /// The tracked model supports attribute tracking, change detection,
  /// and persistence operations like save() and touch().
  $StemWorkflowWatcher toTracked() {
    return $StemWorkflowWatcher.fromModel(this);
  }
}

extension StemWorkflowWatcherPredicateFields
    on PredicateBuilder<StemWorkflowWatcher> {
  PredicateField<StemWorkflowWatcher, String> get runId =>
      PredicateField<StemWorkflowWatcher, String>(this, 'runId');
  PredicateField<StemWorkflowWatcher, String> get stepName =>
      PredicateField<StemWorkflowWatcher, String>(this, 'stepName');
  PredicateField<StemWorkflowWatcher, String> get topic =>
      PredicateField<StemWorkflowWatcher, String>(this, 'topic');
  PredicateField<StemWorkflowWatcher, String> get namespace =>
      PredicateField<StemWorkflowWatcher, String>(this, 'namespace');
  PredicateField<StemWorkflowWatcher, String?> get data =>
      PredicateField<StemWorkflowWatcher, String?>(this, 'data');
  PredicateField<StemWorkflowWatcher, DateTime> get createdAt =>
      PredicateField<StemWorkflowWatcher, DateTime>(this, 'createdAt');
  PredicateField<StemWorkflowWatcher, DateTime?> get deadline =>
      PredicateField<StemWorkflowWatcher, DateTime?>(this, 'deadline');
}

void registerStemWorkflowWatcherEventHandlers(EventBus bus) {
  // No event handlers registered for StemWorkflowWatcher.
}
