package funkin.ui.debug.charedit;

import funkin.data.character.CharacterData.CharacterDataParser;
import funkin.util.FileUtil;
import funkin.util.SortUtil;
import haxe.io.Path;

using StringTools;

/**
 * Reading a Sparrow sprite sheet and writing a character out of it.
 *
 * A sheet knows what pictures it holds and nothing about what they are for:
 * the frames are named by whoever drew them, in whatever scheme they were
 * working in, and the game asks for `idle` and `singLEFT` and the rest by
 * those names. Something has to sit between the two, and on a phone it
 * cannot be a person typing the mapping in by hand.
 *
 * So this guesses. Each frame name has its number taken off to leave a
 * prefix, the prefixes are matched against what the game asks for by the
 * words people actually use for them, and everything that goes unmatched is
 * kept anyway under its own name, so a sheet never silently loses half of
 * itself to a guess that did not come off.
 */
class SpriteSheetImport
{
  /**
   * What the game asks every character for, and the words a sheet is likely
   * to spell each one with.
   *
   * In order: the earlier a word appears, the more sure a match on it is. A
   * sheet saying `singLEFT` means it; a sheet merely containing `left`
   * somewhere might be talking about anything.
   */
  static final WANTED:Array<WantedAnimation> = [
    {name: 'idle', hints: ['idledance', 'idle', 'dance']},
    {name: 'singLEFT', hints: ['singleft', 'noteleft', 'left']},
    {name: 'singDOWN', hints: ['singdown', 'notedown', 'down']},
    {name: 'singUP', hints: ['singup', 'noteup', 'up']},
    {name: 'singRIGHT', hints: ['singright', 'noteright', 'right']}
  ];

  /**
   * Words that mean a frame is a variant of an animation rather than the
   * animation itself, so that `singUP` does not get handed the miss frames
   * when the plain ones are sitting right there.
   */
  static final ASIDES:Array<String> = ['miss', 'hold', 'loop', 'dead', 'death', 'lose'];

  /**
   * Every sheet in a folder that has both halves of itself.
   *
   * A `.png` with no `.xml` beside it is a picture, not a sprite sheet, and
   * would only fail later with less to say about why.
   */
  public static function listSheets(dir:String):Array<String>
  {
    var found:Array<String> = [];

    #if sys
    if (!FileUtil.directoryExists(dir)) return found;

    try
    {
      for (entry in FileUtil.readDir(dir))
      {
        if (Path.extension(entry).toLowerCase() != 'png') continue;

        var base:String = Path.withoutExtension(entry);
        if (!FileUtil.fileExists(Path.join([dir, '$base.xml']))) continue;

        found.push(base);
      }
    }
    catch (error)
    {
      // An unreadable folder lists as an empty one; the caller has a status
      // line to put that on and nothing useful to do about it either way.
    }
    #end

    found.sort(SortUtil.alphabetically);

    return found;
  }

  /**
   * The distinct frame prefixes in a Sparrow sheet, in the order they first
   * appear, which is the order the sheet was drawn in.
   */
  public static function readPrefixes(xmlPath:String):Array<String>
  {
    var prefixes:Array<String> = [];

    #if sys
    var raw:String = null;

    try
    {
      raw = FileUtil.readStringFromPath(xmlPath);
    }
    catch (error)
    {
      return prefixes;
    }

    if (raw == null || raw.trim() == '') return prefixes;

    var document:Xml = null;

    try
    {
      document = Xml.parse(raw);
    }
    catch (error)
    {
      return prefixes;
    }

    var seen:Map<String, Bool> = new Map<String, Bool>();

    for (atlas in document.elementsNamed('TextureAtlas'))
    {
      for (frame in atlas.elementsNamed('SubTexture'))
      {
        var name:Null<String> = frame.get('name');
        if (name == null) continue;

        var prefix:String = withoutFrameNumber(name);
        if (prefix == '' || seen.exists(prefix)) continue;

        seen.set(prefix, true);
        prefixes.push(prefix);
      }
    }
    #end

    return prefixes;
  }

  /**
   * A character file for a sheet, as text ready to be written.
   *
   * Written rather than built as data on purpose: it goes back through the
   * game's own parser on the next asset reload, which is what decides
   * whether a character is valid, so there is no second opinion to keep in
   * step with this one.
   */
  public static function buildCharacterJson(id:String, name:String, assetPath:String, prefixes:Array<String>):String
  {
    var animations:Array<Dynamic> = [];
    var claimed:Map<String, Bool> = new Map<String, Bool>();

    for (wanted in WANTED)
    {
      var prefix:Null<String> = bestMatch(prefixes, wanted.hints);
      if (prefix == null) continue;

      claimed.set(prefix, true);
      animations.push({name: wanted.name, prefix: prefix, offsets: [0, 0]});
    }

    // Whatever the guessing did not want. Under its own name, so a sheet
    // full of extras arrives with all of them there to be looked at rather
    // than quietly reduced to the five the game insists on.
    var used:Map<String, Bool> = new Map<String, Bool>();
    for (wanted in WANTED)
      used.set(wanted.name, true);

    for (prefix in prefixes)
    {
      if (claimed.exists(prefix)) continue;

      var animationName:String = uniqueName(asName(prefix), used);
      if (animationName == '') continue;

      used.set(animationName, true);
      animations.push({name: animationName, prefix: prefix, offsets: [0, 0]});
    }

    return haxe.Json.stringify({
      version: CharacterDataParser.CHARACTER_DATA_VERSION,
      name: name,
      renderType: 'sparrow',
      assetPath: assetPath,
      scale: 1.0,
      danceEvery: 1.0,
      singTime: 8.0,
      flipX: false,
      isPixel: false,
      offsets: [0, 0],
      cameraOffsets: [0, 0],
      startingAnimation: 'idle',
      healthIcon: {id: 'face', flipX: false, isPixel: false},
      animations: animations
    }, null, '  ');
  }

