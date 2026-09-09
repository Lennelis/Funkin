import 'dart:convert';

import '../data/song_chart.dart';
import '../data/song_metadata.dart';
import 'storage/storage_backend.dart';

/// Where the parts of a song live once a folder has been looked at.
class SongRef {
  SongRef({required this.id, required this.dataDirectory});

  /// The song's folder name, which is also its id everywhere in the game.
  final String id;

  /// `data/songs/<id>`, holding the metadata and chart files.
  final StorageEntry dataDirectory;

  /// Metadata files by variation. `default` is the plain one.
  final Map<String, StorageEntry> metadataFiles = {};

  /// Chart files by variation, keyed the same way.
  final Map<String, StorageEntry> chartFiles = {};

  /// `songs/<id>`, holding Inst and Voices. Null when the folder has charts
  /// but no audio, which is normal for a mod that leans on the base game's.
  StorageEntry? audioDirectory;

  List<String> get variations {
    final all = {...metadataFiles.keys, ...chartFiles.keys}.toList()..sort();
    // `default` is the song itself rather than a variation of it, so it leads
    // however it sorts.
    all.remove('default');
    return ['default', ...all];
  }

  bool get isPlayable => metadataFiles.isNotEmpty && chartFiles.isNotEmpty;
}

/// One song, loaded.
class SongProject {
  SongProject({
    required this.ref,
    required this.variation,
    required this.metadata,
    required this.chart,
    this.metadataFile,
    this.chartFile,
  });

  final SongRef ref;
  final String variation;
  final SongMetadata metadata;
  final SongChartData chart;
  final StorageEntry? metadataFile;
  final StorageEntry? chartFile;

  String get id => ref.id;
}

/// A mod folder, or the game's own assets — the app does not much care which.
///
/// Both keep songs under `data/songs/<id>` and audio under `songs/<id>`, so
/// the same walk finds either. The one difference is that the assets repo puts
/// its data inside `preload/`, which is why the search looks a level down
/// before giving up.
class Workspace {
  Workspace({required this.storage, required this.root});

  final StorageBackend storage;
  final StorageEntry root;

  StorageEntry? songsData;
  StorageEntry? charactersData;
  StorageEntry? songsAudio;
  StorageEntry? images;

  final List<SongRef> songs = [];

  bool get isReady => songsData != null;

  String get displayName => root.name;

  /// Look through the folder for the bits the editors need. Cheap enough to
  /// redo when something on disk changed under us.
  Future<void> scan() async {
    songsData = null;
    charactersData = null;
    songsAudio = null;
    images = null;
    songs.clear();

    final base = await _dataRoot(root);
    if (base == null) return;

    final data = await storage.child(base.id, 'data');
    if (data != null && data.isDirectory) {
      songsData = await _directoryChild(data, 'songs');
      charactersData = await _directoryChild(data, 'characters');
    }

    songsAudio = await _directoryChild(base, 'songs');
    images = await _directoryChild(base, 'images');

    // The assets repo splits audio out of `preload/`, so a folder that has the
    // charts but not the audio is worth one more look at the level above.
    if (songsAudio == null && base.id != root.id) {
      songsAudio = await _directoryChild(root, 'songs');
    }

    if (songsData != null) await _readSongs();
  }

  /// The folder that holds `data/`. Usually the one that was picked; in the
  /// assets repo it is `preload/` inside it.
  Future<StorageEntry?> _dataRoot(StorageEntry from) async {
    final direct = await storage.child(from.id, 'data');
    if (direct != null && direct.isDirectory) return from;

    for (final name in const ['preload', 'assets', 'shared']) {
      final nested = await _directoryChild(from, name);
      if (nested == null) continue;

      final data = await storage.child(nested.id, 'data');
      if (data != null && data.isDirectory) return nested;
    }

    return null;
  }

  Future<StorageEntry?> _directoryChild(StorageEntry parent, String name) async {
    final entry = await storage.child(parent.id, name);
    return (entry != null && entry.isDirectory) ? entry : null;
  }

  Future<void> _readSongs() async {
    final directories = await storage.list(songsData!.id);

    for (final directory in directories.where((entry) => entry.isDirectory)) {
      final ref = SongRef(id: directory.name, dataDirectory: directory);

      for (final file in await storage.list(directory.id)) {
        if (file.isDirectory || file.extension != 'json') continue;

        final variation = _variationOf(file.stem, ref.id, '-metadata');
        if (variation != null) {
          ref.metadataFiles[variation] = file;
          continue;
        }

        final chartVariation = _variationOf(file.stem, ref.id, '-chart');
        if (chartVariation != null) ref.chartFiles[chartVariation] = file;
      }

      if (ref.metadataFiles.isEmpty && ref.chartFiles.isEmpty) continue;

      if (songsAudio != null) {
        ref.audioDirectory = await _directoryChild(songsAudio!, ref.id);
      }

      songs.add(ref);
    }

    songs.sort((a, b) => a.id.compareTo(b.id));
  }

