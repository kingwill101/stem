// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'stem_group.dart';

// **************************************************************************
// OrmModelGenerator
// **************************************************************************

const FieldDefinition _$StemGroupIdField = FieldDefinition(
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

const FieldDefinition _$StemGroupNamespaceField = FieldDefinition(
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

const FieldDefinition _$StemGroupExpectedField = FieldDefinition(
  name: 'expected',
  columnName: 'expected',
  dartType: 'int',
  resolvedType: 'int',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemGroupMetaField = FieldDefinition(
  name: 'meta',
  columnName: 'meta',
  dartType: 'Map<String, Object?>',
  resolvedType: 'Map<String, Object?>',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
  codecType: 'json',
);

const FieldDefinition _$StemGroupExpiresAtField = FieldDefinition(
  name: 'expiresAt',
  columnName: 'expires_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemGroupCreatedAtField = FieldDefinition(
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

const FieldDefinition _$StemGroupUpdatedAtField = FieldDefinition(
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

const RelationDefinition _$StemGroupResultsRelation = RelationDefinition(
  name: 'results',
  kind: RelationKind.hasMany,
  targetModel: 'StemGroupResult',
  foreignKey: 'group_id',
);

Map<String, Object?> _encodeStemGroupUntracked(
  Object model,
  ValueCodecRegistry registry,
) {
  final m = model as StemGroup;
  return <String, Object?>{
    'id': registry.encodeField(_$StemGroupIdField, m.id),
    'namespace': registry.encodeField(_$StemGroupNamespaceField, m.namespace),
    'expected': registry.encodeField(_$StemGroupExpectedField, m.expected),
    'meta': registry.encodeField(_$StemGroupMetaField, m.meta),
    'expires_at': registry.encodeField(_$StemGroupExpiresAtField, m.expiresAt),
  };
}

final ModelDefinition<$StemGroup> _$StemGroupDefinition = ModelDefinition(
  modelName: 'StemGroup',
  tableName: 'stem_groups',
  fields: const [
    _$StemGroupIdField,
    _$StemGroupNamespaceField,
    _$StemGroupExpectedField,
    _$StemGroupMetaField,
    _$StemGroupExpiresAtField,
    _$StemGroupCreatedAtField,
    _$StemGroupUpdatedAtField,
  ],
  relations: const [_$StemGroupResultsRelation],
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
    fieldOverrides: const {'meta': FieldAttributeMetadata(cast: 'json')},
    softDeletes: false,
    softDeleteColumn: 'deleted_at',
  ),
  untrackedToMap: _encodeStemGroupUntracked,
  codec: _$StemGroupCodec(),
);

extension StemGroupOrmDefinition on StemGroup {
  static ModelDefinition<$StemGroup> get definition => _$StemGroupDefinition;
}

class StemGroups {
  const StemGroups._();

  /// Starts building a query for [$StemGroup].
  ///
  /// {@macro ormed.query}
  static Query<$StemGroup> query([String? connection]) =>
      Model.query<$StemGroup>(connection: connection);

  static Future<$StemGroup?> find(Object id, {String? connection}) =>
      Model.find<$StemGroup>(id, connection: connection);

  static Future<$StemGroup> findOrFail(Object id, {String? connection}) =>
      Model.findOrFail<$StemGroup>(id, connection: connection);

  static Future<List<$StemGroup>> all({String? connection}) =>
      Model.all<$StemGroup>(connection: connection);

  static Future<int> count({String? connection}) =>
      Model.count<$StemGroup>(connection: connection);

  static Future<bool> anyExist({String? connection}) =>
      Model.anyExist<$StemGroup>(connection: connection);

  static Query<$StemGroup> where(
    String column,
    String operator,
    dynamic value, {
    String? connection,
  }) =>
      Model.where<$StemGroup>(column, operator, value, connection: connection);

  static Query<$StemGroup> whereIn(
    String column,
    List<dynamic> values, {
    String? connection,
  }) => Model.whereIn<$StemGroup>(column, values, connection: connection);

  static Query<$StemGroup> orderBy(
    String column, {
    String direction = "asc",
    String? connection,
  }) => Model.orderBy<$StemGroup>(
    column,
    direction: direction,
    connection: connection,
  );

  static Query<$StemGroup> limit(int count, {String? connection}) =>
      Model.limit<$StemGroup>(count, connection: connection);

  /// Creates a [Repository] for [$StemGroup].
  ///
  /// {@macro ormed.repository}
  static Repository<$StemGroup> repo([String? connection]) =>
      Model.repository<$StemGroup>(connection: connection);

  /// Builds a tracked model from a column/value map.
  static $StemGroup fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$StemGroupDefinition.fromMap(data, registry: registry);

  /// Converts a tracked model to a column/value map.
  static Map<String, Object?> toMap(
    $StemGroup model, {
    ValueCodecRegistry? registry,
  }) => _$StemGroupDefinition.toMap(model, registry: registry);
}

class StemGroupModelFactory {
  const StemGroupModelFactory._();

  static ModelDefinition<$StemGroup> get definition => _$StemGroupDefinition;

  static ModelCodec<$StemGroup> get codec => definition.codec;

  static StemGroup fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => definition.fromMap(data, registry: registry);

  static Map<String, Object?> toMap(
    StemGroup model, {
    ValueCodecRegistry? registry,
  }) => definition.toMap(model.toTracked(), registry: registry);

  static void registerWith(ModelRegistry registry) =>
      registry.register(definition);

  static ModelFactoryConnection<StemGroup> withConnection(
    QueryContext context,
  ) => ModelFactoryConnection<StemGroup>(
    definition: definition,
    context: context,
  );

  static ModelFactoryBuilder<StemGroup> factory({
    GeneratorProvider? generatorProvider,
  }) => ModelFactoryBuilder<StemGroup>(
    definition: definition,
    generatorProvider: generatorProvider,
  );
}

class _$StemGroupCodec extends ModelCodec<$StemGroup> {
  const _$StemGroupCodec();
  @override
  Map<String, Object?> encode($StemGroup model, ValueCodecRegistry registry) {
    return <String, Object?>{
      'id': registry.encodeField(_$StemGroupIdField, model.id),
      'namespace': registry.encodeField(
        _$StemGroupNamespaceField,
        model.namespace,
      ),
      'expected': registry.encodeField(
        _$StemGroupExpectedField,
        model.expected,
      ),
      'meta': registry.encodeField(_$StemGroupMetaField, model.meta),
      'expires_at': registry.encodeField(
        _$StemGroupExpiresAtField,
        model.expiresAt,
      ),
      if (model.hasAttribute('created_at'))
        'created_at': registry.encodeField(
          _$StemGroupCreatedAtField,
          model.getAttribute<DateTime?>('created_at'),
        ),
      if (model.hasAttribute('updated_at'))
        'updated_at': registry.encodeField(
          _$StemGroupUpdatedAtField,
          model.getAttribute<DateTime?>('updated_at'),
        ),
    };
  }

  @override
  $StemGroup decode(Map<String, Object?> data, ValueCodecRegistry registry) {
    final String stemGroupIdValue =
        registry.decodeField<String>(_$StemGroupIdField, data['id']) ??
        (throw StateError('Field id on StemGroup cannot be null.'));
    final String stemGroupNamespaceValue =
        registry.decodeField<String>(
          _$StemGroupNamespaceField,
          data['namespace'],
        ) ??
        (throw StateError('Field namespace on StemGroup cannot be null.'));
    final int stemGroupExpectedValue =
        registry.decodeField<int>(_$StemGroupExpectedField, data['expected']) ??
        (throw StateError('Field expected on StemGroup cannot be null.'));
    final Map<String, Object?> stemGroupMetaValue =
        registry.decodeField<Map<String, Object?>>(
          _$StemGroupMetaField,
          data['meta'],
        ) ??
        (throw StateError('Field meta on StemGroup cannot be null.'));
    final DateTime stemGroupExpiresAtValue =
        registry.decodeField<DateTime>(
          _$StemGroupExpiresAtField,
          data['expires_at'],
        ) ??
        (throw StateError('Field expiresAt on StemGroup cannot be null.'));
    final DateTime? stemGroupCreatedAtValue = registry.decodeField<DateTime?>(
      _$StemGroupCreatedAtField,
      data['created_at'],
    );
    final DateTime? stemGroupUpdatedAtValue = registry.decodeField<DateTime?>(
      _$StemGroupUpdatedAtField,
      data['updated_at'],
    );
    final model = $StemGroup(
      id: stemGroupIdValue,
      namespace: stemGroupNamespaceValue,
      expected: stemGroupExpectedValue,
      meta: stemGroupMetaValue,
      expiresAt: stemGroupExpiresAtValue,
    );
    model._attachOrmRuntimeMetadata({
      'id': stemGroupIdValue,
      'namespace': stemGroupNamespaceValue,
      'expected': stemGroupExpectedValue,
      'meta': stemGroupMetaValue,
      'expires_at': stemGroupExpiresAtValue,
      if (data.containsKey('created_at')) 'created_at': stemGroupCreatedAtValue,
      if (data.containsKey('updated_at')) 'updated_at': stemGroupUpdatedAtValue,
    });
    return model;
  }
}

/// Insert DTO for [StemGroup].
///
/// Auto-increment/DB-generated fields are omitted by default.
class StemGroupInsertDto implements InsertDto<$StemGroup> {
  const StemGroupInsertDto({
    this.id,
    this.namespace,
    this.expected,
    this.meta,
    this.expiresAt,
  });
  final String? id;
  final String? namespace;
  final int? expected;
  final Map<String, Object?>? meta;
  final DateTime? expiresAt;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      if (namespace != null) 'namespace': namespace,
      if (expected != null) 'expected': expected,
      if (meta != null) 'meta': meta,
      if (expiresAt != null) 'expires_at': expiresAt,
    };
  }

  static const _StemGroupInsertDtoCopyWithSentinel _copyWithSentinel =
      _StemGroupInsertDtoCopyWithSentinel();
  StemGroupInsertDto copyWith({
    Object? id = _copyWithSentinel,
    Object? namespace = _copyWithSentinel,
    Object? expected = _copyWithSentinel,
    Object? meta = _copyWithSentinel,
    Object? expiresAt = _copyWithSentinel,
  }) {
    return StemGroupInsertDto(
      id: identical(id, _copyWithSentinel) ? this.id : id as String?,
      namespace: identical(namespace, _copyWithSentinel)
          ? this.namespace
          : namespace as String?,
      expected: identical(expected, _copyWithSentinel)
          ? this.expected
          : expected as int?,
      meta: identical(meta, _copyWithSentinel)
          ? this.meta
          : meta as Map<String, Object?>?,
      expiresAt: identical(expiresAt, _copyWithSentinel)
          ? this.expiresAt
          : expiresAt as DateTime?,
    );
  }
}

class _StemGroupInsertDtoCopyWithSentinel {
  const _StemGroupInsertDtoCopyWithSentinel();
}

/// Update DTO for [StemGroup].
///
/// All fields are optional; only provided entries are used in SET clauses.
class StemGroupUpdateDto implements UpdateDto<$StemGroup> {
  const StemGroupUpdateDto({
    this.id,
    this.namespace,
    this.expected,
    this.meta,
    this.expiresAt,
  });
  final String? id;
  final String? namespace;
  final int? expected;
  final Map<String, Object?>? meta;
  final DateTime? expiresAt;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      if (namespace != null) 'namespace': namespace,
      if (expected != null) 'expected': expected,
      if (meta != null) 'meta': meta,
      if (expiresAt != null) 'expires_at': expiresAt,
    };
  }

  static const _StemGroupUpdateDtoCopyWithSentinel _copyWithSentinel =
      _StemGroupUpdateDtoCopyWithSentinel();
  StemGroupUpdateDto copyWith({
    Object? id = _copyWithSentinel,
    Object? namespace = _copyWithSentinel,
    Object? expected = _copyWithSentinel,
    Object? meta = _copyWithSentinel,
    Object? expiresAt = _copyWithSentinel,
  }) {
    return StemGroupUpdateDto(
      id: identical(id, _copyWithSentinel) ? this.id : id as String?,
      namespace: identical(namespace, _copyWithSentinel)
          ? this.namespace
          : namespace as String?,
      expected: identical(expected, _copyWithSentinel)
          ? this.expected
          : expected as int?,
      meta: identical(meta, _copyWithSentinel)
          ? this.meta
          : meta as Map<String, Object?>?,
      expiresAt: identical(expiresAt, _copyWithSentinel)
          ? this.expiresAt
          : expiresAt as DateTime?,
    );
  }
}

