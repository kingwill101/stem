// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'stem_lock.dart';

// **************************************************************************
// OrmModelGenerator
// **************************************************************************

const FieldDefinition _$StemLockKeyField = FieldDefinition(
  name: 'key',
  columnName: 'key',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: true,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemLockOwnerField = FieldDefinition(
  name: 'owner',
  columnName: 'owner',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemLockExpiresAtField = FieldDefinition(
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

const FieldDefinition _$StemLockCreatedAtField = FieldDefinition(
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

Map<String, Object?> _encodeStemLockUntracked(
  Object model,
  ValueCodecRegistry registry,
) {
  final m = model as StemLock;
  return <String, Object?>{
    'key': registry.encodeField(_$StemLockKeyField, m.key),
    'owner': registry.encodeField(_$StemLockOwnerField, m.owner),
    'expires_at': registry.encodeField(_$StemLockExpiresAtField, m.expiresAt),
    'created_at': registry.encodeField(_$StemLockCreatedAtField, m.createdAt),
  };
}

final ModelDefinition<$StemLock> _$StemLockDefinition = ModelDefinition(
  modelName: 'StemLock',
  tableName: 'stem_locks',
  fields: const [
    _$StemLockKeyField,
    _$StemLockOwnerField,
    _$StemLockExpiresAtField,
    _$StemLockCreatedAtField,
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
  untrackedToMap: _encodeStemLockUntracked,
  codec: _$StemLockCodec(),
);

extension StemLockOrmDefinition on StemLock {
  static ModelDefinition<$StemLock> get definition => _$StemLockDefinition;
}

class StemLocks {
  const StemLocks._();

  /// Starts building a query for [$StemLock].
  ///
  /// {@macro ormed.query}
  static Query<$StemLock> query([String? connection]) =>
      Model.query<$StemLock>(connection: connection);

  static Future<$StemLock?> find(Object id, {String? connection}) =>
      Model.find<$StemLock>(id, connection: connection);

  static Future<$StemLock> findOrFail(Object id, {String? connection}) =>
      Model.findOrFail<$StemLock>(id, connection: connection);

  static Future<List<$StemLock>> all({String? connection}) =>
      Model.all<$StemLock>(connection: connection);

  static Future<int> count({String? connection}) =>
      Model.count<$StemLock>(connection: connection);

  static Future<bool> anyExist({String? connection}) =>
      Model.anyExist<$StemLock>(connection: connection);

  static Query<$StemLock> where(
    String column,
    String operator,
    dynamic value, {
    String? connection,
  }) => Model.where<$StemLock>(column, operator, value, connection: connection);

  static Query<$StemLock> whereIn(
    String column,
    List<dynamic> values, {
    String? connection,
  }) => Model.whereIn<$StemLock>(column, values, connection: connection);

  static Query<$StemLock> orderBy(
    String column, {
    String direction = "asc",
    String? connection,
  }) => Model.orderBy<$StemLock>(
    column,
    direction: direction,
    connection: connection,
  );

  static Query<$StemLock> limit(int count, {String? connection}) =>
      Model.limit<$StemLock>(count, connection: connection);

  /// Creates a [Repository] for [$StemLock].
  ///
  /// {@macro ormed.repository}
  static Repository<$StemLock> repo([String? connection]) =>
      Model.repository<$StemLock>(connection: connection);
}

class StemLockModelFactory {
  const StemLockModelFactory._();

  static ModelDefinition<$StemLock> get definition => _$StemLockDefinition;

  static ModelCodec<$StemLock> get codec => definition.codec;

  static StemLock fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => definition.fromMap(data, registry: registry);

  static Map<String, Object?> toMap(
    StemLock model, {
    ValueCodecRegistry? registry,
  }) => definition.toMap(model.toTracked(), registry: registry);

  static void registerWith(ModelRegistry registry) =>
      registry.register(definition);

  static ModelFactoryConnection<StemLock> withConnection(
    QueryContext context,
  ) => ModelFactoryConnection<StemLock>(
    definition: definition,
    context: context,
  );

  static ModelFactoryBuilder<StemLock> factory({
    GeneratorProvider? generatorProvider,
  }) => ModelFactoryBuilder<StemLock>(
    definition: definition,
    generatorProvider: generatorProvider,
  );
}

class _$StemLockCodec extends ModelCodec<$StemLock> {
  const _$StemLockCodec();
  @override
  Map<String, Object?> encode($StemLock model, ValueCodecRegistry registry) {
    return <String, Object?>{
      'key': registry.encodeField(_$StemLockKeyField, model.key),
      'owner': registry.encodeField(_$StemLockOwnerField, model.owner),
      'expires_at': registry.encodeField(
        _$StemLockExpiresAtField,
        model.expiresAt,
      ),
      'created_at': registry.encodeField(
        _$StemLockCreatedAtField,
        model.createdAt,
      ),
    };
  }

  @override
  $StemLock decode(Map<String, Object?> data, ValueCodecRegistry registry) {
    final String stemLockKeyValue =
        registry.decodeField<String>(_$StemLockKeyField, data['key']) ??
        (throw StateError('Field key on StemLock cannot be null.'));
    final String stemLockOwnerValue =
        registry.decodeField<String>(_$StemLockOwnerField, data['owner']) ??
        (throw StateError('Field owner on StemLock cannot be null.'));
    final DateTime stemLockExpiresAtValue =
        registry.decodeField<DateTime>(
          _$StemLockExpiresAtField,
          data['expires_at'],
        ) ??
        (throw StateError('Field expiresAt on StemLock cannot be null.'));
    final DateTime stemLockCreatedAtValue =
        registry.decodeField<DateTime>(
          _$StemLockCreatedAtField,
          data['created_at'],
        ) ??
        (throw StateError('Field createdAt on StemLock cannot be null.'));
    final model = $StemLock(
      key: stemLockKeyValue,
      owner: stemLockOwnerValue,
      expiresAt: stemLockExpiresAtValue,
      createdAt: stemLockCreatedAtValue,
    );
    model._attachOrmRuntimeMetadata({
      'key': stemLockKeyValue,
      'owner': stemLockOwnerValue,
      'expires_at': stemLockExpiresAtValue,
      'created_at': stemLockCreatedAtValue,
    });
    return model;
  }
}

/// Insert DTO for [StemLock].
///
/// Auto-increment/DB-generated fields are omitted by default.
class StemLockInsertDto implements InsertDto<$StemLock> {
  const StemLockInsertDto({
    this.key,
    this.owner,
    this.expiresAt,
    this.createdAt,
  });
  final String? key;
  final String? owner;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (key != null) 'key': key,
      if (owner != null) 'owner': owner,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (createdAt != null) 'created_at': createdAt,
    };
  }

  static const _StemLockInsertDtoCopyWithSentinel _copyWithSentinel =
      _StemLockInsertDtoCopyWithSentinel();
  StemLockInsertDto copyWith({
    Object? key = _copyWithSentinel,
    Object? owner = _copyWithSentinel,
    Object? expiresAt = _copyWithSentinel,
    Object? createdAt = _copyWithSentinel,
  }) {
    return StemLockInsertDto(
      key: identical(key, _copyWithSentinel) ? this.key : key as String?,
      owner: identical(owner, _copyWithSentinel)
          ? this.owner
          : owner as String?,
      expiresAt: identical(expiresAt, _copyWithSentinel)
          ? this.expiresAt
          : expiresAt as DateTime?,
      createdAt: identical(createdAt, _copyWithSentinel)
          ? this.createdAt
          : createdAt as DateTime?,
    );
  }
}

class _StemLockInsertDtoCopyWithSentinel {
  const _StemLockInsertDtoCopyWithSentinel();
}

/// Update DTO for [StemLock].
///
/// All fields are optional; only provided entries are used in SET clauses.
class StemLockUpdateDto implements UpdateDto<$StemLock> {
  const StemLockUpdateDto({
    this.key,
    this.owner,
    this.expiresAt,
    this.createdAt,
  });
  final String? key;
  final String? owner;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (key != null) 'key': key,
      if (owner != null) 'owner': owner,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (createdAt != null) 'created_at': createdAt,
    };
  }

  static const _StemLockUpdateDtoCopyWithSentinel _copyWithSentinel =
      _StemLockUpdateDtoCopyWithSentinel();
  StemLockUpdateDto copyWith({
    Object? key = _copyWithSentinel,
    Object? owner = _copyWithSentinel,
    Object? expiresAt = _copyWithSentinel,
    Object? createdAt = _copyWithSentinel,
  }) {
    return StemLockUpdateDto(
      key: identical(key, _copyWithSentinel) ? this.key : key as String?,
      owner: identical(owner, _copyWithSentinel)
          ? this.owner
          : owner as String?,
      expiresAt: identical(expiresAt, _copyWithSentinel)
          ? this.expiresAt
          : expiresAt as DateTime?,
      createdAt: identical(createdAt, _copyWithSentinel)
          ? this.createdAt
          : createdAt as DateTime?,
    );
  }
}

class _StemLockUpdateDtoCopyWithSentinel {
  const _StemLockUpdateDtoCopyWithSentinel();
}

/// Partial projection for [StemLock].
///
/// All fields are nullable; intended for subset SELECTs.
class StemLockPartial implements PartialEntity<$StemLock> {
  const StemLockPartial({this.key, this.owner, this.expiresAt, this.createdAt});

  /// Creates a partial from a database row map.
  ///
  /// The [row] keys should be column names (snake_case).
  /// Missing columns will result in null field values.
  factory StemLockPartial.fromRow(Map<String, Object?> row) {
    return StemLockPartial(
      key: row['key'] as String?,
      owner: row['owner'] as String?,
      expiresAt: row['expires_at'] as DateTime?,
      createdAt: row['created_at'] as DateTime?,
    );
  }

  final String? key;
  final String? owner;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  @override
  $StemLock toEntity() {
    // Basic required-field check: non-nullable fields must be present.
    final String? keyValue = key;
    if (keyValue == null) {
      throw StateError('Missing required field: key');
    }
    final String? ownerValue = owner;
    if (ownerValue == null) {
      throw StateError('Missing required field: owner');
    }
    final DateTime? expiresAtValue = expiresAt;
    if (expiresAtValue == null) {
      throw StateError('Missing required field: expiresAt');
    }
    final DateTime? createdAtValue = createdAt;
    if (createdAtValue == null) {
      throw StateError('Missing required field: createdAt');
    }
    return $StemLock(
      key: keyValue,
      owner: ownerValue,
      expiresAt: expiresAtValue,
      createdAt: createdAtValue,
    );
  }

  @override
  Map<String, Object?> toMap() {
    return {
      if (key != null) 'key': key,
      if (owner != null) 'owner': owner,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (createdAt != null) 'created_at': createdAt,
    };
  }

  static const _StemLockPartialCopyWithSentinel _copyWithSentinel =
      _StemLockPartialCopyWithSentinel();
  StemLockPartial copyWith({
    Object? key = _copyWithSentinel,
    Object? owner = _copyWithSentinel,
    Object? expiresAt = _copyWithSentinel,
    Object? createdAt = _copyWithSentinel,
  }) {
    return StemLockPartial(
      key: identical(key, _copyWithSentinel) ? this.key : key as String?,
      owner: identical(owner, _copyWithSentinel)
          ? this.owner
          : owner as String?,
      expiresAt: identical(expiresAt, _copyWithSentinel)
          ? this.expiresAt
          : expiresAt as DateTime?,
      createdAt: identical(createdAt, _copyWithSentinel)
          ? this.createdAt
          : createdAt as DateTime?,
    );
  }
}

class _StemLockPartialCopyWithSentinel {
  const _StemLockPartialCopyWithSentinel();
}

/// Generated tracked model class for [StemLock].
///
/// This class extends the user-defined [StemLock] model and adds
/// attribute tracking, change detection, and relationship management.
/// Instances of this class are returned by queries and repositories.
///
/// **Do not instantiate this class directly.** Use queries, repositories,
/// or model factories to create tracked model instances.
class $StemLock extends StemLock with ModelAttributes implements OrmEntity {
  /// Internal constructor for [$StemLock].
  $StemLock({
    required String key,
    required String owner,
    required DateTime expiresAt,
    required DateTime createdAt,
  }) : super.new(
         key: key,
         owner: owner,
         expiresAt: expiresAt,
         createdAt: createdAt,
       ) {
    _attachOrmRuntimeMetadata({
      'key': key,
      'owner': owner,
      'expires_at': expiresAt,
      'created_at': createdAt,
    });
  }

  /// Creates a tracked model instance from a user-defined model instance.
  factory $StemLock.fromModel(StemLock model) {
    return $StemLock(
      key: model.key,
      owner: model.owner,
      expiresAt: model.expiresAt,
      createdAt: model.createdAt,
    );
  }

  $StemLock copyWith({
    String? key,
    String? owner,
    DateTime? expiresAt,
    DateTime? createdAt,
  }) {
    return $StemLock(
      key: key ?? this.key,
      owner: owner ?? this.owner,
      expiresAt: expiresAt ?? this.expiresAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Tracked getter for [key].
  @override
  String get key => getAttribute<String>('key') ?? super.key;

  /// Tracked setter for [key].
  set key(String value) => setAttribute('key', value);

  /// Tracked getter for [owner].
  @override
  String get owner => getAttribute<String>('owner') ?? super.owner;

  /// Tracked setter for [owner].
  set owner(String value) => setAttribute('owner', value);

  /// Tracked getter for [expiresAt].
  @override
  DateTime get expiresAt =>
      getAttribute<DateTime>('expires_at') ?? super.expiresAt;

  /// Tracked setter for [expiresAt].
  set expiresAt(DateTime value) => setAttribute('expires_at', value);

  /// Tracked getter for [createdAt].
  @override
  DateTime get createdAt =>
      getAttribute<DateTime>('created_at') ?? super.createdAt;

  /// Tracked setter for [createdAt].
  set createdAt(DateTime value) => setAttribute('created_at', value);

  void _attachOrmRuntimeMetadata(Map<String, Object?> values) {
    replaceAttributes(values);
    attachModelDefinition(_$StemLockDefinition);
  }
}

extension StemLockOrmExtension on StemLock {
  /// The Type of the generated ORM-managed model class.
  /// Use this when you need to specify the tracked model type explicitly,
  /// for example in generic type parameters.
  static Type get trackedType => $StemLock;

  /// Converts this immutable model to a tracked ORM-managed model.
  /// The tracked model supports attribute tracking, change detection,
  /// and persistence operations like save() and touch().
  $StemLock toTracked() {
    return $StemLock.fromModel(this);
  }
}

void registerStemLockEventHandlers(EventBus bus) {
  // No event handlers registered for StemLock.
}
