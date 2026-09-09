import 'json_extras.dart';

/// A character file — `data/characters/<id>.json`.
///
/// Follows `source/funkin/data/character/CharacterData.hx`. Most fields are
/// optional and the game fills them in, so anything the file left out stays
/// left out on write rather than being written as the default.
class CharacterData with JsonExtras {
  static const String currentVersion = '1.0.0';

  static const Set<String> _claimed = {
    'version', 'name', 'renderType', 'assetPath', 'scale', 'offsets',
    'cameraOffsets', 'isPixel', 'danceEvery', 'singTime', 'animations',
    'startingAnimation', 'flipX',
  };

  String version;
  String name;
  String renderType;
  String assetPath;
  double? scale;
  List<double>? offsets;
  List<double>? cameraOffsets;
  bool? isPixel;
  double? danceEvery;
  double? singTime;
  List<AnimationData> animations;
  String? startingAnimation;
  bool? flipX;

  CharacterData({
    this.version = currentVersion,
    this.name = 'Unnamed',
    this.renderType = 'sparrow',
    this.assetPath = '',
    this.scale,
    this.offsets,
    this.cameraOffsets,
    this.isPixel,
    this.danceEvery,
    this.singTime,
    List<AnimationData>? animations,
    this.startingAnimation,
    this.flipX,
  }) : animations = animations ?? [];

  factory CharacterData.fromJson(Map<String, dynamic> json) {
    final character = CharacterData(
      version: '${json['version'] ?? currentVersion}',
      name: '${json['name'] ?? 'Unnamed'}',
      renderType: '${json['renderType'] ?? 'sparrow'}',
      assetPath: '${json['assetPath'] ?? ''}',
      scale: json['scale'] == null ? null : asDouble(json['scale']),
      offsets: _numbers(json['offsets']),
      cameraOffsets: _numbers(json['cameraOffsets']),
      isPixel: json['isPixel'] as bool?,
      danceEvery: json['danceEvery'] == null ? null : asDouble(json['danceEvery']),
      singTime: json['singTime'] == null ? null : asDouble(json['singTime']),
      animations: (json['animations'] as List?)
              ?.whereType<Map>()
              .map((item) => AnimationData.fromJson(item.cast<String, dynamic>()))
              .toList() ??
          <AnimationData>[],
      startingAnimation: json['startingAnimation'] as String?,
      flipX: json['flipX'] as bool?,
    );

    character.keepExtras(json, _claimed);
    return character;
  }

  Map<String, dynamic> toJson() => withExtras(pruneNulls(<String, dynamic>{
        'version': version,
        'name': name,
        'renderType': renderType,
        'assetPath': assetPath,
        'scale': scale == null ? null : compactNumber(scale!),
        'offsets': offsets?.map(compactNumber).toList(),
        'cameraOffsets': cameraOffsets?.map(compactNumber).toList(),
        'isPixel': isPixel,
        'danceEvery': danceEvery == null ? null : compactNumber(danceEvery!),
        'singTime': singTime == null ? null : compactNumber(singTime!),
        'animations': animations.map((animation) => animation.toJson()).toList(),
        'startingAnimation': startingAnimation,
        'flipX': flipX,
      }));

  /// The image this character is drawn from, as a path under the folder rather
  /// than the game's library-prefixed form. `shared:characters/bf` is a file
  /// called `bf` in `images/characters` of the shared library, and inside a
  /// single folder that is just `characters/bf`.
  static String stripLibrary(String path) {
    final colon = path.indexOf(':');
    return colon < 0 ? path : path.substring(colon + 1);
  }

  static List<double>? _numbers(dynamic value) {
    if (value is! List) return null;
    return value.map((item) => asDouble(item)).toList();
  }
}

/// One animation: which frames it uses, and how the character sits while it
/// plays.
class AnimationData with JsonExtras {
  static const Set<String> _claimed = {
    'name', 'prefix', 'assetPath', 'offsets', 'looped', 'flipX', 'flipY',
    'frameRate', 'frameIndices',
  };

  String name;
  String prefix;
  String? assetPath;
  List<double>? offsets;
  bool? looped;
  bool? flipX;
  bool? flipY;
  int? frameRate;
  List<int>? frameIndices;

  AnimationData({
    this.name = '',
    this.prefix = '',
    this.assetPath,
    this.offsets,
    this.looped,
    this.flipX,
    this.flipY,
    this.frameRate,
    this.frameIndices,
  });

  factory AnimationData.fromJson(Map<String, dynamic> json) {
    final animation = AnimationData(
      name: '${json['name'] ?? ''}',
      prefix: '${json['prefix'] ?? ''}',
      assetPath: json['assetPath'] as String?,
      offsets: CharacterData._numbers(json['offsets']),
      looped: json['looped'] as bool?,
      flipX: json['flipX'] as bool?,
      flipY: json['flipY'] as bool?,
      frameRate: json['frameRate'] == null ? null : asInt(json['frameRate']),
      frameIndices:
          (json['frameIndices'] as List?)?.map((item) => asInt(item)).toList(),
    );

    animation.keepExtras(json, _claimed);
    return animation;
  }

  Map<String, dynamic> toJson() => withExtras(pruneNulls(<String, dynamic>{
        'name': name,
        'prefix': prefix,
        'assetPath': assetPath,
        'offsets': offsets?.map(compactNumber).toList(),
        'looped': looped,
        'flipX': flipX,
        'flipY': flipY,
        'frameRate': frameRate,
        'frameIndices': frameIndices,
      }));

  double get offsetX => offsets != null && offsets!.isNotEmpty ? offsets![0] : 0;
  double get offsetY => offsets != null && offsets!.length > 1 ? offsets![1] : 0;

  void setOffsets(double x, double y) {
    // An animation with no offsets at all is different from one offset by
    // nothing, so this only starts writing them once they are moved.
    if (x == 0 && y == 0 && offsets == null) return;
    offsets = [x, y];
  }
}
