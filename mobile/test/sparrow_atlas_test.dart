import 'package:flutter_test/flutter_test.dart';
import 'package:funkin_editors/services/sparrow_atlas.dart';

/// Cut down from `shared/images/characters/BOYFRIEND.xml`, with the attribute
/// names and the frame-number convention left exactly as they are there.
const String _atlas = '''
<?xml version="1.0" encoding="utf-8"?>
<TextureAtlas imagePath="BOYFRIEND.png">
  <SubTexture name="BF idle dance0000" x="0" y="0" width="400" height="500" frameX="-10" frameY="-64" frameWidth="439" frameHeight="499" />
  <SubTexture name="BF idle dance0001" x="400" y="0" width="400" height="500" frameX="-10" frameY="-60" frameWidth="439" frameHeight="499" />
  <SubTexture name="BF idle dance0002" x="800" y="0" width="400" height="500" />
  <SubTexture name="BF NOTE LEFT0000" x="0" y="500" width="300" height="400" />
  <SubTexture name="BF NOTE LEFT MISS0000" x="300" y="500" width="300" height="400" />
</TextureAtlas>
''';

void main() {
  final atlas = SparrowAtlas.parse(_atlas);

  group('parsing', () {
    test('reads every frame', () {
      expect(atlas.frames, hasLength(5));
    });

    test('reads where a frame sits in the sheet', () {
      final frame = atlas.frames.first;

      expect(frame.x, 0);
      expect(frame.y, 0);
      expect(frame.width, 400);
      expect(frame.height, 500);
    });

    test('keeps the trim a packer took off', () {
      // Without these a character wanders about as its animation plays.
      final frame = atlas.frames.first;

      expect(frame.offsetX, -10);
      expect(frame.offsetY, -64);
      expect(frame.frameWidth, 439);
      expect(frame.frameHeight, 499);
    });

    test('an untrimmed frame is its own size', () {
      final frame = atlas.frames[2];

      expect(frame.offsetX, 0);
      expect(frame.frameWidth, 400);
      expect(frame.frameHeight, 500);
    });
  });

  group('finding an animation', () {
    test('takes every frame under the prefix, in order', () {
      final frames = atlas.framesFor('BF idle dance');

      expect(frames, hasLength(3));
      expect(frames.first.name, endsWith('0000'));
      expect(frames.last.name, endsWith('0002'));
    });

    test('a prefix that is not there finds nothing', () {
      expect(atlas.framesFor('BF hey'), isEmpty);
      expect(atlas.framesFor(''), isEmpty);
    });

    test('a longer prefix is not swallowed by a shorter one', () {
      // `BF NOTE LEFT` is a prefix of `BF NOTE LEFT MISS`, so asking for the
      // first does pick up the second — which is exactly why the game's own
      // sheets name the miss animation the way they do, and why the editor
      // shows the frame count rather than claiming the animation is fine.
      expect(atlas.framesFor('BF NOTE LEFT'), hasLength(2));
      expect(atlas.framesFor('BF NOTE LEFT MISS'), hasLength(1));
    });
  });

  group('listing what is in a sheet', () {
    test('names the prefixes with the frame numbers off', () {
      expect(atlas.prefixes,
          containsAll(['BF idle dance', 'BF NOTE LEFT', 'BF NOTE LEFT MISS']));
    });
  });
}
