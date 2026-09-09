import 'package:flutter/material.dart';

/// The look, carried over from the tools site so the two feel like one set.
class FunkinColors {
  static const Color pink = Color(0xFFD5187A);
  static const Color ink = Color(0xFF14111F);
  static const Color panel = Color(0xFF1E1A2B);
  static const Color raised = Color(0xFF2A2440);
  static const Color line = Color(0xFF3A3355);
  static const Color text = Color(0xFFF2ECFF);
  static const Color muted = Color(0xFF9A90B8);

  /// The four arrows, in the game's own order and colours: left, down, up,
  /// right. A charter reads the lane by colour before they read anything else,
  /// so these have to be the ones they already know.
  static const List<Color> arrows = [
    Color(0xFFC24B99),
    Color(0xFF00FFFF),
    Color(0xFF12FA05),
    Color(0xFFF9393F),
  ];

  /// The opponent's half of the grid is tinted so the two sides are never
  /// confused at a glance.
  static const Color opponentLane = Color(0x14FFFFFF);
  static const Color playerLane = Color(0x0AD5187A);
}

ThemeData buildFunkinTheme() {
  final base = ThemeData.dark(useMaterial3: true);

  return base.copyWith(
    scaffoldBackgroundColor: FunkinColors.ink,
    colorScheme: base.colorScheme.copyWith(
      primary: FunkinColors.pink,
      secondary: FunkinColors.pink,
      surface: FunkinColors.panel,
      onSurface: FunkinColors.text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: FunkinColors.panel,
      foregroundColor: FunkinColors.text,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: const CardThemeData(
      color: FunkinColors.panel,
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
    dividerTheme: const DividerThemeData(color: FunkinColors.line, thickness: 1),
    listTileTheme: const ListTileThemeData(
      textColor: FunkinColors.text,
      iconColor: FunkinColors.muted,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: FunkinColors.pink,
        foregroundColor: Colors.white,
        // Thumbs are not mouse pointers. Everything tappable is at least this
        // tall, which is the smallest target that does not get missed.
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: FunkinColors.text,
        side: const BorderSide(color: FunkinColors.line),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: FunkinColors.raised,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: FunkinColors.raised,
      contentTextStyle: TextStyle(color: FunkinColors.text),
      behavior: SnackBarBehavior.floating,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: FunkinColors.pink,
        selectedForegroundColor: Colors.white,
        foregroundColor: FunkinColors.muted,
        side: const BorderSide(color: FunkinColors.line),
      ),
    ),
  );
}

/// The arrow shape for a lane, drawn rather than shipped as a sprite so it
/// stays sharp at whatever the grid is zoomed to.
Path arrowPath(Rect bounds, int direction) {
  final path = Path();
  final width = bounds.width;
  final height = bounds.height;

  // Drawn pointing up in a unit square, then turned. One shape, four lanes.
  final points = <Offset>[
    const Offset(0.5, 0.12),
    const Offset(0.88, 0.5),
    const Offset(0.66, 0.5),
    const Offset(0.66, 0.88),
    const Offset(0.34, 0.88),
    const Offset(0.34, 0.5),
    const Offset(0.12, 0.5),
  ];

  // 0 left, 1 down, 2 up, 3 right — quarter turns from the shape above.
  const turns = [1, 2, 0, 3];
  final quarter = turns[direction % 4];

  for (var index = 0; index < points.length; index++) {
    var point = points[index];

    for (var turn = 0; turn < quarter; turn++) {
      point = Offset(1 - point.dy, point.dx);
    }

    final position = Offset(
      bounds.left + point.dx * width,
      bounds.top + point.dy * height,
    );

    if (index == 0) {
      path.moveTo(position.dx, position.dy);
    } else {
      path.lineTo(position.dx, position.dy);
    }
  }

  path.close();
  return path;
}
