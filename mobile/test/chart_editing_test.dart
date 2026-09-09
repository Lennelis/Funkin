import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:funkin_editors/data/song_chart.dart';
import 'package:funkin_editors/data/song_metadata.dart';
import 'package:funkin_editors/editors/chart/chart_controller.dart';
import 'package:funkin_editors/services/audio_engine.dart';
import 'package:funkin_editors/services/storage/io_backend.dart';
import 'package:funkin_editors/services/storage/storage_backend.dart';
import 'package:funkin_editors/services/workspace.dart';

/// A controller over a chart in memory. Nothing here touches the audio, which
/// is the point — the editing has to be testable without a device to play on.
ChartController _controller({List<SongNoteData>? notes}) {
  final root = Directory.systemTemp.createTempSync('funkin_edit');
  addTearDown(() => root.deleteSync(recursive: true));

  final workspace = Workspace(
    storage: IoBackend(),
    root: StorageEntry(id: root.path, name: 'mod', isDirectory: true),
  );

  final ref = SongRef(
    id: 'test',
    dataDirectory: StorageEntry(id: root.path, name: 'test', isDirectory: true),
  );

  final project = SongProject(
    ref: ref,
    variation: 'default',
    metadata: SongMetadata(timeChanges: [SongTimeChange(bpm: 100)]),
    chart: SongChartData(notes: {'normal': notes ?? []}),
  );

  return ChartController(
    workspace: workspace,
    project: project,
    audio: AudioEngine(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('placing notes', () {
    test('a tap puts one on the nearest grid line', () {
      final controller = _controller();

      // 100bpm is a 150ms step, so 140 belongs to the line at 150.
      controller.toggleNote(4, 140);

      expect(controller.notes, hasLength(1));
      expect(controller.notes.first.time, closeTo(150, 0.001));
      expect(controller.notes.first.data, 4);
    });

    test('a second tap in the same place takes it away', () {
      final controller = _controller();

      controller.toggleNote(4, 140);
      controller.toggleNote(4, 155);

      expect(controller.notes, isEmpty);
    });

    test('a tap in the next lane leaves the first alone', () {
      final controller = _controller();

      controller.toggleNote(4, 150);
      controller.toggleNote(5, 150);

      expect(controller.notes, hasLength(2));
    });

    test('notes stay in time order', () {
      final controller = _controller();

      controller.toggleNote(0, 1200);
      controller.toggleNote(1, 300);
      controller.toggleNote(2, 750);

      final times = controller.notes.map((note) => note.time).toList();
      expect(times, [300, 750, 1200]);
    });

    test('the snap decides where it lands', () {
      final controller = _controller()..setSnap(4);

      // A quarter note at 100bpm is 600ms.
      controller.toggleNote(0, 500);
      expect(controller.notes.first.time, closeTo(600, 0.001));
    });
  });

  group('holds', () {
    test('dragging out of a note gives it a length', () {
      final controller = _controller();
      controller.toggleNote(0, 0);

      controller.resizeHold(controller.notes.first, 620);

      // Snapped to the sixteenth at 600.
      expect(controller.notes.first.length, closeTo(600, 0.001));
      expect(controller.notes.first.isHold, isTrue);
    });

    test('dragging back to the head makes it a tap again', () {
      final controller = _controller();
      controller.toggleNote(0, 0);
      controller.resizeHold(controller.notes.first, 600);

      controller.resizeHold(controller.notes.first, 10);

      expect(controller.notes.first.isHold, isFalse);
    });

    test('dragging above the head does not give it a negative length', () {
      final controller = _controller();
      controller.toggleNote(0, 600);

      controller.resizeHold(controller.notes.first, 0);

      expect(controller.notes.first.length, 0);
    });

    test('a tap on the tail finds the note it belongs to', () {
      final controller = _controller();
      controller.toggleNote(0, 0);
      controller.resizeHold(controller.notes.first, 600);

      final found = controller.noteAt(0, 450, 20);
      expect(found, same(controller.notes.first));
    });
  });

  group('undo', () {
    test('takes back the last edit', () {
      final controller = _controller();

      controller.toggleNote(0, 0);
      controller.toggleNote(1, 150);
      expect(controller.notes, hasLength(2));

      controller.undo();
      expect(controller.notes, hasLength(1));

      controller.undo();
      expect(controller.notes, isEmpty);
    });

    test('redo puts it back', () {
      final controller = _controller();

      controller.toggleNote(0, 0);
      controller.undo();
      controller.redo();

      expect(controller.notes, hasLength(1));
    });

    test('a new edit clears what was undone', () {
      final controller = _controller();

      controller.toggleNote(0, 0);
      controller.undo();
      expect(controller.canRedo, isTrue);

      controller.toggleNote(1, 0);
      expect(controller.canRedo, isFalse);
    });

    test('there is nothing to undo to begin with', () {
      final controller = _controller();

      expect(controller.canUndo, isFalse);
      expect(controller.canRedo, isFalse);
      controller.undo();
      expect(controller.notes, isEmpty);
    });

    test('a hold resize is undoable', () {
      final controller = _controller();
      controller.toggleNote(0, 0);
      controller.resizeHold(controller.notes.first, 600);

      controller.undo();

      expect(controller.notes.first.isHold, isFalse);
    });
  });

  group('the selection', () {
    test('flipping sends notes to the other strumline', () {
      final controller = _controller();
      controller.toggleNote(1, 0);
      controller.toggleSelected(controller.notes.first);

      controller.flipSelection();

      expect(controller.notes.first.data, 5);

      controller.flipSelection();
      expect(controller.notes.first.data, 1);
    });

    test('shifting moves them along the grid', () {
      final controller = _controller();
      controller.toggleNote(0, 0);
      controller.toggleSelected(controller.notes.first);

      controller.shiftSelection(150);

      expect(controller.notes.first.time, closeTo(150, 0.001));
    });

    test('deleting takes out only what is selected', () {
      final controller = _controller();
      controller.toggleNote(0, 0);
      controller.toggleNote(1, 150);
      controller.toggleSelected(controller.notes.first);

      controller.removeSelection();

      expect(controller.notes, hasLength(1));
      expect(controller.notes.first.data, 1);
    });
  });

  group('difficulties', () {
    test('each one has its own notes', () {
      final controller = _controller();

      controller.toggleNote(0, 0);
      controller.setDifficulty('hard');

      expect(controller.notes, isEmpty);

      controller.setDifficulty('normal');
      expect(controller.notes, hasLength(1));
    });

    test('switching to one that does not exist yet makes it', () {
      final controller = _controller();

      controller.setDifficulty('nightmare');
      controller.toggleNote(0, 0);

      expect(controller.project.chart.notes['nightmare'], hasLength(1));
    });
  });

  group('event values', () {
    test('JSON is read as JSON', () {
      expect(ChartController.parseEventValue('{"anim": "hey"}'),
          {'anim': 'hey'});
      expect(ChartController.parseEventValue('1'), 1);
      expect(ChartController.parseEventValue('true'), true);
    });

    test('plain words stay words', () {
      // `bf` is a perfectly good event value and is not JSON.
      expect(ChartController.parseEventValue('bf'), 'bf');
      expect(ChartController.parseEventValue(''), isNull);
    });

    test('what cannot be parsed comes back as it was typed', () {
      expect(ChartController.parseEventValue('{oops'), '{oops');
    });
  });

  group('dirtiness', () {
    test('a fresh chart is clean', () {
      expect(_controller().isDirty, isFalse);
    });

    test('an edit marks it', () {
      final controller = _controller()..toggleNote(0, 0);
      expect(controller.isDirty, isTrue);
    });
  });
}
