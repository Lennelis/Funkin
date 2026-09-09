import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:funkin_editors/data/song_chart.dart';
import 'package:funkin_editors/services/storage/io_backend.dart';
import 'package:funkin_editors/services/storage/storage_backend.dart';
import 'package:funkin_editors/services/workspace.dart';

/// Build a mod folder on disk, laid out the way Polymod expects one.
Directory _buildMod(String name, {bool nested = false}) {
  final root = Directory.systemTemp.createTempSync(name);
  final base = nested ? (Directory('${root.path}/preload')..createSync()) : root;

  Directory('${base.path}/data/songs/bopeebo').createSync(recursive: true);
  Directory('${base.path}/data/characters').createSync(recursive: true);
  Directory('${root.path}/songs/bopeebo').createSync(recursive: true);

  final songs = '${base.path}/data/songs/bopeebo';

  File('$songs/bopeebo-metadata.json').writeAsStringSync(json.encode({
    'version': '2.2.4',
    'songName': 'Bopeebo',
    'artist': 'Kawai Sprite',
    'playData': {
      'difficulties': ['easy', 'normal', 'hard'],
      'songVariations': ['erect'],
      'characters': {'player': 'bf', 'girlfriend': 'gf', 'opponent': 'dad'},
      'stage': 'mainStage',
      'noteStyle': 'funkin',
    },
    'generatedBy': 'test',
    'timeChanges': [
      {'t': 0, 'bpm': 100}
    ],
  }));

  File('$songs/bopeebo-chart.json').writeAsStringSync(json.encode({
    'version': '2.0.0',
    'scrollSpeed': {'default': 1.3},
    'events': <dynamic>[],
    'notes': {
      'normal': [
        {'t': 0, 'd': 6},
        {'t': 600, 'd': 7, 'l': 525},
      ],
    },
    'generatedBy': 'test',
  }));

  // A variation, which is the same pair of files with a suffix.
  File('$songs/bopeebo-metadata-erect.json')
      .writeAsStringSync(json.encode({'version': '2.2.4', 'songName': 'Bopeebo'}));
  File('$songs/bopeebo-chart-erect.json').writeAsStringSync(json.encode({
    'version': '2.0.0',
    'notes': {
      'normal': [
        {'t': 0, 'd': 0}
      ]
    },
  }));

  // A file that is in the folder but is not part of the song.
  File('$songs/notes.txt').writeAsStringSync('scratch');

  File('${base.path}/data/characters/bf.json')
      .writeAsStringSync(json.encode({'version': '1.0.0', 'name': 'Boyfriend'}));

  File('${root.path}/songs/bopeebo/Inst.ogg').writeAsBytesSync([0, 1, 2]);
  File('${root.path}/songs/bopeebo/Inst.mp3').writeAsBytesSync([0, 1, 2]);
  File('${root.path}/songs/bopeebo/Voices-bf.ogg').writeAsBytesSync([0, 1, 2]);

  return root;
}

StorageEntry _rootEntry(Directory directory) => StorageEntry(
      id: directory.path,
      name: directory.path.split(Platform.pathSeparator).last,
      isDirectory: true,
    );

void main() {
  late Directory root;
  late Workspace workspace;

  setUp(() async {
    root = _buildMod('funkin_mod');
    workspace = Workspace(storage: IoBackend(), root: _rootEntry(root));
    await workspace.scan();
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('scanning a mod folder', () {
    test('finds the data folders', () {
      expect(workspace.isReady, isTrue);
      expect(workspace.songsData, isNotNull);
      expect(workspace.charactersData, isNotNull);
      expect(workspace.songsAudio, isNotNull);
    });

    test('finds the song and its variations', () {
      expect(workspace.songs, hasLength(1));
      expect(workspace.songs.first.id, 'bopeebo');
      expect(workspace.songs.first.variations, ['default', 'erect']);
      expect(workspace.songs.first.isPlayable, isTrue);
    });

    test('ignores files that are not part of a song', () {
      final song = workspace.songs.first;
      expect(song.metadataFiles.keys, containsAll(['default', 'erect']));
      expect(song.chartFiles.keys, containsAll(['default', 'erect']));
      expect(song.metadataFiles, hasLength(2));
    });

    test('finds the audio', () async {
      final tracks = await workspace.audioTracks(workspace.songs.first);

      expect(tracks.keys, containsAll(['Inst', 'Voices-bf']));
      // The same track ships as both ogg and mp3; only one of them plays.
      expect(tracks['Inst']!.extension, 'ogg');
    });

    test('finds the characters', () async {
      final characters = await workspace.characterFiles();
      expect(characters.map((file) => file.stem), ['bf']);
    });
  });

  group('the game’s own assets layout', () {
    test('is found a level down', () async {
      final nested = _buildMod('funkin_assets', nested: true);
      addTearDown(() => nested.deleteSync(recursive: true));

      final assets =
          Workspace(storage: IoBackend(), root: _rootEntry(nested));
      await assets.scan();

      expect(assets.isReady, isTrue);
      expect(assets.songs, hasLength(1));
      // Audio sits outside preload/, so it takes the second look to find it.
      expect(assets.songs.first.audioDirectory, isNotNull);
    });
  });

  group('loading and saving', () {
    test('loads a song', () async {
      final project = await workspace.loadSong(workspace.songs.first);

      expect(project.metadata.songName, 'Bopeebo');
      expect(project.chart.notesFor('normal'), hasLength(2));
      expect(project.metadata.startingBpm, 100);
    });

    test('a variation loads its own files', () async {
      final project = await workspace
          .loadSong(workspace.songs.first, variation: 'erect');

      expect(project.variation, 'erect');
      expect(project.chart.notesFor('normal'), hasLength(1));
      expect(project.chart.notesFor('normal').first.data, 0);
    });

    test('saving writes the chart back where it came from', () async {
      final project = await workspace.loadSong(workspace.songs.first);
      project.chart.notes['normal']!.add(SongNoteData(time: 1200, data: 3));

      await workspace.saveChart(project);

      final reloaded = await workspace.loadSong(workspace.songs.first);
      expect(reloaded.chart.notesFor('normal'), hasLength(3));
      expect(reloaded.chart.notesFor('normal').last.time, 1200);
    });

    test('saving metadata keeps the rest of the file', () async {
      final project = await workspace.loadSong(workspace.songs.first);
      project.metadata.songName = 'Bopeebo (edited)';

      await workspace.saveMetadata(project);

      final reloaded = await workspace.loadSong(workspace.songs.first);
      expect(reloaded.metadata.songName, 'Bopeebo (edited)');
      expect(reloaded.metadata.artist, 'Kawai Sprite');
      expect(reloaded.metadata.playData.difficulties,
          ['easy', 'normal', 'hard']);
    });

    test('a saved file is JSON a person can read', () async {
      final project = await workspace.loadSong(workspace.songs.first);
      await workspace.saveChart(project);

      final contents =
          File(project.chartFile!.id).readAsStringSync();

      expect(contents, contains('\n  "version"'));
      expect(contents, endsWith('\n'));
    });
  });

  group('a folder that is not a mod', () {
    test('scans to nothing rather than failing', () async {
      final empty = Directory.systemTemp.createTempSync('funkin_empty');
      addTearDown(() => empty.deleteSync(recursive: true));

      final nothing = Workspace(storage: IoBackend(), root: _rootEntry(empty));
      await nothing.scan();

      expect(nothing.isReady, isFalse);
      expect(nothing.songs, isEmpty);
    });
  });
}
