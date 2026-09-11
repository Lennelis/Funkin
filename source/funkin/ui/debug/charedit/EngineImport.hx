package funkin.ui.debug.charedit;

/**
 * Turning another engine's character into one this game can read.
 *
 * Psych Engine and Codename Engine describe a character with the same facts
 * this game does — a sheet, a list of animations, an offset for each — laid
 * out differently and named differently. Nothing here is a conversion in the
 * hard sense: it is the same character, read out of a different shape.
 *
 * Offsets come across as they are written. The two engines subtract them the
 * way this one does, but they scale and round in their own ways, so a
 * character that arrives standing slightly wrong is expected rather than
 * broken — and standing a character correctly is what this editor is for.
 */
class EngineImport
{
  /**
   * Read a Psych Engine character.
   *
   * @param text The contents of the character's `.json`.
   * @param id What to call it here.
   * @return This game's character file, or null if that was not one.
   */
  public static function fromPsych(text:String, id:String):Null<String>
  {
    var read:Dynamic = null;

    try
    {
      read = haxe.Json.parse(text);
    }
    catch (error)
    {
      return null;
    }

    if (read == null || read.animations == null) return null;

    var animations:Array<Dynamic> = cast read.animations;
    var built:Array<Dynamic> = [];

    for (entry in animations)
    {
      if (entry == null || entry.anim == null || entry.name == null) continue;

      built.push(
        {
          name: '' + entry.anim,
          prefix: '' + entry.name,
          frameRate: whole(entry.fps, 24),
          looped: yes(entry.loop, false),
          flipX: false,
          flipY: false,
          offsets: pair(entry.offsets),
          frameIndices: indices(entry.indices)
        });
    }

    if (built.length == 0) return null;

    // Psych turns antialiasing off for pixel characters and has no separate
    // word for it, so the one flag has to answer for both.
    var pixel:Bool = yes(read.no_antialiasing, false);

    return write(
      {
        name: id,
        assetPath: sheetPath(read.image),
        singTime: number(read.sing_duration, 8.0),
        flipX: yes(read.flip_x, false),
        isPixel: pixel,
        scale: number(read.scale, 1.0),
        offsets: pair(read.position),
        cameraOffsets: pair(read.camera_position),
        icon: read.healthicon == null ? id : '' + read.healthicon,
        animations: built
      });
  }

  /**
   * Read a Codename Engine character.
   *
   * Codename writes a character as XML rather than JSON, so this takes the
   * file either way round: what the menu offers is an engine, not a shape.
   *
   * @param text The contents of the character's `.xml`.
   * @param id What to call it here.
   * @return This game's character file, or null if that was not one.
   */
  public static function fromCodename(text:String, id:String):Null<String>
  {
    var root:Null<Xml> = null;

    try
    {
      for (element in Xml.parse(text).elements())
      {
        if (element.nodeName.toLowerCase() == 'character') root = element;
      }
    }
    catch (error)
    {
      return null;
    }

    if (root == null) return null;

    var built:Array<Dynamic> = [];

    for (element in root.elements())
    {
      if (element.nodeName.toLowerCase() != 'anim') continue;

      var name:Null<String> = attribute(element, 'name');
      var prefix:Null<String> = attribute(element, 'anim');

      if (name == null || prefix == null) continue;

      built.push(
        {
          name: name,
          prefix: prefix,
          frameRate: Std.int(numberOf(element, 'fps', 24)),
          looped: flagOf(element, 'loop', false),
          flipX: false,
          flipY: false,
          offsets: [numberOf(element, 'x', 0), numberOf(element, 'y', 0)],
          frameIndices: indices(attribute(element, 'indices'))
        });
    }

    if (built.length == 0) return null;

    return write(
      {
        name: id,
        assetPath: sheetPath(attribute(root, 'sprite')),
        singTime: numberOf(root, 'holdTime', 8.0),
        flipX: flagOf(root, 'flipX', false),
        // Codename says whether to smooth the character; this game says
        // whether it is pixel art, which is the same answer inverted.
        isPixel: !flagOf(root, 'antialiasing', true),
        scale: numberOf(root, 'scale', 1.0),
        offsets: [numberOf(root, 'x', 0), numberOf(root, 'y', 0)],
        cameraOffsets: [numberOf(root, 'camx', 0), numberOf(root, 'camy', 0)],
        icon: attribute(root, 'icon') ?? id,
        animations: built
      });
  }

