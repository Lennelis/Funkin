import '../data/song_metadata.dart';

/// One time change with its position worked out in steps as well as
/// milliseconds, so the two can be converted either way without walking the
/// whole list every time.
class _Segment {
  _Segment({
    required this.timeMs,
    required this.stepTime,
    required this.change,
  });

  final double timeMs;
  final double stepTime;
  final SongTimeChange change;

  double get stepLengthMs => change.stepLengthMs;
  double get beatLengthMs => change.beatLengthMs;
  int get stepsPerMeasure => change.timeSignatureNum * 4;
}

/// Turns song time into musical time and back.
///
/// A song can change tempo partway through, so neither direction is a single
/// multiplication: both walk to the segment that covers the value and measure
/// from there. Everything the grid draws — where a beat line sits, which step
/// a tap landed on — comes through here.
class Conductor {
  Conductor(SongMetadata metadata) {
    _build(metadata.timeChanges);
  }

  Conductor.fromChanges(List<SongTimeChange> changes) {
    _build(changes);
  }

  final List<_Segment> _segments = [];

  void _build(List<SongTimeChange> changes) {
    _segments.clear();

    final sorted = List<SongTimeChange>.from(changes)
      ..sort((a, b) => a.timeStamp.compareTo(b.timeStamp));

    if (sorted.isEmpty) sorted.add(SongTimeChange());

    // The first change is the start of the song whatever its timestamp says;
    // a song that begins at 0 with a change written at 400 is still 0 steps in
    // at 400ms, not negative.
    var stepTime = 0.0;
    double? previousTime;
    double? previousStepLength;

    for (final change in sorted) {
      if (previousTime != null && previousStepLength != null) {
        stepTime += (change.timeStamp - previousTime) / previousStepLength;
      }

      _segments.add(_Segment(
        timeMs: change.timeStamp,
        stepTime: stepTime,
        change: change,
      ));

      previousTime = change.timeStamp;
      previousStepLength = change.stepLengthMs;
    }
  }

  bool get isEmpty => _segments.isEmpty;

  SongTimeChange get firstChange => _segments.first.change;

  _Segment _segmentAtTime(double timeMs) {
    var found = _segments.first;
    for (final segment in _segments) {
      if (segment.timeMs > timeMs) break;
      found = segment;
    }
    return found;
  }

  _Segment _segmentAtStep(double step) {
    var found = _segments.first;
    for (final segment in _segments) {
      if (segment.stepTime > step) break;
      found = segment;
    }
    return found;
  }

  double stepAtTime(double timeMs) {
    final segment = _segmentAtTime(timeMs);
    return segment.stepTime + (timeMs - segment.timeMs) / segment.stepLengthMs;
  }

  double timeAtStep(double step) {
    final segment = _segmentAtStep(step);
    return segment.timeMs + (step - segment.stepTime) * segment.stepLengthMs;
  }

  double beatAtTime(double timeMs) => stepAtTime(timeMs) / 4;

  double timeAtBeat(double beat) => timeAtStep(beat * 4);

  double bpmAtTime(double timeMs) => _segmentAtTime(timeMs).change.bpm;

  double stepLengthAtTime(double timeMs) => _segmentAtTime(timeMs).stepLengthMs;

  double beatLengthAtTime(double timeMs) => _segmentAtTime(timeMs).beatLengthMs;

  /// How many steps make up a measure where [timeMs] falls. 16 at 4/4.
  int stepsPerMeasureAtTime(double timeMs) =>
      _segmentAtTime(timeMs).stepsPerMeasure;

  /// The measure number at [timeMs], counting from the segment it is in.
  /// Measures restart at each time change, which is what the game's own bar
  /// numbering does when a song changes signature.
  int measureAtTime(double timeMs) {
    final segment = _segmentAtTime(timeMs);
    final steps = stepAtTime(timeMs) - segment.stepTime;
    return (steps / segment.stepsPerMeasure).floor();
  }

  /// Round [timeMs] to the nearest grid line, where [snap] is the denominator
  /// you would name it by: 4 for quarter notes, 16 for sixteenths, 12 for
  /// eighth-note triplets.
  double snapTime(double timeMs, int snap) {
    if (snap <= 0) return timeMs;

    final segment = _segmentAtTime(timeMs);
    final increment = segment.beatLengthMs * 4 / snap;
    if (increment <= 0) return timeMs;

    final offset = timeMs - segment.timeMs;
    final snapped = segment.timeMs + (offset / increment).round() * increment;

    // Rounding up can carry past the next tempo change, where the grid it was
    // rounding to no longer applies. Landing exactly on the change is right.
    final next = _nextSegmentAfter(segment);
    if (next != null && snapped > next.timeMs) return next.timeMs;

    return snapped;
  }

  /// The grid increment at [timeMs] for a given [snap], in milliseconds.
  double snapIncrement(double timeMs, int snap) {
    if (snap <= 0) return 0;
    return _segmentAtTime(timeMs).beatLengthMs * 4 / snap;
  }

  _Segment? _nextSegmentAfter(_Segment segment) {
    final index = _segments.indexOf(segment);
    if (index < 0 || index + 1 >= _segments.length) return null;
    return _segments[index + 1];
  }

  /// Every grid line between [fromMs] and [toMs], as (time, kind) pairs where
  /// kind is 0 for a measure, 1 for a beat and 2 for a plain snap line. The
  /// painter draws each weight differently, and walking the tempo map once
  /// here keeps that out of the paint loop.
  List<GridLine> gridLines(double fromMs, double toMs, int snap) {
    final lines = <GridLine>[];
    if (toMs <= fromMs || snap <= 0) return lines;

    for (var index = 0; index < _segments.length; index++) {
      final segment = _segments[index];
      final next = index + 1 < _segments.length ? _segments[index + 1] : null;

      final segmentStart = segment.timeMs;
      final segmentEnd = next?.timeMs ?? toMs;
      if (segmentEnd < fromMs) continue;
      if (segmentStart > toMs) break;

      final increment = segment.beatLengthMs * 4 / snap;
      if (increment <= 0) continue;

      // Start at the first line at or after the window, rather than walking
      // the whole song up to it.
      final firstIndex =
          fromMs <= segmentStart ? 0 : ((fromMs - segmentStart) / increment).floor();

      for (var step = firstIndex;; step++) {
        final time = segmentStart + step * increment;
        if (time > toMs) break;
        if (next != null && time >= next.timeMs) break;
        if (time < fromMs) continue;

        final sinceSegment = time - segmentStart;
        final beatsIn = sinceSegment / segment.beatLengthMs;
        final measureLength = segment.beatLengthMs * segment.change.timeSignatureNum;

        final isMeasure = _isMultiple(sinceSegment, measureLength);
        final isBeat = _isMultiple(sinceSegment, segment.beatLengthMs);

        lines.add(GridLine(
          timeMs: time,
          kind: isMeasure
              ? GridLineKind.measure
              : (isBeat ? GridLineKind.beat : GridLineKind.snap),
          beat: beatsIn,
        ));
      }
    }

    return lines;
  }

  /// Floating point time never lands exactly on a multiple, so "is this a beat
  /// line" is a question about how close it got.
  static bool _isMultiple(double value, double interval) {
    if (interval <= 0) return false;
    final ratio = value / interval;
    return (ratio - ratio.roundToDouble()).abs() < 0.001;
  }
}

enum GridLineKind { measure, beat, snap }

class GridLine {
  const GridLine({required this.timeMs, required this.kind, required this.beat});

  final double timeMs;
  final GridLineKind kind;
  final double beat;
}
