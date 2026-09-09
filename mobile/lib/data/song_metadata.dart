import 'json_extras.dart';

/// The metadata half of a V-Slice song, as written by the game's
/// `SongRegistry` — `<song>-metadata.json`, or `-metadata-<variation>.json`
/// for a variation like erect or pico.
///
/// Field names and defaults follow `source/funkin/data/song/SongData.hx`.
class SongMetadata with JsonExtras {
  static const String currentVersion = '2.2.4';

  static const Set<String> _claimed = {
    'version', 'songName', 'artist', 'charter', 'divisions', 'looped',
    'offsets', 'playData', 'generatedBy', 'timeFormat', 'timeChanges',
  };

  String version;
  String songName;
  String artist;
  String? charter;
  int? divisions;
  bool looped;
  SongOffsets offsets;
  SongPlayData playData;
  String generatedBy;
  String timeFormat;
  List<SongTimeChange> timeChanges;

  /// Which variation this file is, taken from the filename rather than the
  /// contents — the game does the same. `default` for the plain metadata.
  String variation;

  /// Whether the file said so. `ms` is the only format the game has ever
  /// written, so most files leave it out, and writing it back in would put a
  /// line into every song a person opened.
  bool _hadTimeFormat = false;

  SongMetadata({
    this.version = currentVersion,
    this.songName = 'Unknown',
    this.artist = 'Unknown',
    this.charter,
    this.divisions,
    this.looped = false,
    SongOffsets? offsets,
    SongPlayData? playData,
    this.generatedBy = 'Funkin Editors',
    this.timeFormat = 'ms',
    List<SongTimeChange>? timeChanges,
    this.variation = 'default',
  })  : offsets = offsets ?? SongOffsets(),
        playData = playData ?? SongPlayData(),
        timeChanges = timeChanges ?? [SongTimeChange()];

  factory SongMetadata.fromJson(Map<String, dynamic> json,
      {String variation = 'default'}) {
    final changes = (json['timeChanges'] as List?)
            ?.whereType<Map>()
            .map((item) => SongTimeChange.fromJson(item.cast<String, dynamic>()))
            .toList() ??
        <SongTimeChange>[];

    final metadata = SongMetadata(
      version: '${json['version'] ?? currentVersion}',
      songName: '${json['songName'] ?? 'Unknown'}',
      artist: '${json['artist'] ?? 'Unknown'}',
      charter: json['charter'] as String?,
      divisions: json['divisions'] == null ? null : asInt(json['divisions']),
      looped: json['looped'] == true,
      offsets: SongOffsets.fromJson(json['offsets']),
      playData: SongPlayData.fromJson(json['playData']),
      generatedBy: '${json['generatedBy'] ?? ''}',
      timeFormat: '${json['timeFormat'] ?? 'ms'}',
      // A song with no time changes has no tempo, and everything downstream
      // divides by it. One at 100bpm is what the game falls back to.
      timeChanges: changes.isEmpty ? [SongTimeChange()] : changes,
      variation: variation,
    );

    metadata._hadTimeFormat = json.containsKey('timeFormat');
    metadata.keepExtras(json, _claimed);
    return metadata;
  }

  Map<String, dynamic> toJson() => withExtras(pruneNulls(<String, dynamic>{
        'version': version,
        'songName': songName,
        'artist': artist,
        'charter': charter,
        'divisions': divisions,
        // Both are written only when set, matching the game's own output for
        // a song that never touched them.
        'looped': looped ? true : null,
        'offsets': offsets.toJson(),
        'playData': playData.toJson(),
        'generatedBy': generatedBy,
        if (_hadTimeFormat || timeFormat != 'ms') 'timeFormat': timeFormat,
        'timeChanges': timeChanges.map((change) => change.toJson()).toList(),
      }));

  /// The tempo in force at the start of the song, which is what the editor
  /// shows when nothing is playing.
  double get startingBpm => timeChanges.isEmpty ? 100 : timeChanges.first.bpm;
}

/// Per-track timing corrections, in milliseconds.
class SongOffsets with JsonExtras {
  static const Set<String> _claimed = {
    'instrumental', 'altInstrumentals', 'vocals', 'altVocals',
  };

  double instrumental;
  Map<String, double> altInstrumentals;
  Map<String, double> vocals;
  Map<String, Map<String, double>> altVocals;

  SongOffsets({
    this.instrumental = 0,
    Map<String, double>? altInstrumentals,
    Map<String, double>? vocals,
    Map<String, Map<String, double>>? altVocals,
  })  : altInstrumentals = altInstrumentals ?? {},
        vocals = vocals ?? {},
        altVocals = altVocals ?? {};

