import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'storage_backend.dart';

/// Ordinary files and folders, for anywhere that still has them.
///
/// Android is the app's home, and there [SafBackend] is what runs. This one
/// backs the tests, and a desktop run when you want to look at the editors
/// without a phone in your hand. Here an id really is a path.
class IoBackend implements StorageBackend {
  IoBackend({this.onPick});

  /// Where [pickRoot] gets a folder from. There is no system picker to call
  /// on a bare desktop build, so whatever hosts this supplies one.
  final Future<String?> Function()? onPick;

  final List<String> _saved = [];

  @override
  Future<StorageEntry?> pickRoot() async {
    final picked = await onPick?.call();
    if (picked == null) return null;

    final directory = Directory(picked);
    if (!directory.existsSync()) {
      throw StorageException('No folder at $picked');
    }

    if (!_saved.contains(picked)) _saved.add(picked);
    return _directoryEntry(directory);
  }

  @override
  Future<List<StorageEntry>> savedRoots() async => _saved
      .where((path) => Directory(path).existsSync())
      .map((path) => _directoryEntry(Directory(path)))
      .toList();

  @override
  Future<void> forgetRoot(String id) async => _saved.remove(id);

  @override
  Future<List<StorageEntry>> list(String directoryId) async {
    final directory = Directory(directoryId);
    if (!directory.existsSync()) return const [];

    final entries = <StorageEntry>[];
    for (final entity in directory.listSync(followLinks: false)) {
      final stat = entity.statSync();
      entries.add(StorageEntry(
        id: entity.path,
        name: entity.uri.pathSegments.where((part) => part.isNotEmpty).last,
        isDirectory: stat.type == FileSystemEntityType.directory,
        size: stat.size,
        modified: stat.modified,
      ));
    }

    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return entries;
  }

  @override
  Future<StorageEntry?> child(String directoryId, String name) async {
    final path = '$directoryId${Platform.pathSeparator}$name';

    final file = File(path);
    if (file.existsSync()) {
      final stat = file.statSync();
      return StorageEntry(
        id: path,
        name: name,
        isDirectory: false,
        size: stat.size,
        modified: stat.modified,
      );
    }

    final directory = Directory(path);
    if (directory.existsSync()) return _directoryEntry(directory);

    return null;
  }

  @override
  Future<Uint8List> readBytes(String fileId) async {
    final file = File(fileId);
    if (!file.existsSync()) throw StorageException('No file at $fileId');
    return file.readAsBytes();
  }

  @override
  Future<String> readString(String fileId) async =>
      utf8.decode(await readBytes(fileId));

  @override
  Future<void> writeBytes(String fileId, Uint8List bytes) async {
    final file = File(fileId);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> writeString(String fileId, String contents) =>
      writeBytes(fileId, Uint8List.fromList(utf8.encode(contents)));

  @override
  Future<StorageEntry> createFile(String directoryId, String name) async {
    final path = '$directoryId${Platform.pathSeparator}$name';
    final file = File(path);
    if (!file.existsSync()) {
      await file.parent.create(recursive: true);
      await file.create();
    }
    return StorageEntry(id: path, name: name, isDirectory: false);
  }

  @override
  Future<StorageEntry> createDirectory(String directoryId, String name) async {
    final path = '$directoryId${Platform.pathSeparator}$name';
    await Directory(path).create(recursive: true);
    return StorageEntry(id: path, name: name, isDirectory: true);
  }

  @override
  String displayPath(String id) => id;

  StorageEntry _directoryEntry(Directory directory) => StorageEntry(
        id: directory.path,
        name: directory.uri.pathSegments.where((part) => part.isNotEmpty).last,
        isDirectory: true,
      );
}
