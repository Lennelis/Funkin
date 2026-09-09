import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../data/song_chart.dart';
import '../../services/audio_engine.dart';
import '../../services/conductor.dart';
import '../../services/workspace.dart';

/// One undoable state of the chart. Charts run to a few hundred notes, so
/// keeping a copy per edit costs less than the bookkeeping an per-operation
/// undo would need, and it cannot get out of step with the thing it describes.
class _Snapshot {
  _Snapshot(this.notes, this.events);

  final List<SongNoteData> notes;
  final List<SongEventData> events;
}

enum ChartTool { place, select }

/// Everything the chart editor knows.
///
/// The playhead is the centre of it: the grid, the note under your finger and
/// what the audio does are all worked out from [timeMs] and the conductor,
/// rather than each keeping its own idea of where the song is.
class ChartController extends ChangeNotifier {
  ChartController({
    required this.workspace,
    required this.project,
    required this.audio,
  }) : conductor = Conductor(project.metadata) {
    final available = project.chart.difficulties;
    difficulty = available.contains('normal')
        ? 'normal'
        : (available.isNotEmpty ? available.first : 'normal');

    project.chart.notes.putIfAbsent(difficulty, () => <SongNoteData>[]);
  }

  final Workspace workspace;
  final SongProject project;
  final AudioEngine audio;

  Conductor conductor;

  late String difficulty;

  /// Where the playhead is, in milliseconds. While playing this follows the
  /// audio; while stopped it is whatever was last scrolled or snapped to.
  double timeMs = 0;

  /// The denominator of the grid: 16 is sixteenth notes, 12 eighth triplets.
  int snap = 16;

  /// How much of the song one screen shows, as pixels per millisecond.
  double zoom = 0.45;

  ChartTool tool = ChartTool.place;

  final Set<SongNoteData> selection = {};

  bool _dirty = false;
  bool get isDirty => _dirty;

  final List<_Snapshot> _undo = [];
  final List<_Snapshot> _redo = [];

  static const int _undoLimit = 100;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  List<SongNoteData> get notes =>
      project.chart.notes.putIfAbsent(difficulty, () => <SongNoteData>[]);

  List<SongEventData> get events => project.chart.events;

  double get scrollSpeed => project.chart.scrollSpeedFor(difficulty);

  /// The end of the song as the editor sees it: the audio if it loaded, and
  /// otherwise far enough past the last note to place more after it.
  double get lengthMs {
    final audioLength = audio.length.inMilliseconds.toDouble();
    if (audioLength > 0) return audioLength;

    final last = notes.isEmpty ? 0.0 : notes.last.endTime;
    final lastEvent = events.isEmpty ? 0.0 : events.last.time;
    return (last > lastEvent ? last : lastEvent) + 8000;
  }

  // -- moving about -------------------------------------------------------

  void seek(double milliseconds, {bool moveAudio = true}) {
    final clamped = milliseconds.clamp(0.0, lengthMs);
    if (clamped == timeMs) return;

    timeMs = clamped;
    if (moveAudio) audio.seek(clamped);
    notifyListeners();
  }

  /// Move by whole grid lines, which is what the step buttons do.
  void nudge(int steps) {
    final increment = conductor.snapIncrement(timeMs, snap);
    if (increment <= 0) return;

    // Snapping first means a nudge from an unsnapped position lands on the
    // grid rather than carrying the offset along forever.
    final base = conductor.snapTime(timeMs, snap);
    seek(base + increment * steps);
  }

  void setSnap(int value) {
    if (value == snap) return;
    snap = value;
    notifyListeners();
  }

  void setZoom(double value) {
    final clamped = value.clamp(0.08, 2.5);
    if (clamped == zoom) return;
    zoom = clamped;
    notifyListeners();
  }

  void setTool(ChartTool value) {
    if (tool == value) return;
    tool = value;
    selection.clear();
    notifyListeners();
  }

  void setDifficulty(String value) {
    if (value == difficulty) return;
    difficulty = value;
    project.chart.notes.putIfAbsent(value, () => <SongNoteData>[]);
    selection.clear();
    notifyListeners();
  }

  /// Called every frame while the audio runs, so the grid follows it.
  void followAudio() {
    if (!audio.isPlaying) return;

    timeMs = audio.positionMs;
    audio.correctDrift();
    notifyListeners();
  }

  Future<void> togglePlayback() async {
    if (audio.isPlaying) {
      await audio.pause();
    } else {
      await audio.seek(timeMs);
      await audio.play();
    }
    notifyListeners();
  }

  // -- editing ------------------------------------------------------------

  void _record() {
    _undo.add(_Snapshot(
      notes.map((note) => note.copy()).toList(),
      events.map((event) => event.copy()).toList(),
    ));

    if (_undo.length > _undoLimit) _undo.removeAt(0);

    // A new edit is a new branch; whatever was undone past this point is gone.
    _redo.clear();
    _dirty = true;
  }

  void _restore(_Snapshot snapshot) {
    project.chart.notes[difficulty] = snapshot.notes;
    project.chart.events
      ..clear()
      ..addAll(snapshot.events);
    selection.clear();
    _dirty = true;
  }