  factory SongOffsets.fromJson(dynamic json) {
    if (json is! Map) return SongOffsets();
    final map = json.cast<String, dynamic>();

    final altVocals = <String, Map<String, double>>{};
    final rawAltVocals = map['altVocals'];
    if (rawAltVocals is Map) {
      rawAltVocals.forEach((key, value) => altVocals['$key'] = asDoubleMap(value));
    }

    final offsets = SongOffsets(
      instrumental: asDouble(map['instrumental']),
      altInstrumentals: asDoubleMap(map['altInstrumentals']),
      vocals: asDoubleMap(map['vocals']),
      altVocals: altVocals,
    );

    offsets.keepExtras(map, _claimed);
    return offsets;
  }

  /// The offset for one vocal track, falling back the way the game does:
  /// a variation's own table first, then the shared one, then nothing.
  double vocalOffset(String character, {String? variation}) {
    if (variation != null && altVocals[variation]?[character] != null) {
      return altVocals[variation]![character]!;
    }
    return vocals[character] ?? 0;
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (instrumental != 0) json['instrumental'] = compactNumber(instrumental);
    if (altInstrumentals.isNotEmpty) {
      json['altInstrumentals'] = altInstrumentals.map(
          (key, value) => MapEntry(key, compactNumber(value)));
    }
    if (vocals.isNotEmpty) {
      json['vocals'] = vocals.map((key, value) => MapEntry(key, compactNumber(value)));
    }
    if (altVocals.isNotEmpty) {
      json['altVocals'] = altVocals.map((key, value) => MapEntry(
          key, value.map((inner, offset) => MapEntry(inner, compactNumber(offset)))));
    }
    return withExtras(json);
  }
}

/// Everything about how the song is played: who is on stage, where, and at
/// which difficulties.
class SongPlayData with JsonExtras {
  static const Set<String> _claimed = {
    'songVariations', 'difficulties', 'characters', 'stage', 'noteStyle',
    'ratings', 'album', 'previewStart', 'previewEnd', 'stickerPack',
  };

  List<String> songVariations;
  List<String> difficulties;
  SongCharacterData characters;
  String stage;
  String noteStyle;
  Map<String, int> ratings;
  String? album;
  int? previewStart;
  int? previewEnd;
  String? stickerPack;

  SongPlayData({
    List<String>? songVariations,
    List<String>? difficulties,
    SongCharacterData? characters,
    this.stage = 'mainStage',
    this.noteStyle = 'funkin',
    Map<String, int>? ratings,
    this.album,
    this.previewStart,
    this.previewEnd,
    this.stickerPack,
  })  : songVariations = songVariations ?? [],
        difficulties = difficulties ?? ['normal'],
        characters = characters ?? SongCharacterData(),
        ratings = ratings ?? {};

  factory SongPlayData.fromJson(dynamic json) {
    if (json is! Map) return SongPlayData();
    final map = json.cast<String, dynamic>();

    final difficulties = asStringList(map['difficulties']);

    final playData = SongPlayData(
      songVariations: asStringList(map['songVariations']),
      difficulties: difficulties.isEmpty ? ['normal'] : difficulties,
      characters: SongCharacterData.fromJson(map['characters']),
      stage: '${map['stage'] ?? 'mainStage'}',
      noteStyle: '${map['noteStyle'] ?? 'funkin'}',
      ratings: asIntMap(map['ratings']),
      album: map['album'] as String?,
      previewStart: map['previewStart'] == null ? null : asInt(map['previewStart']),
      previewEnd: map['previewEnd'] == null ? null : asInt(map['previewEnd']),
      stickerPack: map['stickerPack'] as String?,
    );

    playData.keepExtras(map, _claimed);
    return playData;
  }

  Map<String, dynamic> toJson() => withExtras(pruneNulls(<String, dynamic>{
        if (songVariations.isNotEmpty) 'songVariations': songVariations,
        'difficulties': difficulties,
        'characters': characters.toJson(),
        'stage': stage,
        'noteStyle': noteStyle,
        if (ratings.isNotEmpty) 'ratings': ratings,
        'album': album,
        'previewStart': previewStart,
        'previewEnd': previewEnd,
        'stickerPack': stickerPack,
      }));
}

/// Who sings this song, and which audio tracks belong to them.
class SongCharacterData with JsonExtras {
  static const Set<String> _claimed = {
    'player', 'girlfriend', 'opponent', 'instrumental', 'altInstrumentals',
    'opponentVocals', 'playerVocals',
  };

  String player;
  String girlfriend;
  String opponent;
  String instrumental;
  List<String> altInstrumentals;

