import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/models.dart';
import 'id_generator.dart';
import 'migrations.dart';

/// Owns the office catalog, shared people file, and independently stored workspaces.
/// Only one workspace connection is open at a time. The active workspace attaches
/// the shared identity file so identity + client engagement writes can be atomic.
class OfficeDatabase {
  OfficeDatabase._({
    required this.rootDirectory,
    required DatabaseFactory factory,
    required Database catalog,
    required String peoplePath,
    required WorkspaceInfo activeWorkspace,
    required Database activeConnection,
  })  : _factory = factory,
        _catalog = catalog,
        _peoplePath = peoplePath,
        _activeWorkspace = activeWorkspace,
        _activeConnection = activeConnection;

  final Directory rootDirectory;
  final DatabaseFactory _factory;
  final Database _catalog;
  final String _peoplePath;
  Database _activeConnection;
  WorkspaceInfo _activeWorkspace;

  Database get connection => _activeConnection;
  WorkspaceInfo get activeWorkspace => _activeWorkspace;

  static Future<OfficeDatabase> open({
    required Directory rootDirectory,
    required DatabaseFactory factory,
  }) async {
    await rootDirectory.create(recursive: true);
    final workspacesDirectory = Directory(p.join(rootDirectory.path, 'workspaces'));
    await workspacesDirectory.create(recursive: true);

    final peoplePath = p.join(rootDirectory.path, 'people_registry.sqlite');
    final registry = await factory.openDatabase(
      peoplePath,
      options: OpenDatabaseOptions(
        version: SchemaVersions.registry,
        onConfigure: _configure,
        onCreate: (db, version) => MigrationRunner.migrate(
          db,
          scope: 'registry',
          fromVersion: 0,
          toVersion: version,
        ),
        onUpgrade: (db, oldVersion, newVersion) => MigrationRunner.migrate(
          db,
          scope: 'registry',
          fromVersion: oldVersion,
          toVersion: newVersion,
        ),
      ),
    );
    await registry.close();

    final catalog = await factory.openDatabase(
      p.join(rootDirectory.path, 'catalog.sqlite'),
      options: OpenDatabaseOptions(
        version: SchemaVersions.catalog,
        onConfigure: _configure,
        onCreate: (db, version) => MigrationRunner.migrate(
          db,
          scope: 'catalog',
          fromVersion: 0,
          toVersion: version,
        ),
      ),
    );

    try {
      var workspaces = await _listWorkspaces(catalog);
      if (workspaces.isEmpty) {
        final first = WorkspaceInfo(
          id: IdGenerator.uuidV4(),
          name: 'القاعدة الرئيسية',
          fileName: 'workspace_${IdGenerator.uuidV4()}.sqlite',
          createdAtUtc: _nowUtc(),
        );
        await catalog.transaction((txn) async {
          await txn.insert('workspaces', _workspaceToMap(first));
          await txn.insert('catalog_settings', {
            'setting_key': 'active_workspace_id',
            'setting_value': first.id,
          });
        });
        workspaces = <WorkspaceInfo>[first];
      }

      final settings = await catalog.query(
        'catalog_settings',
        where: 'setting_key = ?',
        whereArgs: const ['active_workspace_id'],
        limit: 1,
      );
      final savedId = settings.isEmpty
          ? null
          : settings.single['setting_value'] as String?;
      final active = workspaces.firstWhere(
        (workspace) => workspace.id == savedId,
        orElse: () => workspaces.first,
      );

      final activeConnection = await _openWorkspaceConnection(
        factory: factory,
        workspace: active,
        workspacesDirectory: workspacesDirectory,
        peoplePath: peoplePath,
      );
      if (savedId != active.id) {
        await catalog.insert(
          'catalog_settings',
          {'setting_key': 'active_workspace_id', 'setting_value': active.id},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      return OfficeDatabase._(
        rootDirectory: rootDirectory,
        factory: factory,
        catalog: catalog,
        peoplePath: peoplePath,
        activeWorkspace: active,
        activeConnection: activeConnection,
      );
    } catch (_) {
      await catalog.close();
      rethrow;
    }
  }

  Future<List<WorkspaceInfo>> listWorkspaces() => _listWorkspaces(_catalog);

  Future<void> switchWorkspace(String workspaceId) async {
    final workspaces = await listWorkspaces();
    final next = workspaces.where((item) => item.id == workspaceId).firstOrNull;
    if (next == null) throw const RecordNotFoundExceptionForWorkspace();
    if (next.id == _activeWorkspace.id) return;

    final previous = _activeWorkspace;
    await _activeConnection.close();
    Database? newConnection;
    try {
      newConnection = await _openWorkspaceConnection(
        factory: _factory,
        workspace: next,
        workspacesDirectory: Directory(p.join(rootDirectory.path, 'workspaces')),
        peoplePath: _peoplePath,
      );
      await _catalog.insert(
        'catalog_settings',
        {'setting_key': 'active_workspace_id', 'setting_value': next.id},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      _activeWorkspace = next;
      _activeConnection = newConnection;
    } catch (_) {
      if (newConnection != null) await newConnection.close();
      _activeConnection = await _openWorkspaceConnection(
        factory: _factory,
        workspace: previous,
        workspacesDirectory: Directory(p.join(rootDirectory.path, 'workspaces')),
        peoplePath: _peoplePath,
      );
      rethrow;
    }
  }

  Future<WorkspaceInfo> createWorkspace(String name) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty || cleanName.length > 80) {
      throw const InvalidWorkspaceNameException();
    }

    final workspace = WorkspaceInfo(
      id: IdGenerator.uuidV4(),
      name: cleanName,
      fileName: 'workspace_${IdGenerator.uuidV4()}.sqlite',
      createdAtUtc: _nowUtc(),
    );
    final workspacesDirectory = Directory(p.join(rootDirectory.path, 'workspaces'));
    final connection = await _openWorkspaceConnection(
      factory: _factory,
      workspace: workspace,
      workspacesDirectory: workspacesDirectory,
      peoplePath: _peoplePath,
    );
    await connection.close();

    await _catalog.transaction((txn) async {
      await txn.insert('workspaces', _workspaceToMap(workspace));
    });
    await switchWorkspace(workspace.id);
    return workspace;
  }

  Future<void> close() async {
    await _activeConnection.close();
    await _catalog.close();
  }

  static Future<Database> _openWorkspaceConnection({
    required DatabaseFactory factory,
    required WorkspaceInfo workspace,
    required Directory workspacesDirectory,
    required String peoplePath,
  }) async {
    if (p.basename(workspace.fileName) != workspace.fileName ||
        !workspace.fileName.endsWith('.sqlite')) {
      throw const RecordNotFoundExceptionForWorkspace();
    }
    return factory.openDatabase(
      p.join(workspacesDirectory.path, workspace.fileName),
      options: OpenDatabaseOptions(
        version: SchemaVersions.workspace,
        onConfigure: (db) async {
          await _configure(db);
          await db.execute(
            'ATTACH DATABASE ? AS office_registry',
            <Object?>[peoplePath],
          );
          await db.execute('PRAGMA office_registry.journal_mode = DELETE');
          await db.execute('PRAGMA office_registry.synchronous = FULL');
        },
        onCreate: (db, version) => MigrationRunner.migrate(
          db,
          scope: 'workspace',
          fromVersion: 0,
          toVersion: version,
        ),
        onUpgrade: (db, oldVersion, newVersion) => MigrationRunner.migrate(
          db,
          scope: 'workspace',
          fromVersion: oldVersion,
          toVersion: newVersion,
        ),
      ),
    );
  }

  static Future<void> _configure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
    await db.execute('PRAGMA busy_timeout = 5000');
    await db.execute('PRAGMA journal_mode = DELETE');
    await db.execute('PRAGMA synchronous = FULL');
  }

  static Future<List<WorkspaceInfo>> _listWorkspaces(Database catalog) async {
    final rows = await catalog.query('workspaces', orderBy: 'name COLLATE NOCASE');
    return rows.map(WorkspaceInfo.fromMap).toList(growable: false);
  }

  static Map<String, Object?> _workspaceToMap(WorkspaceInfo workspace) => {
        'id': workspace.id,
        'name': workspace.name,
        'file_name': workspace.fileName,
        'created_at_utc': workspace.createdAtUtc,
      };

  static String _nowUtc() => DateTime.now().toUtc().toIso8601String();
}

class RecordNotFoundExceptionForWorkspace implements Exception {
  const RecordNotFoundExceptionForWorkspace();
}

class InvalidWorkspaceNameException implements Exception {
  const InvalidWorkspaceNameException();
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
