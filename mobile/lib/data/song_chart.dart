import 'json_extras.dart';

/// The note half of a V-Slice song — `<song>-chart.json`. One file holds every
/// difficulty of one variation.
class SongChartData with JsonExtras {
  static const String currentVersion = '2.0.0';

  static const Set<String> _claimed = {
    'version', 'scrollSpeed', 'events', 'notes', 'generatedBy',
  };

  String version;
  Map<String, double> scrollSpeed;
  List<SongEventData> events;
  Map<String, List<SongNoteData>> notes;
  String generatedBy;

  SongChartData({
    this.version = currentVersion,
    Map<String, double>? scrollSpeed,
    List<SongEventData>? events,
    Map<String, List<SongNoteData>>? notes,
    this.generatedBy = 'Funkin Editors',
  })  : scrollSpeed = scrollSpeed ?? {'default': 1},
        events = events ?? [],
        notes = notes ?? {};

  factory SongChartData.fromJson(Map<String, dynamic> json) {
    final notes = <String, List<SongNoteData>>{};
    final rawNotes = json['notes'];
    if (rawNotes is Map) {
      rawNotes.forEach((difficulty, list) {
        if (list is! List) return;
        notes['$difficulty'] = list
            .whereType<Map>()
            .map((item) => SongNoteData.fromJson(item.cast<String, dynamic>()))
            .toList()
          // The game reads these in file order, but every editor operation
          // here — the note under your finger, the next one after the
          // playhead — assumes they climb.
          ..sort((a, b) => a.time.compareTo(b.time));
      });
    }

    final chart = SongChartData(
      version: '${json['version'] ?? currentVersion}',
      scrollSpeed: asDoubleMap(json['scrollSpeed']),
      events: (json['events'] as List?)
              ?.whereType<Map>()
              .map((item) => SongEventData.fromJson(item.cast<String, dynamic>()))
              .toList() ??
          <SongEventData>[],
      notes: notes,
      generatedBy: '${json['generatedBy'] ?? ''}',
    );

    chart.events.sort((a, b) => a.time.compareTo(b.time));
    chart.keepExtras(json, _claimed);
    return chart;
  }

  Map<String, dynamic> toJson() => withExtras(<String, dynamic>{
        'version': version,
        'scrollSpeed':
            scrollSpeed.map((key, value) => MapEntry(key, compactNumber(value))),
        'events': events.map((event) => event.toJson()).toList(),
        'notes': notes.map((difficulty, list) =>
            MapEntry(difficulty, list.map((note) => note.toJson()).toList())),
        'generatedBy': generatedBy,
      });

  /// The notes for one difficulty, falling back the way the game does — a
  /// difficulty the file never defined plays the normal chart.
  List<SongNoteData> notesFor(String difficulty) =>
      notes[difficulty] ?? notes['normal'] ?? const [];

  /// The scroll speed for one difficulty. `default` covers the rest, and a
  /// song that set neither scrolls at 1.
  double scrollSpeedFor(String difficulty) =>
      scrollSpeed[difficulty] ?? scrollSpeed['default'] ?? 1;

  List<String> get difficulties => notes.keys.toList()..sort();
}

/// One note. [data] is the lane across both strumlines at once: 0-3 are the
/// player's four, 4-7 the opponent's, which is what `getStrumlineIndex` in the
/// game divides out.
class SongNoteData with JsonExtras {
  static const Set<String> _claimed = {'t', 'd', 'l', 'k', 'p'};

  double time;
  int data;

  /// How long the note is held, in milliseconds. 0 is a tap.
  double length;

  /// A note kind from a mod, like a mine. Null is an ordinary note.
  String? kind;

  /// Per-note parameters a custom kind reads. Kept as raw JSON because what
  /// belongs in here is up to whoever wrote the note kind.
  List<dynamic>? params;

  SongNoteData({
    required this.time,
    required this.data,
    this.length = 0,
    this.kind,
    this.params,
  });

  factory SongNoteData.fromJson(Map<String, dynamic> json) {
    final note = SongNoteData(
      time: asDouble(json['t']),
      data: asInt(json['d']),
      length: asDouble(json['l']),
      // The game writes an empty string for "no kind" in some builds, and
      // treats it the same as absent.
      kind: (json['k'] is String && (json['k'] as String).isNotEmpty)
          ? json['k'] as String
          : null,
      params: (json['p'] as List?)?.toList(),
    );

    note.keepExtras(json, _claimed);
    return note;
  }

  Map<String, dynamic> toJson() => withExtras(<String, dynamic>{
        't': compactNumber(time),
        'd': data,
        // Defaults stay out of the file, which is how the game's own writer
        // keeps charts as small as they are.
        if (length != 0) 'l': compactNumber(length),
        if (kind != null) 'k': kind,
        if (params != null && params!.isNotEmpty) 'p': params,
      });

  bool get isHold => length > 0;

  /// 0 for the player's side, 1 for the opponent's.
  int get strumline => data ~/ 4;

  /// Which of the four arrows, left to right.
  int get direction => data % 4;

  double get endTime => time + length;

  SongNoteData copy({double? time, int? data, double? length}) {
    final note = SongNoteData(
      time: time ?? this.time,
      data: data ?? this.data,
      length: length ?? this.length,
      kind: kind,
      params: params == null ? null : List<dynamic>.from(params!),
    );
    note.extras.addAll(extras);
    return note;
  }
}

/// A song event — a camera move, an animation, anything the chart fires that
/// is not a note.
class SongEventData with JsonExtras {
  static const Set<String> _claimed = {'t', 'e', 'v'};

  double time;
  String kind;

  /// Whatever the event kind wants. A number, a string, an object — the game
  /// hands it straight to the event, so it is kept as raw JSON.
  dynamic value;

  SongEventData({required this.time, required this.kind, this.value});

  factory SongEventData.fromJson(Map<String, dynamic> json) {
    final event = SongEventData(
      time: asDouble(json['t']),
      kind: '${json['e'] ?? ''}',
      value: json['v'],
    );

    event.keepExtras(json, _claimed);
    return event;
  }

  Map<String, dynamic> toJson() => withExtras(<String, dynamic>{
        't': compactNumber(time),
        'e': kind,
        if (value != null) 'v': value,
      });

  SongEventData copy() =>
      SongEventData(time: time, kind: kind, value: value)..extras.addAll(extras);

  /// A one-line reading of [value] for the editor's event list.
  String get summary {
    final data = value;
    if (data == null) return kind;
    if (data is Map) {
      final parts = data.entries.map((entry) => '${entry.key}: ${entry.value}');
      return '$kind — ${parts.join(', ')}';
    }
    return '$kind — $data';
  }
}
