import 'package:flutter_test/flutter_test.dart';
import 'package:funkin_editors/data/song_metadata.dart';
import 'package:funkin_editors/services/conductor.dart';

void main() {
  group('at one tempo', () {
    final conductor = Conductor.fromChanges([SongTimeChange(bpm: 100)]);

    // 100bpm is a 600ms beat and a 150ms step, which is what Bopeebo runs at.
    test('a beat is 600ms', () {
      expect(conductor.timeAtBeat(1), closeTo(600, 0.001));
      expect(conductor.beatAtTime(600), closeTo(1, 0.001));
    });

    test('a step is a quarter of that', () {
      expect(conductor.timeAtStep(1), closeTo(150, 0.001));
      expect(conductor.stepAtTime(600), closeTo(4, 0.001));
    });

    test('time and steps convert back to each other', () {
      for (final time in [0.0, 137.5, 4200.0, 91234.5]) {
        expect(conductor.timeAtStep(conductor.stepAtTime(time)),
            closeTo(time, 0.001));
      }
    });

    test('measures are four beats', () {
      expect(conductor.measureAtTime(0), 0);
      expect(conductor.measureAtTime(2399), 0);
      expect(conductor.measureAtTime(2400), 1);
    });
  });

  group('across a tempo change', () {
    // Eight beats at 100, then twice the speed.
    final conductor = Conductor.fromChanges([
      SongTimeChange(bpm: 100),
      SongTimeChange(timeStamp: 4800, bpm: 200),
    ]);

    test('steps before the change are unaffected', () {
      expect(conductor.stepAtTime(600), closeTo(4, 0.001));
    });

    test('the change lands on the step it should', () {
      // 4800ms at 150ms a step is 32 steps in.
      expect(conductor.stepAtTime(4800), closeTo(32, 0.001));
    });

    test('steps after the change are half as long', () {
      expect(conductor.stepAtTime(4875), closeTo(33, 0.001));
      expect(conductor.timeAtStep(33), closeTo(4875, 0.001));
    });

    test('it still converts both ways', () {
      for (final time in [0.0, 4799.0, 4800.0, 4801.0, 12000.0]) {
        expect(conductor.timeAtStep(conductor.stepAtTime(time)),
            closeTo(time, 0.001));
      }
    });

    test('the tempo reported is the one in force', () {
      expect(conductor.bpmAtTime(4799), 100);
      expect(conductor.bpmAtTime(4800), 200);
    });
  });

  group('time signatures', () {
    test('a 3/4 measure is three beats', () {
      final conductor = Conductor.fromChanges(
          [SongTimeChange(bpm: 120, timeSignatureNum: 3)]);

      // 120bpm is a 500ms beat, so a 3/4 measure is 1500ms.
      expect(conductor.measureAtTime(1499), 0);
      expect(conductor.measureAtTime(1500), 1);
      expect(conductor.stepsPerMeasureAtTime(0), 12);
    });

    test('the denominator changes what a step is worth', () {
      final eighths =
          Conductor.fromChanges([SongTimeChange(bpm: 120, timeSignatureDen: 8)]);

      // At /8 the beat is half as long as at /4.
      expect(eighths.timeAtBeat(1), closeTo(250, 0.001));
    });
  });

  group('snapping', () {
    final conductor = Conductor.fromChanges([SongTimeChange(bpm: 100)]);

    test('sixteenths land on steps', () {
      expect(conductor.snapTime(140, 16), closeTo(150, 0.001));
      expect(conductor.snapTime(160, 16), closeTo(150, 0.001));
      expect(conductor.snapTime(80, 16), closeTo(150, 0.001));
      expect(conductor.snapTime(70, 16), closeTo(0, 0.001));
    });

    test('quarters land on beats', () {
      expect(conductor.snapTime(500, 4), closeTo(600, 0.001));
      expect(conductor.snapIncrement(0, 4), closeTo(600, 0.001));
    });

    test('triplets divide the beat in three', () {
      expect(conductor.snapIncrement(0, 12), closeTo(200, 0.001));
      expect(conductor.snapTime(190, 12), closeTo(200, 0.001));
    });

    test('rounding up never carries past a tempo change', () {
      final changing = Conductor.fromChanges([
        SongTimeChange(bpm: 100),
        SongTimeChange(timeStamp: 4700, bpm: 200),
      ]);

      // 4690 rounds back to 4650, which is an ordinary sixteenth inside the
      // first segment.
      expect(changing.snapTime(4690, 16), closeTo(4650, 0.001));

      // On a coarse grid the nearest line can be past the change. A quarter
      // note from 4650 rounds to 4800, which is in the next segment and on a
      // grid that does not apply there, so it stops at the change itself.
      expect(changing.snapTime(4650, 4), closeTo(4700, 0.001));
    });
  });

  group('grid lines', () {
    final conductor = Conductor.fromChanges([SongTimeChange(bpm: 100)]);

    test('one measure of sixteenths is sixteen lines', () {
      final lines = conductor.gridLines(0, 2399, 16);
      expect(lines.length, 16);
    });

    test('the weights fall where they should', () {
      final lines = conductor.gridLines(0, 2400, 16);

      expect(lines.first.kind, GridLineKind.measure);
      expect(lines[4].kind, GridLineKind.beat);
      expect(lines[1].kind, GridLineKind.snap);
      expect(lines.last.kind, GridLineKind.measure);
    });

    test('a window part way in starts at the first line inside it', () {
      final lines = conductor.gridLines(1000, 1400, 16);

      expect(lines, isNotEmpty);
      expect(lines.first.timeMs, greaterThanOrEqualTo(1000));
      expect(lines.last.timeMs, lessThanOrEqualTo(1400));
    });
  });
}
