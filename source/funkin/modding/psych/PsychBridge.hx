package funkin.modding.psych;

#if FEATURE_PSYCH_LUA
import funkin.Conductor;
import funkin.Highscore;
import funkin.play.PlayState;

/**
 * Turns the names a Psych script uses into the things V-Slice actually has.
 *
 * Almost every Psych mod is written in terms of `getProperty` and `setProperty` against a
 * dotted path - `setProperty('boyfriend.x', 100)`, `getProperty('health')`. So this one
 * lookup carries more mods than any number of individually ported functions would: get
 * the names right and a large amount of existing work simply runs.
 *
 * Most names need no translation, because both engines are FlxSprites underneath and a
 * sprite's `x` is a sprite's `x`. The ones that do are the handful of objects Psych keeps
 * on PlayState and V-Slice keeps somewhere else - the characters, mostly, which live on
 * the stage here.
 */
class PsychBridge
{
  /**
   * Objects created by scripts, by the tag they were made with.
   * Psych addresses these exactly like engine objects, so they are looked up first.
   */
  public static var objects:Map<String, Dynamic> = new Map<String, Dynamic>();

  /**
   * The free-form variable bag Psych scripts share through `setVar`/`getVar`.
   */
  public static var variables:Map<String, Dynamic> = new Map<String, Dynamic>();

  /**
   * Clears everything a song's scripts put here. Called when the scripts go away.
   */
  public static function reset():Void
  {
    objects.clear();
    variables.clear();
  }

  /**
   * Resolves a dotted path and reads the last field.
   *
   * `getProperty('boyfriend.scale.x')` walks boyfriend, then scale, then reads x.
   */
  public static function getProperty(path:String):Dynamic
  {
    var parts:Array<String> = path.split('.');
    var last:String = parts.pop();
    var target:Dynamic = resolve(parts);

    if (target == null) return null;

    return readField(target, last);
  }

  /**
   * Resolves a dotted path and writes the last field.
   * @return Whether anything was written.
   */
  public static function setProperty(path:String, value:Dynamic):Bool
  {
    var parts:Array<String> = path.split('.');
    var last:String = parts.pop();
    var target:Dynamic = resolve(parts);

    if (target == null) return false;

    try
    {
      Reflect.setProperty(target, last, value);
      return true;
    }
    catch (e:Dynamic)
    {
      return false;
    }
  }

  /**
   * Reads a static field off a class named the way Psych names it.
   * Psych paths are its own package layout, so a few are remapped to their counterparts
   * here; anything else is tried as written, which covers scripts reaching into Flixel.
   */
  public static function getClassProperty(className:String, field:String):Dynamic
  {
    var target:Dynamic = resolveClassTarget(className);
    if (target == null) return null;

    return readField(target, field);
  }

  public static function setClassProperty(className:String, field:String, value:Dynamic):Bool
  {
    var target:Dynamic = resolveClassTarget(className);
    if (target == null) return false;

    try
    {
      Reflect.setProperty(target, field, value);
      return true;
    }
    catch (e:Dynamic)
    {
      return false;
    }
  }

  /**
   * The object a bare name refers to.
   *
   * Order matters: a script's own object wins over an engine one, which is what lets a
   * mod make a sprite called `dad` without it fighting the character.
   */
  public static function resolveObject(name:String):Dynamic
  {
    if (objects.exists(name)) return objects.get(name);
    if (variables.exists(name)) return variables.get(name);

    var game:Null<PlayState> = PlayState.instance;
    if (game == null) return null;

    var stage = game.currentStage;

    return switch (name)
    {
      // The characters. Psych keeps these on PlayState; here they belong to the stage,
      // which is the single biggest difference a script will run into.
      case 'boyfriend' | 'bf' | 'player': stage == null ? null : stage.getBoyfriend();
      case 'dad' | 'opponent': stage == null ? null : stage.getDad();
      case 'gf' | 'girlfriend': stage == null ? null : stage.getGirlfriend();

      // Cameras. Psych's third camera is for things drawn over everything, which is what
      // V-Slice uses the cutscene camera for.
      case 'camGame': game.camGame;
      case 'camHUD': game.camHUD;
      case 'camOther': game.camCutscene;

      case 'playerStrums': game.playerStrumline;
      case 'opponentStrums': game.opponentStrumline;

      case 'healthBar': game.healthBar;
      case 'healthBarBG': game.healthBarBG;
      case 'iconP1': game.iconP1;
      case 'iconP2': game.iconP2;

      case 'vocals': game.vocals;
      case 'game' | 'instance': game;

      // Anything else is looked for on PlayState itself, which is where the bulk of the
      // names live and where they mostly already match.
      default: readField(game, name);
    }
  }

  //
  // INTERNALS
  //

  static function resolve(parts:Array<String>):Dynamic
  {
    var game:Null<PlayState> = PlayState.instance;

    // No path at all means the property is on PlayState: `getProperty('health')`.
    if (parts.length == 0) return game;

    var target:Dynamic = resolveObject(parts[0]);

    for (i in 1...parts.length)
    {
      if (target == null) return null;
      target = readField(target, parts[i]);
    }

    return target;
  }

  static function readField(target:Dynamic, field:String):Dynamic
  {
    if (target == null) return null;

    try
    {
      var value:Dynamic = Reflect.getProperty(target, field);

      // Reflect.getProperty returns null both for "no such field" and for a field that is
      // null. Falling back to the plain field read catches the cases where a getter
      // exists but threw, which Reflect swallows.
      if (value == null && Reflect.hasField(target, field)) value = Reflect.field(target, field);

      return value;
    }
    catch (e:Dynamic)
    {
      return null;
    }
  }

  /**
   * What a Psych class path points at here.
   *
   * Usually a class, because Psych's statics are usually statics here too. The Conductor
   * is the exception worth calling out: Psych reads `Conductor.songPosition` as a static,
   * V-Slice keeps one Conductor object, and a script asking for the class would get a
   * class with no such field on it. Handing back the instance makes the same script work
   * unchanged, which is the whole point of this file.
   */
  static function resolveClassTarget(className:String):Dynamic
  {
    switch (className)
    {
      case 'backend.Conductor' | 'Conductor' | 'funkin.Conductor':
        return Conductor.instance;

      case 'backend.Highscore' | 'Highscore':
        return Highscore;

      default:
    }

    var mapped:String = switch (className)
    {
      case 'backend.ClientPrefs' | 'ClientPrefs': 'funkin.Preferences';
      case 'states.PlayState' | 'PlayState': 'funkin.play.PlayState';
      case 'objects.Character' | 'Character': 'funkin.play.character.BaseCharacter';
      default: className;
    }

    return Type.resolveClass(mapped);
  }
}
#end
