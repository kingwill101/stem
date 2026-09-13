// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'stem_workflow_journal.dart';

// **************************************************************************
// OrmModelGenerator
// **************************************************************************

const FieldDefinition _$StemWorkflowJournalNamespaceField = FieldDefinition(
  name: 'namespace',
  columnName: 'namespace',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: true,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemWorkflowJournalRunIdField = FieldDefinition(
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

const FieldDefinition _$StemWorkflowJournalKindField = FieldDefinition(
  name: 'kind',
  columnName: 'kind',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: true,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemWorkflowJournalNameField = FieldDefinition(
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

const FieldDefinition _$StemWorkflowJournalRevisionField = FieldDefinition(
  name: 'revision',
  columnName: 'revision',
  dartType: 'int',
  resolvedType: 'int',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemWorkflowJournalDataField = FieldDefinition(
  name: 'data',
  columnName: 'data',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemWorkflowJournalPositionField = FieldDefinition(
  name: 'position',
  columnName: 'position',
  dartType: 'int',
  resolvedType: 'int?',
  isPrimaryKey: false,
  isNullable: true,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

Map<String, Object?> _encodeStemWorkflowJournalUntracked(
  Object model,
  ValueCodecRegistry registry,
) {
  final m = model as StemWorkflowJournal;
  return <String, Object?>{
    'namespace': registry.encodeField(
      _$StemWorkflowJournalNamespaceField,
      m.namespace,
    ),
    'run_id': registry.encodeField(_$StemWorkflowJournalRunIdField, m.runId),
    'kind': registry.encodeField(_$StemWorkflowJournalKindField, m.kind),
    'name': registry.encodeField(_$StemWorkflowJournalNameField, m.name),
    'revision': registry.encodeField(
      _$StemWorkflowJournalRevisionField,
      m.revision,
    ),
    'data': registry.encodeField(_$StemWorkflowJournalDataField, m.data),
    'position': registry.encodeField(
      _$StemWorkflowJournalPositionField,
      m.position,
    ),
  };
}

final ModelDefinition<$StemWorkflowJournal> _$StemWorkflowJournalDefinition =
    ModelDefinition(
      modelName: 'StemWorkflowJournal',
      tableName: 'wf_journal',
      fields: const [
        _$StemWorkflowJournalNamespaceField,
        _$StemWorkflowJournalRunIdField,
        _$StemWorkflowJournalKindField,
        _$StemWorkflowJournalNameField,
        _$StemWorkflowJournalRevisionField,
        _$StemWorkflowJournalDataField,
        _$StemWorkflowJournalPositionField,
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
      untrackedToMap: _encodeStemWorkflowJournalUntracked,
      codec: _$StemWorkflowJournalCodec(),
    );

extension StemWorkflowJournalOrmDefinition on StemWorkflowJournal {
  static ModelDefinition<$StemWorkflowJournal> get definition =>
      _$StemWorkflowJournalDefinition;
}

class StemWorkflowJournals {
  const StemWorkflowJournals._();

  /// Starts building a query for [$StemWorkflowJournal].
  ///
  /// {@macro ormed.query}
  static Query<$StemWorkflowJournal> query([String? connection]) =>
      Model.query<$StemWorkflowJournal>(connection: connection);

  static Future<$StemWorkflowJournal?> find(Object id, {String? connection}) =>
      Model.find<$StemWorkflowJournal>(id, connection: connection);

  static Future<$StemWorkflowJournal> findOrFail(
    Object id, {
    String? connection,
  }) => Model.findOrFail<$StemWorkflowJournal>(id, connection: connection);

  static Future<List<$StemWorkflowJournal>> all({String? connection}) =>
      // ignore: ormed/ormed_get_without_limit
      Model.all<$StemWorkflowJournal>(connection: connection);

  static Future<int> count({String? connection}) =>
      Model.count<$StemWorkflowJournal>(connection: connection);

  static Future<bool> anyExist({String? connection}) =>
      Model.anyExist<$StemWorkflowJournal>(connection: connection);

  static Query<$StemWorkflowJournal> where(
    String column,
    String operator,
    dynamic value, {
    String? connection,
  }) => Model.where<$StemWorkflowJournal>(
    column,
    operator,
    value,
    connection: connection,
  );

  static Query<$StemWorkflowJournal> whereIn(
    String column,
    List<dynamic> values, {
    String? connection,
  }) => Model.whereIn<$StemWorkflowJournal>(
    column,
    values,
    connection: connection,
  );

  static Query<$StemWorkflowJournal> orderBy(
    String column, {
    String direction = "asc",
    String? connection,
  }) => Model.orderBy<$StemWorkflowJournal>(
    column,
    direction: direction,
    connection: connection,
  );

  static Query<$StemWorkflowJournal> limit(int count, {String? connection}) =>
      Model.limit<$StemWorkflowJournal>(count, connection: connection);

  /// Creates a [Repository] for [$StemWorkflowJournal].
  ///
  /// {@macro ormed.repository}
  static Repository<$StemWorkflowJournal> repo([String? connection]) =>
      Model.repository<$StemWorkflowJournal>(connection: connection);

  /// Builds a tracked model from a column/value map.
  static $StemWorkflowJournal fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$StemWorkflowJournalDefinition.fromMap(data, registry: registry);

  /// Converts a tracked model to a column/value map.
  static Map<String, Object?> toMap(
    $StemWorkflowJournal model, {
    ValueCodecRegistry? registry,
  }) => _$StemWorkflowJournalDefinition.toMap(model, registry: registry);
}

class StemWorkflowJournalModelFactory {
  const StemWorkflowJournalModelFactory._();

  static ModelDefinition<$StemWorkflowJournal> get definition =>
      _$StemWorkflowJournalDefinition;

  static ModelCodec<$StemWorkflowJournal> get codec => definition.codec;

  static StemWorkflowJournal fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => definition.fromMap(data, registry: registry);

  static Map<String, Object?> toMap(
    StemWorkflowJournal model, {
    ValueCodecRegistry? registry,
  }) => definition.toMap(model.toTracked(), registry: registry);

  static void registerWith(ModelRegistry registry) =>
      registry.register(definition);

  static ModelFactoryConnection<StemWorkflowJournal> withConnection(
    QueryContext context,
  ) => ModelFactoryConnection<StemWorkflowJournal>(
    definition: definition,
    context: context,
  );

  static ModelFactoryBuilder<StemWorkflowJournal> factory({
    GeneratorProvider? generatorProvider,
  }) => ModelFactoryRegistry.factoryFor<StemWorkflowJournal>(
    generatorProvider: generatorProvider,
  );
}

class _$StemWorkflowJournalCodec extends ModelCodec<$StemWorkflowJournal> {
  const _$StemWorkflowJournalCodec();
  @override
  Map<String, Object?> encode(
    $StemWorkflowJournal model,
    ValueCodecRegistry registry,
  ) {
    return <String, Object?>{
      'namespace': registry.encodeField(
        _$StemWorkflowJournalNamespaceField,
        model.namespace,
      ),
      'run_id': registry.encodeField(
        _$StemWorkflowJournalRunIdField,
        model.runId,
      ),
      'kind': registry.encodeField(_$StemWorkflowJournalKindField, model.kind),
      'name': registry.encodeField(_$StemWorkflowJournalNameField, model.name),
      'revision': registry.encodeField(
        _$StemWorkflowJournalRevisionField,
        model.revision,
      ),
      'data': registry.encodeField(_$StemWorkflowJournalDataField, model.data),
      'position': registry.encodeField(
        _$StemWorkflowJournalPositionField,
        model.position,
      ),
    };
  }

  @override
  $StemWorkflowJournal decode(
    Map<String, Object?> data,
    ValueCodecRegistry registry,
  ) {
    final String stemWorkflowJournalNamespaceValue =
        registry.decodeField<String>(
          _$StemWorkflowJournalNamespaceField,
          data['namespace'],
        ) ??
        (throw StateError(
          'Field namespace on StemWorkflowJournal cannot be null.',
        ));
    final String stemWorkflowJournalRunIdValue =
        registry.decodeField<String>(
          _$StemWorkflowJournalRunIdField,
          data['run_id'],
        ) ??
        (throw StateError(
          'Field runId on StemWorkflowJournal cannot be null.',
        ));
    final String stemWorkflowJournalKindValue =
        registry.decodeField<String>(
          _$StemWorkflowJournalKindField,
          data['kind'],
        ) ??
        (throw StateError('Field kind on StemWorkflowJournal cannot be null.'));
    final String stemWorkflowJournalNameValue =
        registry.decodeField<String>(
          _$StemWorkflowJournalNameField,
          data['name'],
        ) ??
        (throw StateError('Field name on StemWorkflowJournal cannot be null.'));
    final int stemWorkflowJournalRevisionValue =
        registry.decodeField<int>(
          _$StemWorkflowJournalRevisionField,
          data['revision'],
        ) ??
        (throw StateError(
          'Field revision on StemWorkflowJournal cannot be null.',
        ));
    final String stemWorkflowJournalDataValue =
        registry.decodeField<String>(
          _$StemWorkflowJournalDataField,
          data['data'],
        ) ??
        (throw StateError('Field data on StemWorkflowJournal cannot be null.'));
    final int? stemWorkflowJournalPositionValue = registry.decodeField<int?>(
      _$StemWorkflowJournalPositionField,
      data['position'],
    );
    final model = $StemWorkflowJournal(
      namespace: stemWorkflowJournalNamespaceValue,
      runId: stemWorkflowJournalRunIdValue,
      kind: stemWorkflowJournalKindValue,
      name: stemWorkflowJournalNameValue,
      revision: stemWorkflowJournalRevisionValue,
      data: stemWorkflowJournalDataValue,
      position: stemWorkflowJournalPositionValue,
    );
    model._attachOrmRuntimeMetadata({
      'namespace': stemWorkflowJournalNamespaceValue,
      'run_id': stemWorkflowJournalRunIdValue,
      'kind': stemWorkflowJournalKindValue,
      'name': stemWorkflowJournalNameValue,
      'revision': stemWorkflowJournalRevisionValue,
      'data': stemWorkflowJournalDataValue,
      'position': stemWorkflowJournalPositionValue,
    });
    return model;
  }
}

/// Insert DTO for [StemWorkflowJournal].
///
/// Auto-increment/DB-generated fields are omitted by default.
class StemWorkflowJournalInsertDto implements InsertDto<$StemWorkflowJournal> {
  const StemWorkflowJournalInsertDto({
    this.namespace,
    this.runId,
    this.kind,
    this.name,
    this.revision,
    this.data,
    this.position,
  });
  final String? namespace;
  final String? runId;
  final String? kind;
  final String? name;
  final int? revision;
  final String? data;
  final int? position;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (namespace != null) 'namespace': namespace,
      if (runId != null) 'run_id': runId,
      if (kind != null) 'kind': kind,
      if (name != null) 'name': name,
      if (revision != null) 'revision': revision,
      if (data != null) 'data': data,
      if (position != null) 'position': position,
    };
  }

  static const _StemWorkflowJournalInsertDtoCopyWithSentinel _copyWithSentinel =
      _StemWorkflowJournalInsertDtoCopyWithSentinel();
  StemWorkflowJournalInsertDto copyWith({
    Object? namespace = _copyWithSentinel,
    Object? runId = _copyWithSentinel,
    Object? kind = _copyWithSentinel,
    Object? name = _copyWithSentinel,
    Object? revision = _copyWithSentinel,
    Object? data = _copyWithSentinel,
    Object? position = _copyWithSentinel,
  }) {
    return StemWorkflowJournalInsertDto(
      namespace: identical(namespace, _copyWithSentinel)
          ? this.namespace
          : namespace as String?,
      runId: identical(runId, _copyWithSentinel)
          ? this.runId
          : runId as String?,
      kind: identical(kind, _copyWithSentinel) ? this.kind : kind as String?,
      name: identical(name, _copyWithSentinel) ? this.name : name as String?,
      revision: identical(revision, _copyWithSentinel)
          ? this.revision
          : revision as int?,
      data: identical(data, _copyWithSentinel) ? this.data : data as String?,
      position: identical(position, _copyWithSentinel)
          ? this.position
          : position as int?,
    );
  }
}

class _StemWorkflowJournalInsertDtoCopyWithSentinel {
  const _StemWorkflowJournalInsertDtoCopyWithSentinel();
}

/// Update DTO for [StemWorkflowJournal].
///
/// All fields are optional; only provided entries are used in SET clauses.
class StemWorkflowJournalUpdateDto implements UpdateDto<$StemWorkflowJournal> {
  const StemWorkflowJournalUpdateDto({
    this.namespace,
    this.runId,
    this.kind,
    this.name,
    this.revision,
    this.data,
    this.position,
  });
  final String? namespace;
  final String? runId;
  final String? kind;
  final String? name;
  final int? revision;
  final String? data;
  final int? position;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (namespace != null) 'namespace': namespace,
      if (runId != null) 'run_id': runId,
      if (kind != null) 'kind': kind,
      if (name != null) 'name': name,
      if (revision != null) 'revision': revision,
      if (data != null) 'data': data,
      if (position != null) 'position': position,
    };
  }

  static const _StemWorkflowJournalUpdateDtoCopyWithSentinel _copyWithSentinel =
      _StemWorkflowJournalUpdateDtoCopyWithSentinel();
  StemWorkflowJournalUpdateDto copyWith({
    Object? namespace = _copyWithSentinel,
    Object? runId = _copyWithSentinel,
    Object? kind = _copyWithSentinel,
    Object? name = _copyWithSentinel,
    Object? revision = _copyWithSentinel,
    Object? data = _copyWithSentinel,
    Object? position = _copyWithSentinel,
  }) {
    return StemWorkflowJournalUpdateDto(
      namespace: identical(namespace, _copyWithSentinel)
          ? this.namespace
          : namespace as String?,
      runId: identical(runId, _copyWithSentinel)
          ? this.runId
          : runId as String?,
      kind: identical(kind, _copyWithSentinel) ? this.kind : kind as String?,
      name: identical(name, _copyWithSentinel) ? this.name : name as String?,
      revision: identical(revision, _copyWithSentinel)
          ? this.revision
          : revision as int?,
      data: identical(data, _copyWithSentinel) ? this.data : data as String?,
      position: identical(position, _copyWithSentinel)
          ? this.position
          : position as int?,
    );
  }
}

class _StemWorkflowJournalUpdateDtoCopyWithSentinel {
  const _StemWorkflowJournalUpdateDtoCopyWithSentinel();
}

/// Partial projection for [StemWorkflowJournal].
///
/// All fields are nullable; intended for subset SELECTs.
class StemWorkflowJournalPartial
    implements PartialEntity<$StemWorkflowJournal> {
  const StemWorkflowJournalPartial({
    this.namespace,
    this.runId,
    this.kind,
    this.name,
    this.revision,
    this.data,
    this.position,
  });

  /// Creates a partial from a database row map.
  ///
  /// The [row] keys should be column names (snake_case).
  /// Missing columns will result in null field values.
  factory StemWorkflowJournalPartial.fromRow(Map<String, Object?> row) {
    return StemWorkflowJournalPartial(
      namespace: row['namespace'] as String?,
      runId: row['run_id'] as String?,
      kind: row['kind'] as String?,
      name: row['name'] as String?,
      revision: row['revision'] as int?,
      data: row['data'] as String?,
      position: row['position'] as int?,
    );
  }

  final String? namespace;
  final String? runId;
  final String? kind;
  final String? name;
  final int? revision;
  final String? data;
  final int? position;

  @override
  $StemWorkflowJournal toEntity() {
    // Basic required-field check: non-nullable fields must be present.
    final String? namespaceValue = namespace;
    if (namespaceValue == null) {
      throw StateError('Missing required field: namespace');
    }
    final String? runIdValue = runId;
    if (runIdValue == null) {
      throw StateError('Missing required field: runId');
    }
    final String? kindValue = kind;
    if (kindValue == null) {
      throw StateError('Missing required field: kind');
    }
    final String? nameValue = name;
    if (nameValue == null) {
      throw StateError('Missing required field: name');
    }
    final int? revisionValue = revision;
    if (revisionValue == null) {
      throw StateError('Missing required field: revision');
    }
    final String? dataValue = data;
    if (dataValue == null) {
      throw StateError('Missing required field: data');
    }
    return $StemWorkflowJournal(
      namespace: namespaceValue,
      runId: runIdValue,
      kind: kindValue,
      name: nameValue,
      revision: revisionValue,
      data: dataValue,
      position: position,
    );
  }

  @override
  Map<String, Object?> toMap() {
    return {
      if (namespace != null) 'namespace': namespace,
      if (runId != null) 'run_id': runId,
      if (kind != null) 'kind': kind,
      if (name != null) 'name': name,
      if (revision != null) 'revision': revision,
      if (data != null) 'data': data,
      if (position != null) 'position': position,
    };
  }

  static const _StemWorkflowJournalPartialCopyWithSentinel _copyWithSentinel =
      _StemWorkflowJournalPartialCopyWithSentinel();
  StemWorkflowJournalPartial copyWith({
    Object? namespace = _copyWithSentinel,
    Object? runId = _copyWithSentinel,
    Object? kind = _copyWithSentinel,
    Object? name = _copyWithSentinel,
    Object? revision = _copyWithSentinel,
    Object? data = _copyWithSentinel,
    Object? position = _copyWithSentinel,
  }) {
    return StemWorkflowJournalPartial(
      namespace: identical(namespace, _copyWithSentinel)
          ? this.namespace
          : namespace as String?,
      runId: identical(runId, _copyWithSentinel)
          ? this.runId
          : runId as String?,
      kind: identical(kind, _copyWithSentinel) ? this.kind : kind as String?,
      name: identical(name, _copyWithSentinel) ? this.name : name as String?,
      revision: identical(revision, _copyWithSentinel)
          ? this.revision
          : revision as int?,
      data: identical(data, _copyWithSentinel) ? this.data : data as String?,
      position: identical(position, _copyWithSentinel)
          ? this.position
          : position as int?,
    );
  }
}

class _StemWorkflowJournalPartialCopyWithSentinel {
  const _StemWorkflowJournalPartialCopyWithSentinel();
}

/// Generated tracked model class for [StemWorkflowJournal].
///
/// This class extends the user-defined [StemWorkflowJournal] model and adds
/// attribute tracking, change detection, and relationship management.
/// Instances of this class are returned by queries and repositories.
///
/// **Do not instantiate this class directly.** Use queries, repositories,
/// or model factories to create tracked model instances.
class $StemWorkflowJournal extends StemWorkflowJournal
    with ModelAttributes
    implements OrmEntity {
  /// Internal constructor for [$StemWorkflowJournal].
  $StemWorkflowJournal({
    required String namespace,
    required String runId,
    required String kind,
    required String name,
    required int revision,
    required String data,
    int? position,
  }) : super(
         namespace: namespace,
         runId: runId,
         kind: kind,
         name: name,
         revision: revision,
         data: data,
         position: position,
       ) {
    _attachOrmRuntimeMetadata({
      'namespace': namespace,
      'run_id': runId,
      'kind': kind,
      'name': name,
      'revision': revision,
      'data': data,
      'position': position,
    });
  }

  /// Creates a tracked model instance from a user-defined model instance.
  factory $StemWorkflowJournal.fromModel(StemWorkflowJournal model) {
    return $StemWorkflowJournal(
      namespace: model.namespace,
      runId: model.runId,
      kind: model.kind,
      name: model.name,
      revision: model.revision,
      data: model.data,
      position: model.position,
    );
  }

  $StemWorkflowJournal copyWith({
    String? namespace,
    String? runId,
    String? kind,
    String? name,
    int? revision,
    String? data,
    int? position,
  }) {
    return $StemWorkflowJournal(
      namespace: namespace ?? this.namespace,
      runId: runId ?? this.runId,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      revision: revision ?? this.revision,
      data: data ?? this.data,
      position: position ?? this.position,
    );
  }

  /// Builds a tracked model from a column/value map.
  static $StemWorkflowJournal fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$StemWorkflowJournalDefinition.fromMap(data, registry: registry);

  /// Converts this tracked model to a column/value map.
  Map<String, Object?> toMap({ValueCodecRegistry? registry}) =>
      _$StemWorkflowJournalDefinition.toMap(this, registry: registry);

  /// Tracked getter for [namespace].
  @override
  String get namespace => getAttribute<String>('namespace') ?? super.namespace;

  /// Tracked setter for [namespace].
  set namespace(String value) => setAttribute('namespace', value);

  /// Tracked getter for [runId].
  @override
  String get runId => getAttribute<String>('run_id') ?? super.runId;

  /// Tracked setter for [runId].
  set runId(String value) => setAttribute('run_id', value);

  /// Tracked getter for [kind].
  @override
  String get kind => getAttribute<String>('kind') ?? super.kind;

  /// Tracked setter for [kind].
  set kind(String value) => setAttribute('kind', value);

  /// Tracked getter for [name].
  @override
  String get name => getAttribute<String>('name') ?? super.name;

  /// Tracked setter for [name].
  set name(String value) => setAttribute('name', value);

  /// Tracked getter for [revision].
  @override
  int get revision => getAttribute<int>('revision') ?? super.revision;

  /// Tracked setter for [revision].
  set revision(int value) => setAttribute('revision', value);

  /// Tracked getter for [data].
  @override
  String get data => getAttribute<String>('data') ?? super.data;

  /// Tracked setter for [data].
  set data(String value) => setAttribute('data', value);

  /// Tracked getter for [position].
  @override
  int? get position => getAttribute<int?>('position') ?? super.position;

  /// Tracked setter for [position].
  set position(int? value) => setAttribute('position', value);

  void _attachOrmRuntimeMetadata(Map<String, Object?> values) {
    replaceAttributes(values);
    attachModelDefinition(_$StemWorkflowJournalDefinition);
  }
}

class _StemWorkflowJournalCopyWithSentinel {
  const _StemWorkflowJournalCopyWithSentinel();
}

extension StemWorkflowJournalOrmExtension on StemWorkflowJournal {
  static const _StemWorkflowJournalCopyWithSentinel _copyWithSentinel =
      _StemWorkflowJournalCopyWithSentinel();
  StemWorkflowJournal copyWith({
    Object? namespace = _copyWithSentinel,
    Object? runId = _copyWithSentinel,
    Object? kind = _copyWithSentinel,
    Object? name = _copyWithSentinel,
    Object? revision = _copyWithSentinel,
    Object? data = _copyWithSentinel,
    Object? position = _copyWithSentinel,
  }) {
    return StemWorkflowJournal(
      namespace: identical(namespace, _copyWithSentinel)
          ? this.namespace
          : namespace as String,
      runId: identical(runId, _copyWithSentinel) ? this.runId : runId as String,
      kind: identical(kind, _copyWithSentinel) ? this.kind : kind as String,
      name: identical(name, _copyWithSentinel) ? this.name : name as String,
      revision: identical(revision, _copyWithSentinel)
          ? this.revision
          : revision as int,
      data: identical(data, _copyWithSentinel) ? this.data : data as String,
      position: identical(position, _copyWithSentinel)
          ? this.position
          : position as int?,
    );
  }

  /// Converts this model to a column/value map.
  Map<String, Object?> toMap({ValueCodecRegistry? registry}) =>
      _$StemWorkflowJournalDefinition.toMap(this, registry: registry);

  /// Builds a model from a column/value map.
  static StemWorkflowJournal fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$StemWorkflowJournalDefinition.fromMap(data, registry: registry);

  /// The Type of the generated ORM-managed model class.
  /// Use this when you need to specify the tracked model type explicitly,
  /// for example in generic type parameters.
  static Type get trackedType => $StemWorkflowJournal;

  /// Converts this immutable model to a tracked ORM-managed model.
  /// The tracked model supports attribute tracking, change detection,
  /// and persistence operations like save() and touch().
  $StemWorkflowJournal toTracked() {
    return $StemWorkflowJournal.fromModel(this);
  }
}

extension StemWorkflowJournalPredicateFields
    on PredicateBuilder<StemWorkflowJournal> {
  PredicateField<StemWorkflowJournal, String> get namespace =>
      PredicateField<StemWorkflowJournal, String>(this, 'namespace');
  PredicateField<StemWorkflowJournal, String> get runId =>
      PredicateField<StemWorkflowJournal, String>(this, 'runId');
  PredicateField<StemWorkflowJournal, String> get kind =>
      PredicateField<StemWorkflowJournal, String>(this, 'kind');
  PredicateField<StemWorkflowJournal, String> get name =>
      PredicateField<StemWorkflowJournal, String>(this, 'name');
  PredicateField<StemWorkflowJournal, int> get revision =>
      PredicateField<StemWorkflowJournal, int>(this, 'revision');
  PredicateField<StemWorkflowJournal, String> get data =>
      PredicateField<StemWorkflowJournal, String>(this, 'data');
  PredicateField<StemWorkflowJournal, int?> get position =>
      PredicateField<StemWorkflowJournal, int?>(this, 'position');
}

void registerStemWorkflowJournalEventHandlers(EventBus bus) {
  // No event handlers registered for StemWorkflowJournal.
}
