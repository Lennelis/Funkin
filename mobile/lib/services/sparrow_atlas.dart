import 'package:xml/xml.dart';

/// One frame in a sparrow atlas.
///
/// [source] is where the frame sits in the sheet. The `frame*` fields describe
/// the space that was trimmed off it when the sheet was packed — leaving them
/// out is why a character preview drifts around as its animation plays, so
/// they are kept and applied when drawing.
class AtlasFrame {
  const AtlasFrame({
    required this.name,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.offsetX = 0,
    this.offsetY = 0,
    this.originalWidth,
    this.originalHeight,
  });

  final String name;
  final double x;
  final double y;
  final double width;
  final double height;
  final double offsetX;
  final double offsetY;
  final double? originalWidth;
  final double? originalHeight;

  double get frameWidth => originalWidth ?? width;
  double get frameHeight => originalHeight ?? height;
}

/// A Sparrow v2 texture atlas — the `.xml` next to a character's `.png`.
///
/// Frames are named `<prefix>0000`, and an animation is every frame whose name
/// starts with its prefix, in order. That is the whole of the convention, and
/// it is what the game itself goes by.
class SparrowAtlas {
  SparrowAtlas(this.frames);

  final List<AtlasFrame> frames;

  factory SparrowAtlas.parse(String xml) {
    final document = XmlDocument.parse(xml);
    final frames = <AtlasFrame>[];

    for (final element in document.findAllElements('SubTexture')) {
      final name = element.getAttribute('name');
      if (name == null) continue;

      frames.add(AtlasFrame(
        name: name,
        x: _number(element, 'x') ?? 0,
        y: _number(element, 'y') ?? 0,
        width: _number(element, 'width') ?? 0,
        height: _number(element, 'height') ?? 0,
        offsetX: _number(element, 'frameX') ?? 0,
        offsetY: _number(element, 'frameY') ?? 0,
        originalWidth: _number(element, 'frameWidth'),
        originalHeight: _number(element, 'frameHeight'),
      ));
    }

    return SparrowAtlas(frames);
  }

  /// Every frame belonging to [prefix], in the order they play.
  List<AtlasFrame> framesFor(String prefix) {
    if (prefix.isEmpty) return const [];

    final matching =
        frames.where((frame) => frame.name.startsWith(prefix)).toList();

    // Packers write the frame number as a fixed-width suffix, so sorting the
    // names sorts the frames. Doing it by name rather than by document order
    // survives a sheet that was repacked.
    matching.sort((a, b) => a.name.compareTo(b.name));
    return matching;
  }

  /// The prefixes in the sheet, worked out by taking the trailing frame number
  /// off each name. Useful when a character file names an animation the sheet
  /// does not have, which is the usual reason one shows up blank.
  List<String> get prefixes {
    final found = <String>{};

    for (final frame in frames) {
      found.add(frame.name.replaceFirst(RegExp(r'\d+$'), '').trimRight());
    }

    return found.toList()..sort();
  }

  static double? _number(XmlElement element, String attribute) {
    final value = element.getAttribute(attribute);
    if (value == null) return null;
    return double.tryParse(value);
  }
}
