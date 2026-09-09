import 'dart:typed_data';

/// One file or folder, wherever it came from.
///
/// [id] is opaque on purpose. On Android it is a document URI, which cannot be
/// taken apart or joined the way a path can, so nothing above this layer is
/// allowed to build one — you get to a child by listing its parent.
class StorageEntry {
  const StorageEntry({
    required this.id,
    required this.name,
    required this.isDirectory,
    this.size = 0,
    this.modified,
  });

  final String id;
  final String name;
  final bool isDirectory;
  final int size;
  final DateTime? modified;

  String get extension {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  /// The name with its extension taken off, which is how songs and characters
  /// are identified everywhere in the game's data.
  String get stem {
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? name : name.substring(0, dot);
  }
}

/// Where the app's files live.
///
/// Android hands out access to a folder the person picked, addressed by URI;
/// everywhere else there are real paths. Both answer the same handful of
/// questions, so the editors do not have to know which one they are on.
abstract class StorageBackend {
  /// Ask the person for a folder to work in. Null if they backed out.
  Future<StorageEntry?> pickRoot();

  /// Folders picked earlier that this app can still reach without asking
  /// again. Android drops these when the app is uninstalled or the person
  /// revokes them, so a remembered folder is not a promise.
  Future<List<StorageEntry>> savedRoots();

  Future<void> forgetRoot(String id);

  Future<List<StorageEntry>> list(String directoryId);

  Future<StorageEntry?> child(String directoryId, String name);

  Future<Uint8List> readBytes(String fileId);

  Future<String> readString(String fileId);

  /// Overwrite [fileId] with [bytes].
  Future<void> writeBytes(String fileId, Uint8List bytes);

  Future<void> writeString(String fileId, String contents);

  /// Make [name] under [directoryId], or return what is already there.
  Future<StorageEntry> createFile(String directoryId, String name);

  Future<StorageEntry> createDirectory(String directoryId, String name);

  /// A path to show a person. Not something to pass back in — see [StorageEntry.id].
  String displayPath(String id);
}

class StorageException implements Exception {
  StorageException(this.message);

  final String message;

  @override
  String toString() => message;
}
