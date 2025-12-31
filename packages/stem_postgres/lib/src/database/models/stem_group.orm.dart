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
);

const FieldDefinition _$StemGroupExpectedField = FieldDefinition(
  name: 'expected',
  columnName: 'expected',
  dartType: 'int',
  resolvedType: 'int',
  isNullable: false,
);

const FieldDefinition _$StemGroupMetaField = FieldDefinition(
  name: 'meta',
  columnName: 'meta',
  dartType: 'Map<String, Object?>',
  resolvedType: 'Map<String, Object?>',
  isNullable: false,
  codecType: 'json',
);

const FieldDefinition _$StemGroupExpiresAtField = FieldDefinition(
  name: 'expiresAt',
  columnName: 'expires_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime',
  isNullable: false,
);

const FieldDefinition _$StemGroupCreatedAtField = FieldDefinition(
  name: 'createdAt',
  columnName: 'created_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime?',
  isNullable: true,
);

const FieldDefinition _$StemGroupUpdatedAtField = FieldDefinition(
  name: 'updatedAt',
  columnName: 'updated_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime?',
  isNullable: true,
);

Map<String, Object?> _encodeStemGroupUntracked(
  Object model,
  ValueCodecRegistry registry,
) {
  final m = model as StemGroup;
  return <String, Object?>{
    'id': registry.encodeField(_$StemGroupIdField, m.id),
    'expected': registry.encodeField(_$StemGroupExpectedField, m.expected),
    'meta': registry.encodeField(_$StemGroupMetaField, m.meta),
    'expires_at': registry.encodeField(_$StemGroupExpiresAtField, m.expiresAt),
  };
}