  /// `bopeebo-chart-erect` under the song `bopeebo` with the suffix `-chart`
  /// is the erect variation; `bopeebo-chart` is the song itself. Anything that
  /// does not fit the shape is some other file and gets left alone.
  static String? _variationOf(String stem, String songId, String suffix) {
    final head = '$songId$suffix';
    if (stem == head) return 'default';
    if (stem.startsWith('$head-')) {
      final variation = stem.substring(head.length + 1);
      return variation.isEmpty ? null : variation;
    }
    return null;
  }

  Future<SongProject> loadSong(SongRef ref, {String variation = 'default'}) async {
    final metadataFile = ref.metadataFiles[variation] ?? ref.metadataFiles['default'];
    final chartFile = ref.chartFiles[variation] ?? ref.chartFiles['default'];

    final metadata = metadataFile == null
        ? SongMetadata(songName: ref.id, variation: variation)
        : SongMetadata.fromJson(
            _decodeObject(await storage.readString(metadataFile.id)),
            variation: variation,
          );

    final chart = chartFile == null
        ? SongChartData()
        : SongChartData.fromJson(
            _decodeObject(await storage.readString(chartFile.id)));

    return SongProject(
      ref: ref,
      variation: variation,
      metadata: metadata,
      chart: chart,
      metadataFile: metadataFile,
      chartFile: chartFile,
    );
  }

  Future<void> saveChart(SongProject project) async {
    final file = project.chartFile ??
        await storage.createFile(
          project.ref.dataDirectory.id,
          _fileName(project.ref.id, 'chart', project.variation),
        );

    await storage.writeString(file.id, encodeJson(project.chart.toJson()));
    project.ref.chartFiles[project.variation] = file;
  }

  Future<void> saveMetadata(SongProject project) async {
    final file = project.metadataFile ??
        await storage.createFile(
          project.ref.dataDirectory.id,
          _fileName(project.ref.id, 'metadata', project.variation),
        );

    await storage.writeString(file.id, encodeJson(project.metadata.toJson()));
    project.ref.metadataFiles[project.variation] = file;
  }

  static String _fileName(String songId, String kind, String variation) =>
      variation == 'default'
          ? '$songId-$kind.json'
          : '$songId-$kind-$variation.json';

  /// The audio files that belong to a song, by track name — `Inst`,
  /// `Voices-bf` and so on, as the game names them.
  Future<Map<String, StorageEntry>> audioTracks(SongRef ref) async {
    final directory = ref.audioDirectory;
    if (directory == null) return {};

    final tracks = <String, StorageEntry>{};

    for (final file in await storage.list(directory.id)) {
      if (file.isDirectory) continue;
      if (!const ['ogg', 'mp3', 'wav'].contains(file.extension)) continue;

      // A song ships the same track twice, as ogg and mp3, for platforms that
      // will only take one of them. Either plays, so first one wins and ogg
      // gets asked first because that is what the game prefers.
      tracks.putIfAbsent(file.stem, () => file);
      if (file.extension == 'ogg') tracks[file.stem] = file;
    }

    return tracks;
  }

  /// Find the file behind an `assetPath` like `shared:characters/bf`.
  ///
  /// The prefix is the game's asset library, which in a mod folder is nothing
  /// at all — the file is simply under `images/`. In the game's own assets each
  /// library is its own folder with an `images/` inside it, so both places are
  /// worth a look before giving up.
  Future<StorageEntry?> resolveImage(String assetPath, String extension) async {
    final library = assetPath.contains(':') ? assetPath.split(':').first : null;
    final relative = assetPath.contains(':')
        ? assetPath.substring(assetPath.indexOf(':') + 1)
        : assetPath;

    final segments = relative.split('/').where((part) => part.isNotEmpty).toList();
    if (segments.isEmpty) return null;

    final fileName = '${segments.removeLast()}.$extension';

    if (images != null) {
      final found = await _walk(images!, segments, fileName);
      if (found != null) return found;
    }

    if (library != null) {
      final libraryFolder = await _directoryChild(root, library);
      if (libraryFolder != null) {
        final libraryImages = await _directoryChild(libraryFolder, 'images');
        if (libraryImages != null) {
          final found = await _walk(libraryImages, segments, fileName);
          if (found != null) return found;
        }
      }
    }

    return null;
  }

  Future<StorageEntry?> _walk(
      StorageEntry from, List<String> directories, String fileName) async {
    var current = from;

    for (final name in directories) {
      final next = await _directoryChild(current, name);
      if (next == null) return null;
      current = next;
    }

    final file = await storage.child(current.id, fileName);
    return (file != null && !file.isDirectory) ? file : null;
  }

  Future<List<StorageEntry>> characterFiles() async {
    if (charactersData == null) return const [];
    return (await storage.list(charactersData!.id))
        .where((entry) => !entry.isDirectory && entry.extension == 'json')
        .toList();
  }

  static Map<String, dynamic> _decodeObject(String contents) {
    final decoded = json.decode(contents);
    if (decoded is! Map) {
      throw StorageException('That file is not a JSON object');
    }
    return decoded.cast<String, dynamic>();
  }
}

/// Two spaces, and a newline at the end. The game writes its own files with an
/// indent, and matching it keeps a save from showing up as a whole-file diff
/// in whatever the mod is versioned with.
String encodeJson(Map<String, dynamic> value) =>
    '${const JsonEncoder.withIndent('  ').convert(value)}\n';