  void undo() {
    if (_undo.isEmpty) return;

    final current = _Snapshot(
      notes.map((note) => note.copy()).toList(),
      events.map((event) => event.copy()).toList(),
    );

    _restore(_undo.removeLast());
    _redo.add(current);
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;

    final current = _Snapshot(
      notes.map((note) => note.copy()).toList(),
      events.map((event) => event.copy()).toList(),
    );

    _restore(_redo.removeLast());
    _undo.add(current);
    notifyListeners();
  }

  /// The note at [lane] whose span covers [milliseconds], within [tolerance]
  /// of its head. Holds count along their whole length so a tap on the tail
  /// finds the note it belongs to.
  SongNoteData? noteAt(int lane, double milliseconds, double tolerance) {
    SongNoteData? best;
    var bestDistance = double.infinity;

    for (final note in notes) {
      if (note.data != lane) continue;

      final distance = (note.time - milliseconds).abs();
      final withinHead = distance <= tolerance;
      final withinTail =
          note.isHold && milliseconds >= note.time && milliseconds <= note.endTime;

      if (!withinHead && !withinTail) continue;
      if (distance >= bestDistance) continue;

      best = note;
      bestDistance = distance;
    }

    return best;
  }

  /// Put a note at the nearest grid line, or take away the one already there.
  /// One gesture doing both is what makes charting with a thumb bearable.
  void toggleNote(int lane, double milliseconds) {
    final snapped = conductor.snapTime(milliseconds, snap);
    final tolerance = conductor.snapIncrement(milliseconds, snap) / 2;

    final existing = noteAt(lane, snapped, tolerance);

    _record();

    if (existing != null) {
      notes.remove(existing);
      selection.remove(existing);
    } else {
      notes.add(SongNoteData(time: snapped, data: lane));
      notes.sort((a, b) => a.time.compareTo(b.time));
    }

    notifyListeners();
  }

  void removeNote(SongNoteData note) {
    _record();
    notes.remove(note);
    selection.remove(note);
    notifyListeners();
  }

  void removeSelection() {
    if (selection.isEmpty) return;

    _record();
    notes.removeWhere(selection.contains);
    selection.clear();
    notifyListeners();
  }

  void toggleSelected(SongNoteData note) {
    if (!selection.remove(note)) selection.add(note);
    notifyListeners();
  }

  /// Drag a hold's end to [milliseconds]. Dragging back to the head makes it a
  /// tap again, which is how you undo an overshoot without leaving the gesture.
  void resizeHold(SongNoteData note, double milliseconds, {bool record = true}) {
    final snapped = conductor.snapTime(milliseconds, snap);
    final length = (snapped - note.time).clamp(0.0, double.infinity);

    if (length == note.length) return;
    if (record) _record();

    note.length = length;
    _dirty = true;
    notifyListeners();
  }

  /// Move every selected note by [milliseconds], keeping them on the grid.
  void shiftSelection(double milliseconds) {
    if (selection.isEmpty) return;

    _record();

    for (final note in selection) {
      note.time = conductor.snapTime(note.time + milliseconds, snap)
          .clamp(0.0, double.infinity);
    }

    notes.sort((a, b) => a.time.compareTo(b.time));
    notifyListeners();
  }

  /// Send the selection to the other strumline. Charting one side and flipping
  /// it is common enough to be worth a button.
  void flipSelection() {
    if (selection.isEmpty) return;

    _record();

    for (final note in selection) {
      note.data = note.data < 4 ? note.data + 4 : note.data - 4;
    }

    notifyListeners();
  }

  // -- events -------------------------------------------------------------

  void addEvent(String kind, dynamic value, double milliseconds) {
    _record();

    events.add(SongEventData(
      time: conductor.snapTime(milliseconds, snap),
      kind: kind,
      value: value,
    ));

    events.sort((a, b) => a.time.compareTo(b.time));
    notifyListeners();
  }

  void updateEvent(SongEventData event, String kind, dynamic value) {
    _record();
    event.kind = kind;
    event.value = value;
    notifyListeners();
  }

  void removeEvent(SongEventData event) {
    _record();
    events.remove(event);
    notifyListeners();
  }

  /// Parse what someone typed into the event value box. Events take anything
  /// JSON, so a bare number or a bare word are both legitimate values and only
  /// the ones that look like JSON are treated as such.
  static dynamic parseEventValue(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    final looksStructured = trimmed.startsWith('{') ||
        trimmed.startsWith('[') ||
        trimmed == 'true' ||
        trimmed == 'false' ||
        trimmed == 'null' ||
        double.tryParse(trimmed) != null;

    if (!looksStructured) return trimmed;

    try {
      return json.decode(trimmed);
    } catch (error) {
      return trimmed;
    }
  }

  static String formatEventValue(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    return const JsonEncoder.withIndent('  ').convert(value);
  }

  // -- saving -------------------------------------------------------------

  Future<void> save() async {
    await workspace.saveChart(project);
    _dirty = false;
    notifyListeners();
  }

  /// Rebuild the conductor after the metadata editor changed the tempo map.
  void refreshTiming() {
    conductor = Conductor(project.metadata);
    notifyListeners();
  }

  void markDirty() {
    _dirty = true;
    notifyListeners();
  }
}
