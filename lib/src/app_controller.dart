import 'package:flutter/foundation.dart';

import 'data/client_repository.dart';
import 'data/office_database.dart';
import 'domain/models.dart';

class AppController extends ChangeNotifier {
  AppController(this.database);

  final OfficeDatabase database;
  List<WorkspaceInfo> _workspaces = const <WorkspaceInfo>[];
  bool _busy = false;
  Object? _lastError;

  WorkspaceInfo get activeWorkspace => database.activeWorkspace;
  List<WorkspaceInfo> get workspaces => _workspaces;
  bool get isBusy => _busy;
  Object? get lastError => _lastError;

  ClientRepository get clients => ClientRepository(
        database.connection,
        workspaceId: activeWorkspace.id,
      );

  Future<void> initialize() async {
    _busy = true;
    notifyListeners();
    try {
      _workspaces = await database.listWorkspaces();
      await clients.verifyIntegrity();
      _lastError = null;
    } catch (error) {
      _lastError = error;
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> switchWorkspace(String id) async {
    if (_busy || id == activeWorkspace.id) return;
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      await database.switchWorkspace(id);
      _workspaces = await database.listWorkspaces();
      await clients.verifyIntegrity();
    } catch (error) {
      _lastError = error;
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> createWorkspace(String name) async {
    if (_busy) return;
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      await database.createWorkspace(name);
      _workspaces = await database.listWorkspaces();
      await clients.verifyIntegrity();
    } catch (error) {
      _lastError = error;
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> refreshWorkspaces() async {
    _workspaces = await database.listWorkspaces();
    notifyListeners();
  }

  void markDataChanged() => notifyListeners();

}