class _StemGroupUpdateDtoCopyWithSentinel {
  const _StemGroupUpdateDtoCopyWithSentinel();
}

/// Partial projection for [StemGroup].
///
/// All fields are nullable; intended for subset SELECTs.
class StemGroupPartial implements PartialEntity<$StemGroup> {
  const StemGroupPartial({
    this.id,
    this.namespace,
    this.expected,
    this.meta,
    this.expiresAt,
  });

  /// Creates a partial from a database row map.
  ///
  /// The [row] keys should be column names (snake_case).
  /// Missing columns will result in null field values.
  factory StemGroupPartial.fromRow(Map<String, Object?> row) {
    return StemGroupPartial(
      id: row['id'] as String?,
      namespace: row['namespace'] as String?,
      expected: row['expected'] as int?,
      meta: row['meta'] as Map<String, Object?>?,
      expiresAt: row['expires_at'] as DateTime?,
    );
  }

  final String? id;
  final String? namespace;
  final int? expected;
  final Map<String, Object?>? meta;
  final DateTime? expiresAt;

  @override
  $StemGroup toEntity() {
    // Basic required-field check: non-nullable fields must be present.
    final String? idValue = id;
    if (idValue == null) {
      throw StateError('Missing required field: id');
    }
    final String? namespaceValue = namespace;
    if (namespaceValue == null) {
      throw StateError('Missing required field: namespace');
    }
    final int? expectedValue = expected;
    if (expectedValue == null) {
      throw StateError('Missing required field: expected');
    }
    final Map<String, Object?>? metaValue = meta;
    if (metaValue == null) {
      throw StateError('Missing required field: meta');
    }
    final DateTime? expiresAtValue = expiresAt;
    if (expiresAtValue == null) {
      throw StateError('Missing required field: expiresAt');
    }
    return $StemGroup(
      id: idValue,
      namespace: namespaceValue,
      expected: expectedValue,
      meta: metaValue,
      expiresAt: expiresAtValue,
    );
  }