  /**
   * The sheet a character file names, as this game would name it.
   *
   * Both engines point at a sheet by a path inside their own assets, and the
   * sheet itself arrives here separately and lands in the editor's own
   * folder, so only the last part of that path survives.
   */
  public static function sheetName(image:Null<String>):Null<String>
  {
    if (image == null || image == '') return null;

    return haxe.io.Path.withoutDirectory(StringTools.replace('' + image, '\\', '/'));
  }

  static function sheetPath(image:Null<String>):String
  {
    var sheet:Null<String> = sheetName(image);

    return sheet == null ? 'characters/unknown' : 'characters/$sheet';
  }

  /**
   * A character file, filled in around what the other engine had to say.
   */
  static function write(from:Dynamic):String
  {
    return haxe.Json.stringify({
      version: '1.0.0',
      name: from.name,
      renderType: 'sparrow',
      assetPath: from.assetPath,
      singTime: from.singTime,
      flipX: from.flipX,
      isPixel: from.isPixel,
      scale: from.scale,
      offsets: from.offsets,
      cameraOffsets: from.cameraOffsets,
      healthIcon:
        {
          id: from.icon,
          scale: 1.0,
          flipX: false,
          isPixel: from.isPixel,
          offsets: [0.0, 25.0]
        },
      animations: from.animations
    }, null, '  ');
  }

  // -- reading values that may be missing, or may be text -----------------

  static function attribute(element:Xml, name:String):Null<String>
  {
    // Attribute names are not spelled consistently between hand-written
    // character files, so the match ignores case.
    for (found in element.attributes())
      if (found.toLowerCase() == name.toLowerCase()) return element.get(found);

    return null;
  }

  static function numberOf(element:Xml, name:String, fallback:Float):Float
  {
    return number(attribute(element, name), fallback);
  }

  static function flagOf(element:Xml, name:String, fallback:Bool):Bool
  {
    return yes(attribute(element, name), fallback);
  }

  static function number(value:Dynamic, fallback:Float):Float
  {
    if (value == null) return fallback;

    if (Std.isOfType(value, String))
    {
      var parsed:Null<Float> = Std.parseFloat(value);
      return (parsed == null || Math.isNaN(parsed)) ? fallback : parsed;
    }

    var asFloat:Null<Float> = cast value;
    return asFloat == null ? fallback : asFloat;
  }

  static function whole(value:Dynamic, fallback:Int):Int
  {
    return Std.int(number(value, fallback));
  }

  static function yes(value:Dynamic, fallback:Bool):Bool
  {
    if (value == null) return fallback;

    if (Std.isOfType(value, String))
    {
      var said:String = StringTools.trim(('' + value).toLowerCase());
      return said == 'true' || said == '1' || said == 'yes';
    }

    return value == true;
  }

  /**
   * A pair of numbers, whichever way round the file wrote it.
   */
  static function pair(value:Dynamic):Array<Float>
  {
    if (value == null || !Std.isOfType(value, Array)) return [0.0, 0.0];

    var given:Array<Dynamic> = cast value;

    return [number(given[0], 0.0), number(given[1], 0.0)];
  }

  /**
   * The frames an animation uses, from a list or from a line of text.
   */
  static function indices(value:Dynamic):Array<Int>
  {
    if (value == null) return [];

    if (Std.isOfType(value, String))
    {
      var found:Array<Int> = [];

      for (piece in ('' + value).split(','))
      {
        var parsed:Null<Int> = Std.parseInt(StringTools.trim(piece));
        if (parsed != null) found.push(parsed);
      }

      return found;
    }

    if (!Std.isOfType(value, Array)) return [];

    var given:Array<Dynamic> = cast value;

    return [for (each in given) whole(each, 0)];
  }
}