  /**
   * An id no character already has.
   */
  public static function uniqueId(sheetName:String, taken:Array<String>):String
  {
    var base:String = asId(sheetName);
    if (base == '') base = 'character';

    var id:String = base;
    var attempt:Int = 2;

    while (taken.indexOf(id) != -1)
    {
      id = '$base-$attempt';
      attempt++;
    }

    return id;
  }

  /**
   * Which prefix a wanted animation should use, or null if the sheet has
   * nothing that looks like it.
   */
  static function bestMatch(prefixes:Array<String>, hints:Array<String>):Null<String>
  {
    var best:Null<String> = null;
    var bestScore:Int = -1;

    for (prefix in prefixes)
    {
      var flattened:String = flatten(prefix);

      for (index in 0...hints.length)
      {
        if (flattened.indexOf(hints[index]) == -1) continue;

        // Earlier hints are surer, and a frame that also says "miss" or
        // "hold" is a variant of the thing rather than the thing.
        var score:Int = (hints.length - index) * 10;
        if (isAside(flattened)) score -= 5;

        // Two names both saying "idle" and nothing else to choose between
        // them: the plainer one. A sheet with "Senpai Idle" and "Angry
        // Senpai Idle" in it means the first by "idle".
        var plainer:Bool = best != null && flattened.length < flatten(best).length;

        if (score > bestScore || (score == bestScore && plainer))
        {
          bestScore = score;
          best = prefix;
        }

        break;
      }
    }

    return best;
  }

  static function isAside(flattened:String):Bool
  {
    for (aside in ASIDES)
      if (flattened.indexOf(aside) != -1) return true;

    return false;
  }

  /**
   * A frame name with its number taken off, so that `BF NOTE LEFT0003` and
   * `BF NOTE LEFT0004` are recognisably the same animation.
   */
  static function withoutFrameNumber(name:String):String
  {
    var end:Int = name.length;

    while (end > 0)
    {
      var code:Int = name.fastCodeAt(end - 1);
      if (code < '0'.code || code > '9'.code) break;
      end--;
    }

    // All digits and nothing else is a number, not a name.
    if (end == 0) return '';

    return name.substr(0, end).rtrim();
  }

  /**
   * Only the letters and digits, in lower case, so that two spellings of the
   * same word can be compared.
   */
  static function flatten(value:String):String
  {
    var out:StringBuf = new StringBuf();

    for (index in 0...value.length)
    {
      var code:Int = value.fastCodeAt(index);
      if (isLetterOrDigit(code)) out.addChar(lower(code));
    }

    return out.toString();
  }

  /**
   * A prefix as an animation name: readable, and nothing in it that would
   * need quoting.
   */
  static function asName(prefix:String):String
  {
    var out:StringBuf = new StringBuf();

    for (index in 0...prefix.length)
    {
      var code:Int = prefix.fastCodeAt(index);
      if (isLetterOrDigit(code)) out.addChar(code);
    }

    return out.toString();
  }

  static function asId(value:String):String
  {
    var out:StringBuf = new StringBuf();
    var lastWasDash:Bool = true;

    for (index in 0...value.length)
    {
      var code:Int = value.fastCodeAt(index);

      if (isLetterOrDigit(code))
      {
        out.addChar(lower(code));
        lastWasDash = false;
      }
      else if (!lastWasDash)
      {
        out.addChar('-'.code);
        lastWasDash = true;
      }
    }

    var id:String = out.toString();
    while (id.endsWith('-'))
      id = id.substr(0, id.length - 1);

    return id;
  }

  static function uniqueName(name:String, taken:Map<String, Bool>):String
  {
    if (name == '') return '';
    if (!taken.exists(name)) return name;

    var attempt:Int = 2;
    while (taken.exists('$name$attempt'))
      attempt++;

    return '$name$attempt';
  }

  static inline function isLetterOrDigit(code:Int):Bool
  {
    return (code >= 'a'.code && code <= 'z'.code) || (code >= 'A'.code && code <= 'Z'.code) || (code >= '0'.code && code <= '9'.code);
  }

  static inline function lower(code:Int):Int
  {
    return (code >= 'A'.code && code <= 'Z'.code) ? code + 32 : code;
  }
}

typedef WantedAnimation =
{
  var name:String;
  var hints:Array<String>;
}