const ModelDefinition<$StemGroup> _$StemGroupDefinition = ModelDefinition(
  modelName: 'StemGroup',
  tableName: 'stem_groups',
  fields: [
    _$StemGroupIdField,
    _$StemGroupExpectedField,
    _$StemGroupMetaField,
    _$StemGroupExpiresAtField,
    _$StemGroupCreatedAtField,
    _$StemGroupUpdatedAtField,
  ],
  softDeleteColumn: 'deleted_at',
  metadata: ModelAttributesMetadata(
    fieldOverrides: {'meta': FieldAttributeMetadata(cast: 'json')},
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
    String direction = 'asc',
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
    final stemGroupIdValue =
        registry.decodeField<String>(_$StemGroupIdField, data['id']) ??
        (throw StateError('Field id on StemGroup cannot be null.'));
    final stemGroupExpectedValue =
        registry.decodeField<int>(_$StemGroupExpectedField, data['expected']) ??
        (throw StateError('Field expected on StemGroup cannot be null.'));
    final stemGroupMetaValue =
        registry.decodeField<Map<String, Object?>>(
          _$StemGroupMetaField,
          data['meta'],
        ) ??
        (throw StateError('Field meta on StemGroup cannot be null.'));
    final stemGroupExpiresAtValue =
        registry.decodeField<DateTime>(
          _$StemGroupExpiresAtField,
          data['expires_at'],
        ) ??
        (throw StateError('Field expiresAt on StemGroup cannot be null.'));
    final stemGroupCreatedAtValue = registry.decodeField<DateTime?>(
      _$StemGroupCreatedAtField,
      data['created_at'],
    );
    final stemGroupUpdatedAtValue = registry.decodeField<DateTime?>(
      _$StemGroupUpdatedAtField,
      data['updated_at'],
    );
    final model = $StemGroup(
      id: stemGroupIdValue,
      expected: stemGroupExpectedValue,
      meta: stemGroupMetaValue,
      expiresAt: stemGroupExpiresAtValue,
    );
    model._attachOrmRuntimeMetadata({
      'id': stemGroupIdValue,
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
  const StemGroupInsertDto({this.id, this.expected, this.meta, this.expiresAt});
  final String? id;
  final int? expected;
  final Map<String, Object?>? meta;
  final DateTime? expiresAt;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      if (expected != null) 'expected': expected,
      if (meta != null) 'meta': meta,
      if (expiresAt != null) 'expires_at': expiresAt,
    };
  }

  static const _StemGroupInsertDtoCopyWithSentinel _copyWithSentinel =
      _StemGroupInsertDtoCopyWithSentinel();
  StemGroupInsertDto copyWith({
    Object? id = _copyWithSentinel,
    Object? expected = _copyWithSentinel,
    Object? meta = _copyWithSentinel,
    Object? expiresAt = _copyWithSentinel,
  }) {
    return StemGroupInsertDto(
      id: identical(id, _copyWithSentinel) ? this.id : id as String?,
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
  const StemGroupUpdateDto({this.id, this.expected, this.meta, this.expiresAt});
  final String? id;
  final int? expected;
  final Map<String, Object?>? meta;
  final DateTime? expiresAt;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      if (expected != null) 'expected': expected,
      if (meta != null) 'meta': meta,
      if (expiresAt != null) 'expires_at': expiresAt,
    };
  }

  static const _StemGroupUpdateDtoCopyWithSentinel _copyWithSentinel =
      _StemGroupUpdateDtoCopyWithSentinel();
  StemGroupUpdateDto copyWith({
    Object? id = _copyWithSentinel,
    Object? expected = _copyWithSentinel,
    Object? meta = _copyWithSentinel,
    Object? expiresAt = _copyWithSentinel,
  }) {
    return StemGroupUpdateDto(
      id: identical(id, _copyWithSentinel) ? this.id : id as String?,
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
  const StemGroupPartial({this.id, this.expected, this.meta, this.expiresAt});

  /// Creates a partial from a database row map.
  ///
  /// The [row] keys should be column names (snake_case).
  /// Missing columns will result in null field values.
  factory StemGroupPartial.fromRow(Map<String, Object?> row) {
    return StemGroupPartial(
      id: row['id'] as String?,
      expected: row['expected'] as int?,
      meta: row['meta'] as Map<String, Object?>?,
      expiresAt: row['expires_at'] as DateTime?,
    );
  }

  final String? id;
  final int? expected;
  final Map<String, Object?>? meta;
  final DateTime? expiresAt;

  @override
  $StemGroup toEntity() {
    // Basic required-field check: non-nullable fields must be present.
    final idValue = id;
    if (idValue == null) {
      throw StateError('Missing required field: id');
    }
    final expectedValue = expected;
    if (expectedValue == null) {
      throw StateError('Missing required field: expected');
    }
    final metaValue = meta;
    if (metaValue == null) {
      throw StateError('Missing required field: meta');
    }
    final expiresAtValue = expiresAt;
    if (expiresAtValue == null) {
      throw StateError('Missing required field: expiresAt');
    }
    return $StemGroup(
      id: idValue,
      expected: expectedValue,
      meta: metaValue,
      expiresAt: expiresAtValue,
    );
  }

  @override
  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      if (expected != null) 'expected': expected,
      if (meta != null) 'meta': meta,
      if (expiresAt != null) 'expires_at': expiresAt,
    };
  }

  static const _StemGroupPartialCopyWithSentinel _copyWithSentinel =
      _StemGroupPartialCopyWithSentinel();
  StemGroupPartial copyWith({
    Object? id = _copyWithSentinel,
    Object? expected = _copyWithSentinel,
    Object? meta = _copyWithSentinel,
    Object? expiresAt = _copyWithSentinel,
  }) {
    return StemGroupPartial(
      id: identical(id, _copyWithSentinel) ? this.id : id as String?,
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
    required int expected,
    required Map<String, Object?> meta,
    required DateTime expiresAt,
  }) : super.new(id: id, expected: expected, meta: meta, expiresAt: expiresAt) {
    _attachOrmRuntimeMetadata({
      'id': id,
      'expected': expected,
      'meta': meta,
      'expires_at': expiresAt,
    });
  }

  /// Creates a tracked model instance from a user-defined model instance.
  factory $StemGroup.fromModel(StemGroup model) {
    return $StemGroup(
      id: model.id,
      expected: model.expected,
      meta: model.meta,
      expiresAt: model.expiresAt,
    );
  }

  $StemGroup copyWith({
    String? id,
    int? expected,
    Map<String, Object?>? meta,
    DateTime? expiresAt,
  }) {
    return $StemGroup(
      id: id ?? this.id,
      expected: expected ?? this.expected,
      meta: meta ?? this.meta,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  /// Tracked getter for [id].
  @override
  String get id => getAttribute<String>('id') ?? super.id;

  /// Tracked setter for [id].
  set id(String value) => setAttribute('id', value);

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
}

extension StemGroupOrmExtension on StemGroup {
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

void registerStemGroupEventHandlers(EventBus bus) {
  // No event handlers registered for StemGroup.
}