  @override
  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      if (namespace != null) 'namespace': namespace,
      if (expected != null) 'expected': expected,
      if (meta != null) 'meta': meta,
      if (expiresAt != null) 'expires_at': expiresAt,
    };
  }

  static const _StemGroupPartialCopyWithSentinel _copyWithSentinel =
      _StemGroupPartialCopyWithSentinel();
  StemGroupPartial copyWith({
    Object? id = _copyWithSentinel,
    Object? namespace = _copyWithSentinel,
    Object? expected = _copyWithSentinel,
    Object? meta = _copyWithSentinel,
    Object? expiresAt = _copyWithSentinel,
  }) {
    return StemGroupPartial(
      id: identical(id, _copyWithSentinel) ? this.id : id as String?,
      namespace: identical(namespace, _copyWithSentinel)
          ? this.namespace
          : namespace as String?,
      expected: identical(expected, _copyWithSentinel)
          ? this.expected
          : expected as int?,
      meta: identical(meta, _copyWithSentinel)
          ? this.meta
          : meta as Map<String, Object?>?,
      expiresAt: identical(expiresAt, _copyWithSentinel)
          ? this.expiresAt
          : expiresAt as DateTime?,
    );
  }
}

class _StemGroupPartialCopyWithSentinel {
  const _StemGroupPartialCopyWithSentinel();
}

