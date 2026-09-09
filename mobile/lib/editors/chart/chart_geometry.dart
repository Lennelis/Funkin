import 'dart:ui';

/// Where things are on the grid.
///
/// The painter and the gestures have to agree exactly about which pixel is
/// which millisecond, so both ask this rather than each doing the arithmetic.
class ChartGeometry {
  const ChartGeometry({
    required this.size,
    required this.timeMs,
    required this.pixelsPerMs,
  });

  final Size size;

  /// The time under the playhead.
  final double timeMs;

  final double pixelsPerMs;

  /// The events column, down the left.
  static const double gutter = 44;

  /// How far down the screen the playhead sits. Not the middle: a charter is
  /// reading what is coming, so most of the screen is given to the song ahead
  /// of the line rather than behind it.
  static const double playheadFraction = 0.28;

  double get playheadY => size.height * playheadFraction;

  double get laneWidth => (size.width - gutter) / 8;

  /// The lane drawn in [column], left to right. The opponent has the left half
  /// and the player the right, which is the way round they appear in the game.
  static int laneForColumn(int column) =>
      column < 4 ? column + 4 : column - 4;

  static int columnForLane(int lane) => lane < 4 ? lane + 4 : lane - 4;

  double columnLeft(int column) => gutter + column * laneWidth;

  double yForTime(double milliseconds) =>
      playheadY + (milliseconds - timeMs) * pixelsPerMs;

  double timeForY(double y) => timeMs + (y - playheadY) / pixelsPerMs;

  /// The lane a horizontal position falls in, or null for the events column.
  int? laneForX(double x) {
    if (x < gutter) return null;

    final column = ((x - gutter) / laneWidth).floor();
    if (column < 0 || column > 7) return null;

    return laneForColumn(column);
  }

  Rect noteRect(double milliseconds, int lane) {
    final column = columnForLane(lane);
    final side = laneWidth * 0.74;
    final centreX = columnLeft(column) + laneWidth / 2;
    final centreY = yForTime(milliseconds);

    return Rect.fromCenter(
      center: Offset(centreX, centreY),
      width: side,
      height: side,
    );
  }

  /// The window of song time the screen covers, with a little either side so
  /// a hold that starts above the top still draws its tail.
  double get visibleStartMs => timeForY(0) - 1;
  double get visibleEndMs => timeForY(size.height) + 1;
}
