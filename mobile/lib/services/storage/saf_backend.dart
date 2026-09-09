import 'dart:convert';

import 'package:flutter/services.dart';

import 'storage_backend.dart';

/// Android's Storage Access Framework, over a method channel to the Kotlin in
/// `android/app/src/main/kotlin`.
///
/// The reason this is not a plain `dart:io` path: since Android 11 an app
/// cannot read a mod folder on shared storage by path at all. It asks the
/// person for a folder, is handed a tree URI for it, and everything under it
/// is addressed by document URI from then on. Those URIs are not paths — you
/// cannot append a name to one and get its child — so this class is the only
/// place in the app that knows the difference.
class SafBackend implements StorageBackend {
  static const MethodChannel _channel = MethodChannel('dev.lennelis.funkin/saf');

  @override
  Future<StorageEntry?> pickRoot() async {
    final result = await _invoke<Map<Object?, Object?>?>('pickTree');
    if (result == null) return null;
    return _entry(result);
  }

  @override
  Future<List<StorageEntry>> savedRoots() async {
    final result = await _invoke<List<Object?>>('savedTrees') ?? const [];
    return result
        .whereType<Map<Object?, Object?>>()
        .map(_entry)
        .toList();
  }

  @override
  Future<void> forgetRoot(String id) =>
      _invoke<void>('forgetTree', {'uri': id});

  @override
  Future<List<StorageEntry>> list(String directoryId) async {
    final result =
        await _invoke<List<Object?>>('list', {'uri': directoryId}) ?? const [];

    final entries = result
        .whereType<Map<Object?, Object?>>()
        .map(_entry)
        .toList();

    // SAF returns children in whatever order the provider felt like. A song
    // list that reshuffles between openings is worse than a slow sort.
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return entries;
  }

  @override
  Future<StorageEntry?> child(String directoryId, String name) async {
    final result = await _invoke<Map<Object?, Object?>?>(
        'child', {'uri': directoryId, 'name': name});
    return result == null ? null : _entry(result);
  }

  @override
  Future<Uint8List> readBytes(String fileId) async {
    final result = await _invoke<Uint8List>('read', {'uri': fileId});
    if (result == null) throw StorageException('Could not read $fileId');
    return result;
  }

  @override
  Future<String> readString(String fileId) async =>
      utf8.decode(await readBytes(fileId));

  @override
  Future<void> writeBytes(String fileId, Uint8List bytes) =>
      _invoke<void>('write', {'uri': fileId, 'bytes': bytes});

  @override
  Future<void> writeString(String fileId, String contents) =>
      writeBytes(fileId, Uint8List.fromList(utf8.encode(contents)));

  @override
  Future<StorageEntry> createFile(String directoryId, String name) async {
    final result = await _invoke<Map<Object?, Object?>?>(
        'createFile', {'uri': directoryId, 'name': name});
    if (result == null) throw StorageException('Could not create $name');
    return _entry(result);
  }

  @override
  Future<StorageEntry> createDirectory(String directoryId, String name) async {
    final result = await _invoke<Map<Object?, Object?>?>(
        'createDirectory', {'uri': directoryId, 'name': name});
    if (result == null) throw StorageException('Could not create $name');
    return _entry(result);
  }

  @override
  String displayPath(String id) {
    // A tree URI ends in the provider's own encoding of the path, which is
    // close enough to readable once the escaping is undone.
    final decoded = Uri.decodeFull(id);
    final marker = decoded.lastIndexOf(':');
    final tail = marker < 0 ? decoded : decoded.substring(marker + 1);
    return tail.isEmpty ? '/' : '/$tail';
  }

  StorageEntry _entry(Map<Object?, Object?> map) {
    final modified = map['modified'];
    return StorageEntry(
      id: '${map['uri']}',
      name: '${map['name']}',
      isDirectory: map['isDirectory'] == true,
      size: map['size'] is int ? map['size'] as int : 0,
      modified: modified is int && modified > 0
          ? DateTime.fromMillisecondsSinceEpoch(modified)
          : null,
    );
  }

  Future<T?> _invoke<T>(String method, [Map<String, dynamic>? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      throw StorageException(error.message ?? 'Storage error in $method');
    } on MissingPluginException {
      throw StorageException('Device storage is not available on this platform');
    }
  }
}