  /// Which vocal tracks each side owns. The game defaults these to the
  /// character's own name when the file leaves them out, and so does this —
  /// but only on read, so a file that omitted them keeps omitting them.
  List<String> opponentVocals;
  List<String> playerVocals;

  bool _hadOpponentVocals = false;
  bool _hadPlayerVocals = false;

  SongCharacterData({
    this.player = 'bf',
    this.girlfriend = 'gf',
    this.opponent = 'dad',
    this.instrumental = '',
    List<String>? altInstrumentals,
    List<String>? opponentVocals,
    List<String>? playerVocals,
  })  : altInstrumentals = altInstrumentals ?? [],
        opponentVocals = opponentVocals ?? [],
        playerVocals = playerVocals ?? [];

  factory SongCharacterData.fromJson(dynamic json) {
    if (json is! Map) return SongCharacterData();
    final map = json.cast<String, dynamic>();

    final player = '${map['player'] ?? 'bf'}';
    final opponent = '${map['opponent'] ?? 'dad'}';

    final characters = SongCharacterData(
      player: player,
      girlfriend: '${map['girlfriend'] ?? 'gf'}',
      opponent: opponent,
      instrumental: '${map['instrumental'] ?? ''}',
      altInstrumentals: asStringList(map['altInstrumentals']),
      opponentVocals: map.containsKey('opponentVocals')
          ? asStringList(map['opponentVocals'])
          : [opponent],
      playerVocals: map.containsKey('playerVocals')
          ? asStringList(map['playerVocals'])
          : [player],
    );

    characters._hadOpponentVocals = map.containsKey('opponentVocals');
    characters._hadPlayerVocals = map.containsKey('playerVocals');
    characters.keepExtras(map, _claimed);
    return characters;
  }

  Map<String, dynamic> toJson() => withExtras(<String, dynamic>{
        'player': player,
        'girlfriend': girlfriend,
        'opponent': opponent,
        if (instrumental.isNotEmpty) 'instrumental': instrumental,
        if (altInstrumentals.isNotEmpty) 'altInstrumentals': altInstrumentals,
        if (_hadOpponentVocals) 'opponentVocals': opponentVocals,
        if (_hadPlayerVocals) 'playerVocals': playerVocals,
      });
}

/// A tempo and time signature, in force from [timeStamp] until the next one.
class SongTimeChange with JsonExtras {
  static const Set<String> _claimed = {'t', 'b', 'bpm', 'n', 'd', 'bt'};

  double timeStamp;
  double? beatTime;
  double bpm;
  int timeSignatureNum;
  int timeSignatureDen;
  List<int>? beatTuplets;

  SongTimeChange({
    this.timeStamp = 0,
    this.beatTime,
    this.bpm = 100,
    this.timeSignatureNum = 4,
    this.timeSignatureDen = 4,
    this.beatTuplets,
  });

  factory SongTimeChange.fromJson(Map<String, dynamic> json) {
    final change = SongTimeChange(
      timeStamp: asDouble(json['t']),
      beatTime: json['b'] == null ? null : asDouble(json['b']),
      bpm: asDouble(json['bpm'], 100),
      timeSignatureNum: asInt(json['n'], 4),
      timeSignatureDen: asInt(json['d'], 4),
      beatTuplets: (json['bt'] as List?)?.map((item) => asInt(item)).toList(),
    );

    change.keepExtras(json, _claimed);
    return change;
  }

  Map<String, dynamic> toJson() => withExtras(pruneNulls(<String, dynamic>{
        't': compactNumber(timeStamp),
        'b': beatTime == null ? null : compactNumber(beatTime!),
        'bpm': compactNumber(bpm),
        if (timeSignatureNum != 4) 'n': timeSignatureNum,
        if (timeSignatureDen != 4) 'd': timeSignatureDen,
        'bt': beatTuplets,
      }));

  /// How long one step lasts here. A step is a sixteenth at 4/4, and the
  /// denominator moves it the way you would expect at 3/4 or 6/8.
  double get stepLengthMs => (60000 / bpm) / (timeSignatureDen / 4) / 4;

  double get beatLengthMs => stepLengthMs * 4;

  double get measureLengthMs => beatLengthMs * timeSignatureNum;

  SongTimeChange copy() => SongTimeChange(
        timeStamp: timeStamp,
        beatTime: beatTime,
        bpm: bpm,
        timeSignatureNum: timeSignatureNum,
        timeSignatureDen: timeSignatureDen,
        beatTuplets: beatTuplets == null ? null : List<int>.from(beatTuplets!),
      );
}
