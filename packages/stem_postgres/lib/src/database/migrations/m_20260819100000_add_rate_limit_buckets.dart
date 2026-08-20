import 'package:ormed/migrations.dart';

/// Adds durable token-bucket state for the PostgreSQL rate limiter.
class AddRateLimitBuckets extends Migration {
  /// Creates the migration.
  const AddRateLimitBuckets();

  @override
  void up(SchemaBuilder schema) {
    schema.create('stem_rate_limit_buckets', (table) {
      table
        ..text('namespace')
        ..text('rate_key')
        ..bigInteger('capacity')
        ..bigInteger('interval_ms')
        ..bigInteger('available_micros')
        ..bigInteger('updated_at_ms')
        ..timestampsTz()
        ..primary(
          ['namespace', 'rate_key'],
          name: 'stem_rate_limit_buckets_primary',
        )
        ..index(
          ['namespace', 'updated_at_ms'],
          name: 'stem_rate_limit_buckets_updated_idx',
        );
    });
  }

  @override
  void down(SchemaBuilder schema) {
    schema.drop('stem_rate_limit_buckets', ifExists: true);
  }
}
