import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

abstract final class SchemaVersions {
  static const catalog = 1;
  static const registry = 2;
  static const workspace = 2;
}

abstract final class MigrationRunner {
  static Future<void> migrate(
    DatabaseExecutor database, {
    required String scope,
    required int fromVersion,
    required int toVersion,
  }) async {
    for (var version = fromVersion + 1; version <= toVersion; version++) {
      final fileName = switch ((scope, version)) {
        ('catalog', 1) || ('registry', 1) || ('workspace', 1) =>
          '001_initial.sql',
        ('registry', 2) || ('workspace', 2) => '002_revision.sql',
        _ => throw StateError('No migration registered for $scope v$version'),
      };
      final sql = await rootBundle.loadString(
        'assets/migrations/$scope/$fileName',
      );
      for (final statement in _splitStatements(sql)) {
        await database.execute(statement);
      }
    }
  }

  static List<String> _splitStatements(String sql) => sql
      .split(';')
      .map((statement) => statement.trim())
      .where((statement) => statement.isNotEmpty)
      .toList(growable: false);
}