/// Generated tracked model class for [StemGroup].
///
/// This class extends the user-defined [StemGroup] model and adds
/// attribute tracking, change detection, and relationship management.
/// Instances of this class are returned by queries and repositories.
///
/// **Do not instantiate this class directly.** Use queries, repositories,
/// or model factories to create tracked model instances.
class $StemGroup extends StemGroup
    with ModelAttributes, TimestampsTZImpl
    implements OrmEntity {
  /// Internal constructor for [$StemGroup].
  $StemGroup({
    required String id,
    required String namespace,
    required int expected,
    required Map<String, Object?> meta,
    required DateTime expiresAt,
  }) : super(
         id: id,
         namespace: namespace,
         expected: expected,
         meta: meta,
         expiresAt: expiresAt,
       ) {
    _attachOrmRuntimeMetadata({
      'id': id,
      'namespace': namespace,
      'expected': expected,
      'meta': meta,
      'expires_at': expiresAt,
    });
  }

  /// Creates a tracked model instance from a user-defined model instance.
  factory $StemGroup.fromModel(StemGroup model) {
    return $StemGroup(
      id: model.id,
      namespace: model.namespace,
      expected: model.expected,
      meta: model.meta,
      expiresAt: model.expiresAt,
    );
  }

  $StemGroup copyWith({
    String? id,
    String? namespace,
    int? expected,
    Map<String, Object?>? meta,
    DateTime? expiresAt,
  }) {
    return $StemGroup(
      id: id ?? this.id,
      namespace: namespace ?? this.namespace,
      expected: expected ?? this.expected,
      meta: meta ?? this.meta,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  /// Builds a tracked model from a column/value map.
  static $StemGroup fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$StemGroupDefinition.fromMap(data, registry: registry);

  /// Converts this tracked model to a column/value map.
  Map<String, Object?> toMap({ValueCodecRegistry? registry}) =>
      _$StemGroupDefinition.toMap(this, registry: registry);

  /// Tracked getter for [id].
  @override
  String get id => getAttribute<String>('id') ?? super.id;

  /// Tracked setter for [id].
  set id(String value) => setAttribute('id', value);

  /// Tracked getter for [namespace].
  @override
  String get namespace => getAttribute<String>('namespace') ?? super.namespace;

  /// Tracked setter for [namespace].
  set namespace(String value) => setAttribute('namespace', value);

  /// Tracked getter for [expected].
  @override
  int get expected => getAttribute<int>('expected') ?? super.expected;

  /// Tracked setter for [expected].
  set expected(int value) => setAttribute('expected', value);

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
    attachModelDefinition(_$StemGroupDefinition);
  }

  @override
  List<StemGroupResult> get results {
    if (relationLoaded('results')) {
      return getRelationList<StemGroupResult>('results');
    }
    return super.results;
  }
}

extension StemGroupRelationQueries on StemGroup {
  Query<StemGroupResult> resultsQuery() {
    return Model.query<StemGroupResult>().where(
      'group_id',
      getAttribute("null"),
    );
  }
}

class _StemGroupCopyWithSentinel {
  const _StemGroupCopyWithSentinel();
}

extension StemGroupOrmExtension on StemGroup {
  static const _StemGroupCopyWithSentinel _copyWithSentinel =
      _StemGroupCopyWithSentinel();
  StemGroup copyWith({
    Object? id = _copyWithSentinel,
    Object? namespace = _copyWithSentinel,
    Object? expected = _copyWithSentinel,
    Object? meta = _copyWithSentinel,
    Object? expiresAt = _copyWithSentinel,
    Object? results = _copyWithSentinel,
  }) {
    return StemGroup(
      id: identical(id, _copyWithSentinel) ? this.id : id as String,
      namespace: identical(namespace, _copyWithSentinel)
          ? this.namespace
          : namespace as String,
      expected: identical(expected, _copyWithSentinel)
          ? this.expected
          : expected as int,
      meta: identical(meta, _copyWithSentinel)
          ? this.meta
          : meta as Map<String, Object?>,
      expiresAt: identical(expiresAt, _copyWithSentinel)
          ? this.expiresAt
          : expiresAt as DateTime,
      results: identical(results, _copyWithSentinel)
          ? this.results
          : results as List<StemGroupResult>,
    );
  }

  /// Converts this model to a column/value map.
  Map<String, Object?> toMap({ValueCodecRegistry? registry}) =>
      _$StemGroupDefinition.toMap(this, registry: registry);

  /// Builds a model from a column/value map.
  static StemGroup fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$StemGroupDefinition.fromMap(data, registry: registry);

  /// The Type of the generated ORM-managed model class.
  /// Use this when you need to specify the tracked model type explicitly,
  /// for example in generic type parameters.
  static Type get trackedType => $StemGroup;

  /// Converts this immutable model to a tracked ORM-managed model.
  /// The tracked model supports attribute tracking, change detection,
  /// and persistence operations like save() and touch().
  $StemGroup toTracked() {
    return $StemGroup.fromModel(this);
  }
}

extension StemGroupPredicateFields on PredicateBuilder<StemGroup> {
  PredicateField<StemGroup, String> get id =>
      PredicateField<StemGroup, String>(this, 'id');
  PredicateField<StemGroup, String> get namespace =>
      PredicateField<StemGroup, String>(this, 'namespace');
  PredicateField<StemGroup, int> get expected =>
      PredicateField<StemGroup, int>(this, 'expected');
  PredicateField<StemGroup, Map<String, Object?>> get meta =>
      PredicateField<StemGroup, Map<String, Object?>>(this, 'meta');
  PredicateField<StemGroup, DateTime> get expiresAt =>
      PredicateField<StemGroup, DateTime>(this, 'expiresAt');
}

extension StemGroupTypedRelations on Query<StemGroup> {
  Query<StemGroup> withResults([
    PredicateCallback<StemGroupResult>? constraint,
  ]) => withRelationTyped('results', constraint);
  Query<StemGroup> whereHasResults([
    PredicateCallback<StemGroupResult>? constraint,
  ]) => whereHasTyped('results', constraint);
  Query<StemGroup> orWhereHasResults([
    PredicateCallback<StemGroupResult>? constraint,
  ]) => orWhereHasTyped('results', constraint);
}

void registerStemGroupEventHandlers(EventBus bus) {
  // No event handlers registered for StemGroup.
}
