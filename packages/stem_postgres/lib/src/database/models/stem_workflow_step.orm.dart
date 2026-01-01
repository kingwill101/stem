// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'stem_workflow_step.dart';

// **************************************************************************
// OrmModelGenerator
// **************************************************************************

const FieldDefinition _$StemWorkflowStepRunIdField = FieldDefinition(
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

const FieldDefinition _$StemWorkflowStepNameField = FieldDefinition(
  name: 'name',
  columnName: 'name',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: true,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemWorkflowStepNamespaceField = FieldDefinition(
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

const FieldDefinition _$StemWorkflowStepValueField = FieldDefinition(
  name: 'value',
  columnName: 'value',
  dartType: 'String',
  resolvedType: 'String?',
  isPrimaryKey: false,
  isNullable: true,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

Map<String, Object?> _encodeStemWorkflowStepUntracked(
  Object model,
  ValueCodecRegistry registry,
) {
  final m = model as StemWorkflowStep;
  return <String, Object?>{
    'run_id': registry.encodeField(_$StemWorkflowStepRunIdField, m.runId),
    'name': registry.encodeField(_$StemWorkflowStepNameField, m.name),
    'namespace': registry.encodeField(
      _$StemWorkflowStepNamespaceField,
      m.namespace,
    ),
    'value': registry.encodeField(_$StemWorkflowStepValueField, m.value),
  };
}

final ModelDefinition<$StemWorkflowStep> _$StemWorkflowStepDefinition =
    ModelDefinition(
      modelName: 'StemWorkflowStep',
      tableName: 'stem_workflow_steps',
      fields: const [
        _$StemWorkflowStepRunIdField,
        _$StemWorkflowStepNameField,
        _$StemWorkflowStepNamespaceField,
        _$StemWorkflowStepValueField,
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
      untrackedToMap: _encodeStemWorkflowStepUntracked,
      codec: _$StemWorkflowStepCodec(),
    );

extension StemWorkflowStepOrmDefinition on StemWorkflowStep {
  static ModelDefinition<$StemWorkflowStep> get definition =>
      _$StemWorkflowStepDefinition;
}

class StemWorkflowSteps {
  const StemWorkflowSteps._();

  /// Starts building a query for [$StemWorkflowStep].
  ///
  /// {@macro ormed.query}
  static Query<$StemWorkflowStep> query([String? connection]) =>
      Model.query<$StemWorkflowStep>(connection: connection);

  static Future<$StemWorkflowStep?> find(Object id, {String? connection}) =>
      Model.find<$StemWorkflowStep>(id, connection: connection);

  static Future<$StemWorkflowStep> findOrFail(
    Object id, {
    String? connection,
  }) => Model.findOrFail<$StemWorkflowStep>(id, connection: connection);

  static Future<List<$StemWorkflowStep>> all({String? connection}) =>
      Model.all<$StemWorkflowStep>(connection: connection);

  static Future<int> count({String? connection}) =>
      Model.count<$StemWorkflowStep>(connection: connection);

  static Future<bool> anyExist({String? connection}) =>
      Model.anyExist<$StemWorkflowStep>(connection: connection);

  static Query<$StemWorkflowStep> where(
    String column,
    String operator,
    dynamic value, {
    String? connection,
  }) => Model.where<$StemWorkflowStep>(
    column,
    operator,
    value,
    connection: connection,
  );

  static Query<$StemWorkflowStep> whereIn(
    String column,
    List<dynamic> values, {
    String? connection,
  }) =>
      Model.whereIn<$StemWorkflowStep>(column, values, connection: connection);

  static Query<$StemWorkflowStep> orderBy(
    String column, {
    String direction = "asc",
    String? connection,
  }) => Model.orderBy<$StemWorkflowStep>(
    column,
    direction: direction,
    connection: connection,
  );

  static Query<$StemWorkflowStep> limit(int count, {String? connection}) =>
      Model.limit<$StemWorkflowStep>(count, connection: connection);

  /// Creates a [Repository] for [$StemWorkflowStep].
  ///
  /// {@macro ormed.repository}
  static Repository<$StemWorkflowStep> repo([String? connection]) =>
      Model.repository<$StemWorkflowStep>(connection: connection);

  /// Builds a tracked model from a column/value map.
  static $StemWorkflowStep fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$StemWorkflowStepDefinition.fromMap(data, registry: registry);

  /// Converts a tracked model to a column/value map.
  static Map<String, Object?> toMap(
    $StemWorkflowStep model, {
    ValueCodecRegistry? registry,
  }) => _$StemWorkflowStepDefinition.toMap(model, registry: registry);
}

class StemWorkflowStepModelFactory {
  const StemWorkflowStepModelFactory._();

  static ModelDefinition<$StemWorkflowStep> get definition =>
      _$StemWorkflowStepDefinition;

  static ModelCodec<$StemWorkflowStep> get codec => definition.codec;

  static StemWorkflowStep fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => definition.fromMap(data, registry: registry);

  static Map<String, Object?> toMap(
    StemWorkflowStep model, {
    ValueCodecRegistry? registry,
  }) => definition.toMap(model.toTracked(), registry: registry);

  static void registerWith(ModelRegistry registry) =>
      registry.register(definition);

  static ModelFactoryConnection<StemWorkflowStep> withConnection(
    QueryContext context,
  ) => ModelFactoryConnection<StemWorkflowStep>(
    definition: definition,
    context: context,
  );

  static ModelFactoryBuilder<StemWorkflowStep> factory({
    GeneratorProvider? generatorProvider,
  }) => ModelFactoryBuilder<StemWorkflowStep>(
    definition: definition,
    generatorProvider: generatorProvider,
  );
}

class _$StemWorkflowStepCodec extends ModelCodec<$StemWorkflowStep> {
  const _$StemWorkflowStepCodec();
  @override
  Map<String, Object?> encode(
    $StemWorkflowStep model,
    ValueCodecRegistry registry,
  ) {
    return <String, Object?>{
      'run_id': registry.encodeField(_$StemWorkflowStepRunIdField, model.runId),
      'name': registry.encodeField(_$StemWorkflowStepNameField, model.name),
      'namespace': registry.encodeField(
        _$StemWorkflowStepNamespaceField,
        model.namespace,
      ),
      'value': registry.encodeField(_$StemWorkflowStepValueField, model.value),
    };
  }

  @override
  $StemWorkflowStep decode(
    Map<String, Object?> data,
    ValueCodecRegistry registry,
  ) {
    final String stemWorkflowStepRunIdValue =
        registry.decodeField<String>(
          _$StemWorkflowStepRunIdField,
          data['run_id'],
        ) ??
        (throw StateError('Field runId on StemWorkflowStep cannot be null.'));
    final String stemWorkflowStepNameValue =
        registry.decodeField<String>(
          _$StemWorkflowStepNameField,
          data['name'],
        ) ??
        (throw StateError('Field name on StemWorkflowStep cannot be null.'));
    final String stemWorkflowStepNamespaceValue =
        registry.decodeField<String>(
          _$StemWorkflowStepNamespaceField,
          data['namespace'],
        ) ??
        (throw StateError(
          'Field namespace on StemWorkflowStep cannot be null.',
        ));
    final String? stemWorkflowStepValueValue = registry.decodeField<String?>(
      _$StemWorkflowStepValueField,
      data['value'],
    );
    final model = $StemWorkflowStep(
      runId: stemWorkflowStepRunIdValue,
      name: stemWorkflowStepNameValue,
      namespace: stemWorkflowStepNamespaceValue,
      value: stemWorkflowStepValueValue,
    );
    model._attachOrmRuntimeMetadata({
      'run_id': stemWorkflowStepRunIdValue,
      'name': stemWorkflowStepNameValue,
      'namespace': stemWorkflowStepNamespaceValue,
      'value': stemWorkflowStepValueValue,
    });
    return model;
  }
}

/// Insert DTO for [StemWorkflowStep].
///
/// Auto-increment/DB-generated fields are omitted by default.
class StemWorkflowStepInsertDto implements InsertDto<$StemWorkflowStep> {
  const StemWorkflowStepInsertDto({
    this.runId,
    this.name,
    this.namespace,
    this.value,
  });
  final String? runId;
  final String? name;
  final String? namespace;
  final String? value;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (runId != null) 'run_id': runId,
      if (name != null) 'name': name,
      if (namespace != null) 'namespace': namespace,
      if (value != null) 'value': value,
    };
  }

  static const _StemWorkflowStepInsertDtoCopyWithSentinel _copyWithSentinel =
      _StemWorkflowStepInsertDtoCopyWithSentinel();
  StemWorkflowStepInsertDto copyWith({
    Object? runId = _copyWithSentinel,
    Object? name = _copyWithSentinel,
    Object? namespace = _copyWithSentinel,
    Object? value = _copyWithSentinel,
  }) {
    return StemWorkflowStepInsertDto(
      runId: identical(runId, _copyWithSentinel)
          ? this.runId
          : runId as String?,
      name: identical(name, _copyWithSentinel) ? this.name : name as String?,
      namespace: identical(namespace, _copyWithSentinel)
          ? this.namespace
          : namespace as String?,
      value: identical(value, _copyWithSentinel)
          ? this.value
          : value as String?,
    );
  }
}

class _StemWorkflowStepInsertDtoCopyWithSentinel {
  const _StemWorkflowStepInsertDtoCopyWithSentinel();
}

/// Update DTO for [StemWorkflowStep].
///
/// All fields are optional; only provided entries are used in SET clauses.
class StemWorkflowStepUpdateDto implements UpdateDto<$StemWorkflowStep> {
  const StemWorkflowStepUpdateDto({
    this.runId,
    this.name,
    this.namespace,
    this.value,
  });
  final String? runId;
  final String? name;
  final String? namespace;
  final String? value;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (runId != null) 'run_id': runId,
      if (name != null) 'name': name,
      if (namespace != null) 'namespace': namespace,
      if (value != null) 'value': value,
    };
  }

  static const _StemWorkflowStepUpdateDtoCopyWithSentinel _copyWithSentinel =
      _StemWorkflowStepUpdateDtoCopyWithSentinel();
  StemWorkflowStepUpdateDto copyWith({
    Object? runId = _copyWithSentinel,
    Object? name = _copyWithSentinel,
    Object? namespace = _copyWithSentinel,
    Object? value = _copyWithSentinel,
  }) {
    return StemWorkflowStepUpdateDto(
      runId: identical(runId, _copyWithSentinel)
          ? this.runId
          : runId as String?,
      name: identical(name, _copyWithSentinel) ? this.name : name as String?,
      namespace: identical(namespace, _copyWithSentinel)
          ? this.namespace
          : namespace as String?,
      value: identical(value, _copyWithSentinel)
          ? this.value
          : value as String?,
    );
  }
}

class _StemWorkflowStepUpdateDtoCopyWithSentinel {
  const _StemWorkflowStepUpdateDtoCopyWithSentinel();
}

/// Partial projection for [StemWorkflowStep].
///
/// All fields are nullable; intended for subset SELECTs.
class StemWorkflowStepPartial implements PartialEntity<$StemWorkflowStep> {
  const StemWorkflowStepPartial({
    this.runId,
    this.name,
    this.namespace,
    this.value,
  });

  /// Creates a partial from a database row map.
  ///
  /// The [row] keys should be column names (snake_case).
  /// Missing columns will result in null field values.
  factory StemWorkflowStepPartial.fromRow(Map<String, Object?> row) {
    return StemWorkflowStepPartial(
      runId: row['run_id'] as String?,
      name: row['name'] as String?,
      namespace: row['namespace'] as String?,
      value: row['value'] as String?,
    );
  }

  final String? runId;
  final String? name;
  final String? namespace;
  final String? value;

  @override
  $StemWorkflowStep toEntity() {
    // Basic required-field check: non-nullable fields must be present.
    final String? runIdValue = runId;
    if (runIdValue == null) {
      throw StateError('Missing required field: runId');
    }
    final String? nameValue = name;
    if (nameValue == null) {
      throw StateError('Missing required field: name');
    }
    final String? namespaceValue = namespace;
    if (namespaceValue == null) {
      throw StateError('Missing required field: namespace');
    }
    return $StemWorkflowStep(
      runId: runIdValue,
      name: nameValue,
      namespace: namespaceValue,
      value: value,
    );
  }

  @override
  Map<String, Object?> toMap() {
    return {
      if (runId != null) 'run_id': runId,
      if (name != null) 'name': name,
      if (namespace != null) 'namespace': namespace,
      if (value != null) 'value': value,
    };
  }

  static const _StemWorkflowStepPartialCopyWithSentinel _copyWithSentinel =
      _StemWorkflowStepPartialCopyWithSentinel();
  StemWorkflowStepPartial copyWith({
    Object? runId = _copyWithSentinel,
    Object? name = _copyWithSentinel,
    Object? namespace = _copyWithSentinel,
    Object? value = _copyWithSentinel,
  }) {
    return StemWorkflowStepPartial(
      runId: identical(runId, _copyWithSentinel)
          ? this.runId
          : runId as String?,
      name: identical(name, _copyWithSentinel) ? this.name : name as String?,
      namespace: identical(namespace, _copyWithSentinel)
          ? this.namespace
          : namespace as String?,
      value: identical(value, _copyWithSentinel)
          ? this.value
          : value as String?,
    );
  }
}

class _StemWorkflowStepPartialCopyWithSentinel {
  const _StemWorkflowStepPartialCopyWithSentinel();
}

/// Generated tracked model class for [StemWorkflowStep].
///
/// This class extends the user-defined [StemWorkflowStep] model and adds
/// attribute tracking, change detection, and relationship management.
/// Instances of this class are returned by queries and repositories.
///
/// **Do not instantiate this class directly.** Use queries, repositories,
/// or model factories to create tracked model instances.
class $StemWorkflowStep extends StemWorkflowStep
    with ModelAttributes
    implements OrmEntity {
  /// Internal constructor for [$StemWorkflowStep].
  $StemWorkflowStep({
    required String runId,
    required String name,
    required String namespace,
    String? value,
  }) : super(runId: runId, name: name, namespace: namespace, value: value) {
    _attachOrmRuntimeMetadata({
      'run_id': runId,
      'name': name,
      'namespace': namespace,
      'value': value,
    });
  }

  /// Creates a tracked model instance from a user-defined model instance.
  factory $StemWorkflowStep.fromModel(StemWorkflowStep model) {
    return $StemWorkflowStep(
      runId: model.runId,
      name: model.name,
      namespace: model.namespace,
      value: model.value,
    );
  }

  $StemWorkflowStep copyWith({
    String? runId,
    String? name,
    String? namespace,
    String? value,
  }) {
    return $StemWorkflowStep(
      runId: runId ?? this.runId,
      name: name ?? this.name,
      namespace: namespace ?? this.namespace,
      value: value ?? this.value,
    );
  }

  /// Builds a tracked model from a column/value map.
  static $StemWorkflowStep fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$StemWorkflowStepDefinition.fromMap(data, registry: registry);

  /// Converts this tracked model to a column/value map.
  Map<String, Object?> toMap({ValueCodecRegistry? registry}) =>
      _$StemWorkflowStepDefinition.toMap(this, registry: registry);

  /// Tracked getter for [runId].
  @override
  String get runId => getAttribute<String>('run_id') ?? super.runId;

  /// Tracked setter for [runId].
  set runId(String value) => setAttribute('run_id', value);

  /// Tracked getter for [name].
  @override
  String get name => getAttribute<String>('name') ?? super.name;

  /// Tracked setter for [name].
  set name(String value) => setAttribute('name', value);

  /// Tracked getter for [namespace].
  @override
  String get namespace => getAttribute<String>('namespace') ?? super.namespace;

  /// Tracked setter for [namespace].
  set namespace(String value) => setAttribute('namespace', value);

  /// Tracked getter for [value].
  @override
  String? get value => getAttribute<String?>('value') ?? super.value;

  /// Tracked setter for [value].
  set value(String? value) => setAttribute('value', value);

  void _attachOrmRuntimeMetadata(Map<String, Object?> values) {
    replaceAttributes(values);
    attachModelDefinition(_$StemWorkflowStepDefinition);
  }
}

class _StemWorkflowStepCopyWithSentinel {
  const _StemWorkflowStepCopyWithSentinel();
}

extension StemWorkflowStepOrmExtension on StemWorkflowStep {
  static const _StemWorkflowStepCopyWithSentinel _copyWithSentinel =
      _StemWorkflowStepCopyWithSentinel();
  StemWorkflowStep copyWith({
    Object? runId = _copyWithSentinel,
    Object? name = _copyWithSentinel,
    Object? namespace = _copyWithSentinel,
    Object? value = _copyWithSentinel,
  }) {
    return StemWorkflowStep(
      runId: identical(runId, _copyWithSentinel) ? this.runId : runId as String,
      name: identical(name, _copyWithSentinel) ? this.name : name as String,
      namespace: identical(namespace, _copyWithSentinel)
          ? this.namespace
          : namespace as String,
      value: identical(value, _copyWithSentinel)
          ? this.value
          : value as String?,
    );
  }

  /// Converts this model to a column/value map.
  Map<String, Object?> toMap({ValueCodecRegistry? registry}) =>
      _$StemWorkflowStepDefinition.toMap(this, registry: registry);

  /// Builds a model from a column/value map.
  static StemWorkflowStep fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$StemWorkflowStepDefinition.fromMap(data, registry: registry);

  /// The Type of the generated ORM-managed model class.
  /// Use this when you need to specify the tracked model type explicitly,
  /// for example in generic type parameters.
  static Type get trackedType => $StemWorkflowStep;

  /// Converts this immutable model to a tracked ORM-managed model.
  /// The tracked model supports attribute tracking, change detection,
  /// and persistence operations like save() and touch().
  $StemWorkflowStep toTracked() {
    return $StemWorkflowStep.fromModel(this);
  }
}

extension StemWorkflowStepPredicateFields
    on PredicateBuilder<StemWorkflowStep> {
  PredicateField<StemWorkflowStep, String> get runId =>
      PredicateField<StemWorkflowStep, String>(this, 'runId');
  PredicateField<StemWorkflowStep, String> get name =>
      PredicateField<StemWorkflowStep, String>(this, 'name');
  PredicateField<StemWorkflowStep, String> get namespace =>
      PredicateField<StemWorkflowStep, String>(this, 'namespace');
  PredicateField<StemWorkflowStep, String?> get value =>
      PredicateField<StemWorkflowStep, String?>(this, 'value');
}

void registerStemWorkflowStepEventHandlers(EventBus bus) {
  // No event handlers registered for StemWorkflowStep.
}
