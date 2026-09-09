import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:funkin_editors/data/song_chart.dart';
import 'package:funkin_editors/data/song_metadata.dart';

/// Shaped like a real `<song>-chart.json`, down to the fields the game leaves
/// out of one.
const String _chartJson = '''
{
  "version": "2.0.0",
  "scrollSpeed": { "easy": 1.2, "normal": 1.3, "hard": 1.6 },
  "events": [
    { "t": 0, "e": "FocusCamera", "v": 1 },
    { "t": 4200, "e": "PlayAnimation", "v": { "anim": "hey", "force": true, "target": "bf" } }
  ],
  "notes": {
    "normal": [
      { "t": 0, "d": 6 },
      { "t": 600, "d": 7, "l": 525 },
      { "t": 1200, "d": 2, "k": "mine" }
    ]
  },
  "generatedBy": "Friday Night Funkin' - v0.8.1"
}
''';

const String _metadataJson = '''
{
  "version": "2.2.4",
  "songName": "Bopeebo",
  "artist": "Kawai Sprite",
  "charter": "ninjamuffin99 + MtH",
  "offsets": {},
  "playData": {
    "songVariations": ["erect", "pico"],
    "difficulties": ["easy", "normal", "hard"],
    "characters": { "player": "bf", "girlfriend": "gf", "opponent": "dad" },
    "stage": "mainStage",
    "noteStyle": "funkin",
    "ratings": { "easy": 1, "normal": 1, "hard": 2 },
    "album": "volume1"
  },
  "generatedBy": "Friday Night Funkin' - v0.8.1",
  "timeChanges": [{ "t": 0, "b": 0, "bpm": 100, "bt": [4, 4, 4, 4] }]
}
''';

Map<String, dynamic> _decode(String source) =>
    (json.decode(source) as Map).cast<String, dynamic>();

void main() {
  group('reading a chart', () {
    final chart = SongChartData.fromJson(_decode(_chartJson));

    test('finds the notes', () {
      expect(chart.notes['normal'], hasLength(3));
      expect(chart.notesFor('normal').first.data, 6);
    });

    test('a missing length is a tap', () {
      expect(chart.notesFor('normal').first.isHold, isFalse);
      expect(chart.notesFor('normal')[1].length, 525);
      expect(chart.notesFor('normal')[1].isHold, isTrue);
    });

    test('lanes split into strumline and direction', () {
      // 6 is the opponent's third arrow; 2 is the player's.
      expect(chart.notesFor('normal').first.strumline, 1);
      expect(chart.notesFor('normal').first.direction, 2);
      expect(chart.notesFor('normal')[2].strumline, 0);
      expect(chart.notesFor('normal')[2].direction, 2);
    });

    test('keeps a note kind', () {
      expect(chart.notesFor('normal')[2].kind, 'mine');
    });

    test('an undefined difficulty falls back to normal', () {
      expect(chart.notesFor('nightmare'), chart.notesFor('normal'));
      expect(chart.scrollSpeedFor('hard'), 1.6);
      expect(chart.scrollSpeedFor('nightmare'), 1.0);
    });

    test('events keep whatever value they were given', () {
      expect(chart.events.first.value, 1);
      expect((chart.events[1].value as Map)['anim'], 'hey');
    });
  });

  group('writing a chart', () {
    test('comes back byte for byte', () {
      final source = _decode(_chartJson);
      final written = SongChartData.fromJson(source).toJson();

      expect(json.encode(written), json.encode(source));
    });

    test('defaults stay out of the file', () {
      final note = SongNoteData(time: 100, data: 3);
      expect(note.toJson().containsKey('l'), isFalse);
      expect(note.toJson().containsKey('k'), isFalse);
      expect(note.toJson().containsKey('p'), isFalse);
    });

    test('whole numbers do not grow a decimal point', () {
      // Writing 600.0 where the file said 600 turns a one-note edit into a
      // diff against every line of the chart.
      final note = SongNoteData(time: 600, data: 1, length: 525);
      expect(note.toJson()['t'], 600);
      expect(note.toJson()['t'], isA<int>());
      expect(note.toJson()['l'], 525);
    });

    test('an edit survives the trip', () {
      final chart = SongChartData.fromJson(_decode(_chartJson));
      chart.notes['normal']!.add(SongNoteData(time: 1800, data: 0));

      final again = SongChartData.fromJson(
          (json.decode(json.encode(chart.toJson())) as Map)
              .cast<String, dynamic>());

      expect(again.notesFor('normal'), hasLength(4));
      expect(again.notesFor('normal').last.time, 1800);
    });
  });

  group('fields this app does not know about', () {
    test('survive a save', () {
      final source = _decode(_chartJson);
      source['somethingNew'] = {'from': 'a later build'};
      (source['notes']['normal'][0] as Map)['x'] = 42;

      final written = SongChartData.fromJson(source).toJson();

      expect(written['somethingNew'], {'from': 'a later build'});
      expect((written['notes'] as Map)['normal'][0]['x'], 42);
    });

    test('do not overrule an edit to a field it does know', () {
      final chart = SongChartData.fromJson(_decode(_chartJson));
      chart.notesFor('normal').first.time = 999;

      expect(chart.toJson()['notes']['normal'][0]['t'], 999);
    });
  });

  group('reading metadata', () {
    final metadata = SongMetadata.fromJson(_decode(_metadataJson));

    test('finds the song', () {
      expect(metadata.songName, 'Bopeebo');
      expect(metadata.artist, 'Kawai Sprite');
      expect(metadata.startingBpm, 100);
    });

    test('finds the play data', () {
      expect(metadata.playData.difficulties, ['easy', 'normal', 'hard']);
      expect(metadata.playData.songVariations, ['erect', 'pico']);
      expect(metadata.playData.characters.opponent, 'dad');
      expect(metadata.playData.stage, 'mainStage');
    });

    test('vocal tracks default to the characters', () {
      // The file leaves these out, and the game fills them in from the
      // character names rather than leaving a song with no vocals.
      expect(metadata.playData.characters.playerVocals, ['bf']);
      expect(metadata.playData.characters.opponentVocals, ['dad']);
    });

    test('comes back byte for byte', () {
      final source = _decode(_metadataJson);
      final written = SongMetadata.fromJson(source).toJson();

      expect(json.encode(written), json.encode(source));
    });

    test('a field the file left out is not invented on write', () {
      final source = _decode(_metadataJson);
      final written = SongMetadata.fromJson(source).toJson();

      // The characters block had no vocal lists, so it still has none.
      expect((written['playData']['characters'] as Map).containsKey('playerVocals'),
          isFalse);
      expect(written.containsKey('looped'), isFalse);
    });
  });

  group('timing', () {
    test('a step is a sixteenth of a 4/4 bar', () {
      final change = SongTimeChange(bpm: 120);
      expect(change.beatLengthMs, closeTo(500, 0.001));
      expect(change.stepLengthMs, closeTo(125, 0.001));
      expect(change.measureLengthMs, closeTo(2000, 0.001));
    });

    test('a song with no time changes still has a tempo', () {
      final metadata = SongMetadata.fromJson({'timeChanges': <dynamic>[]});
      expect(metadata.timeChanges, hasLength(1));
      expect(metadata.startingBpm, 100);
    });
  });
}
