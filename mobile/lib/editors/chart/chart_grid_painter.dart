import 'package:flutter/material.dart';

import '../../data/song_chart.dart';
import '../../services/conductor.dart';
import '../../theme/funkin_theme.dart';
import 'chart_geometry.dart';

/// Draws the grid, the notes and the playhead.
///
/// Only what is on screen is drawn. A long song holds a few thousand notes and
/// painting all of them every frame is the difference between a grid that
/// scrolls and one that stutters.
class ChartGridPainter extends CustomPainter {
  ChartGridPainter({
    required this.geometry,
    required this.conductor,
    required this.notes,
    required this.events,
    required this.selection,
    required this.snap,
    this.dragPreview,
  });

  final ChartGeometry geometry;
  final Conductor conductor;
  final List<SongNoteData> notes;
  final List<SongEventData> events;
  final Set<SongNoteData> selection;
  final int snap;

  /// The hold being dragged out right now, drawn even though the note it
  /// belongs to has not been given the new length yet.
  final ({SongNoteData note, double endMs})? dragPreview;

  @override
  void paint(Canvas canvas, Size size) {
    _paintLanes(canvas, size);
    _paintGridLines(canvas, size);
    _paintEvents(canvas);
    _paintNotes(canvas);
    _paintPlayhead(canvas, size);
  }

  void _paintLanes(Canvas canvas, Size size) {
    final gutterPaint = Paint()..color = FunkinColors.panel;
    canvas.drawRect(
        Rect.fromLTWH(0, 0, ChartGeometry.gutter, size.height), gutterPaint);

    for (var column = 0; column < 8; column++) {
      final lane = ChartGeometry.laneForColumn(column);
      final paint = Paint()
        ..color = lane >= 4 ? FunkinColors.opponentLane : FunkinColors.playerLane;

      canvas.drawRect(
        Rect.fromLTWH(
            geometry.columnLeft(column), 0, geometry.laneWidth, size.height),
        paint,
      );
    }

    // The seam between the two strumlines, which is the one boundary that
    // matters when you are placing notes quickly.
    final seam = Paint()
      ..color = FunkinColors.pink.withValues(alpha: 0.55)
      ..strokeWidth = 2;

    final seamX = geometry.columnLeft(4);
    canvas.drawLine(Offset(seamX, 0), Offset(seamX, size.height), seam);
  }

  void _paintGridLines(Canvas canvas, Size size) {
    final lines = conductor.gridLines(
      geometry.visibleStartMs,
      geometry.visibleEndMs,
      snap,
    );

    final snapPaint = Paint()
      ..color = FunkinColors.line.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    final beatPaint = Paint()
      ..color = FunkinColors.line.withValues(alpha: 0.9)
      ..strokeWidth = 1;
    final measurePaint = Paint()
      ..color = FunkinColors.muted.withValues(alpha: 0.8)
      ..strokeWidth = 2;

    for (final line in lines) {
      final y = geometry.yForTime(line.timeMs);
      if (y < -2 || y > size.height + 2) continue;

      final paint = switch (line.kind) {
        GridLineKind.measure => measurePaint,
        GridLineKind.beat => beatPaint,
        GridLineKind.snap => snapPaint,
      };

      canvas.drawLine(
          Offset(ChartGeometry.gutter, y), Offset(size.width, y), paint);

      if (line.kind == GridLineKind.measure) {
        _paintMeasureNumber(canvas, y, line.timeMs);
      }
    }
  }

  void _paintMeasureNumber(Canvas canvas, double y, double timeMs) {
    final painter = TextPainter(
      text: TextSpan(
        text: '${conductor.measureAtTime(timeMs) + 1}',
        style: const TextStyle(color: FunkinColors.muted, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    painter.paint(canvas, Offset(4, y + 2));
  }

  void _paintEvents(Canvas canvas) {
    final paint = Paint()..color = const Color(0xFFFFC24B);

    for (final event in events) {
      if (event.time < geometry.visibleStartMs) continue;
      if (event.time > geometry.visibleEndMs) break;

      final y = geometry.yForTime(event.time);
      final centre = Offset(ChartGeometry.gutter - 14, y);

      // A diamond, so it never reads as a note that wandered out of its lane.
      final path = Path()
        ..moveTo(centre.dx, centre.dy - 7)
        ..lineTo(centre.dx + 7, centre.dy)
        ..lineTo(centre.dx, centre.dy + 7)
        ..lineTo(centre.dx - 7, centre.dy)
        ..close();

      canvas.drawPath(path, paint);
    }
  }

  void _paintNotes(Canvas canvas) {
    // Tails first, so a note sitting on top of another one's tail still reads
    // as the head it is.
    for (final note in notes) {
      if (note.endTime < geometry.visibleStartMs) continue;
      if (note.time > geometry.visibleEndMs) break;

      final length = dragPreview?.note == note
          ? (dragPreview!.endMs - note.time).clamp(0.0, double.infinity)
          : note.length;

      if (length > 0) _paintTail(canvas, note, length);
    }

    for (final note in notes) {
      if (note.endTime < geometry.visibleStartMs) continue;
      if (note.time > geometry.visibleEndMs) break;

      _paintHead(canvas, note);
    }
  }

  void _paintTail(Canvas canvas, SongNoteData note, double length) {
    final rect = geometry.noteRect(note.time, note.data);
    final endY = geometry.yForTime(note.time + length);

    final paint = Paint()
      ..color = FunkinColors.arrows[note.direction].withValues(alpha: 0.55);

    final width = rect.width * 0.36;
    final tail = RRect.fromRectAndRadius(
      Rect.fromLTRB(
        rect.center.dx - width / 2,
        rect.center.dy,
        rect.center.dx + width / 2,
        endY,
      ),
      Radius.circular(width / 2),
    );

    canvas.drawRRect(tail, paint);
  }

  void _paintHead(Canvas canvas, SongNoteData note) {
    final rect = geometry.noteRect(note.time, note.data);
    final colour = FunkinColors.arrows[note.direction];

    final fill = Paint()..color = colour;
    canvas.drawPath(arrowPath(rect, note.direction), fill);

    // A note kind is a mod's own thing, and the only honest way to show one
    // without its sprites is to mark that it is not an ordinary note.
    if (note.kind != null) {
      final marker = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(rect.center, rect.width * 0.42, marker);
    }

    if (selection.contains(note)) {
      final outline = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(3), const Radius.circular(6)),
        outline,
      );
    }
  }

  void _paintPlayhead(Canvas canvas, Size size) {
    final y = geometry.playheadY;

    final paint = Paint()
      ..color = FunkinColors.pink
      ..strokeWidth = 2.5;

    canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);

    // A wedge at each end, so the line is still findable against a screenful
    // of pink notes.
    final wedge = Paint()..color = FunkinColors.pink;
    canvas.drawPath(
      Path()
        ..moveTo(0, y - 7)
        ..lineTo(9, y)
        ..lineTo(0, y + 7)
        ..close(),
      wedge,
    );
  }

  @override
  bool shouldRepaint(ChartGridPainter old) =>
      old.geometry.timeMs != geometry.timeMs ||
      old.geometry.pixelsPerMs != geometry.pixelsPerMs ||
      old.geometry.size != geometry.size ||
      old.snap != snap ||
      old.notes != notes ||
      old.events != events ||
      old.dragPreview != dragPreview ||
      !setEquals(old.selection, selection);

  static bool setEquals(Set<SongNoteData> a, Set<SongNoteData> b) {
    if (identical(a, b)) return a.length == b.length;
    if (a.length != b.length) return false;
    return a.every(b.contains);
  }
}
