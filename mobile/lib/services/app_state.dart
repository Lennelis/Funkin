import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'storage/io_backend.dart';
import 'storage/saf_backend.dart';
import 'storage/storage_backend.dart';
import 'workspace.dart';

/// What the app knows between screens: which storage it is on, which folder is
/// open, and what is in it.
class AppState extends ChangeNotifier {
  AppState({StorageBackend? storage})
      : storage = storage ?? _backendForPlatform();

  static StorageBackend _backendForPlatform() {
    // Android is the target; the filesystem backend is for a desktop run and
    // for the tests, where there is no picker to call.
    if (!kIsWeb && Platform.isAndroid) return SafBackend();
    return IoBackend();
  }

  final StorageBackend storage;

  static const String _lastRootKey = 'last-root';

  Workspace? workspace;
  bool isScanning = false;
  String? error;

  bool get hasWorkspace => workspace?.isReady == true;

  /// Reopen the folder from last time, if it is still reachable. A grant can
  /// be revoked or the folder deleted between launches, and neither is worth
  /// an error on the way in — the app just asks again.
  Future<void> restore() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(_lastRootKey);
    if (saved == null) return;

    final roots = await storage.savedRoots();
    final root = roots.where((entry) => entry.id == saved).firstOrNull;
    if (root == null) return;

    await _open(root);
  }

  Future<void> pickFolder() async {
    error = null;

    try {
      final root = await storage.pickRoot();
      if (root == null) return;

      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_lastRootKey, root.id);

      await _open(root);
    } on StorageException catch (failure) {
      error = failure.message;
      notifyListeners();
    }
  }

  Future<void> _open(StorageEntry root) async {
    isScanning = true;
    error = null;
    notifyListeners();

    final opened = Workspace(storage: storage, root: root);

    try {
      await opened.scan();

      workspace = opened;
      if (!opened.isReady) {
        error = 'No data/songs folder in ${root.name}. '
            'Pick a mod folder, or the assets folder inside the game.';
      }
    } on StorageException catch (failure) {
      error = failure.message;
    } catch (failure) {
      error = 'Could not read that folder: $failure';
    }

    isScanning = false;
    notifyListeners();
  }

  Future<void> rescan() async {
    final current = workspace;
    if (current == null) return;
    await _open(current.root);
  }

  Future<void> close() async {
    workspace = null;
    error = null;

    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_lastRootKey);

    notifyListeners();
  }
}
