package funkin.modding.psych;

#if FEATURE_PSYCH_LUA
import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.FlxSprite;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import funkin.Conductor;
import funkin.graphics.FunkinSprite;
import funkin.play.PlayState;

/**
 * The functions a Psych Engine Lua script can call.
 *
 * Psych's API is flat and enormous - a couple of hundred globals, added to over years of
 * releases. What is here is the part mods actually lean on: reading and writing
 * properties, making and animating sprites, cameras, and timers. A script that calls
 * something not yet ported gets a clear error naming the function rather than a silent
 * no-op, so it is obvious what is missing instead of mysterious.
 *
 * Every function is registered against each script's own interpreter, but they all act on
 * the one running `PlayState`, which is how Psych behaves - scripts are not sandboxed
 * from each other and mods rely on that.
 */
class PsychApi
{
  /**
   * Adds the whole API to a script's interpreter.
   */
  public static function register(script:PsychScript):Void
  {
    registerCore(script);
    registerProperties(script);
    registerObjects(script);
    registerCameras(script);
    registerTiming(script);
  }

  //
  // CORE
  //

  static function registerCore(script:PsychScript):Void
  {
    script.set('scriptName', script.path);
    script.set('modFolder', script.modId);

    // Psych scripts return these constants to say what should happen after a callback.
    script.set('Function_Stop', PsychScript.STOP);
    script.set('Function_Continue', PsychScript.CONTINUE);
    script.set('Function_StopLua', PsychScript.STOP_LUA);
    script.set('Function_StopHScript', PsychScript.STOP_HSCRIPT);
    script.set('Function_StopAll', PsychScript.STOP_ALL);

    script.addCallback('debugPrint', function(text:Dynamic, ?color:String):Void
    {
      trace('[PSYCHLUA] ${text}');
    });

    // Asks PsychScript which script is running rather than closing over `script`. The Lua
    // binding keys its callbacks by name alone, so every state shares one function object
    // per name - a closure over `script` here would close whichever file happened to load
    // last, whatever called it.
    script.addCallback('close', function():Void
    {
      if (PsychScript.current != null) PsychScript.current.stop();
    });

    script.addCallback('getSongPosition', function():Float
    {
      return Conductor.instance == null ? 0 : Conductor.instance.songPosition;
    });
  }

  //
  // PROPERTIES
  //

  static function registerProperties(script:PsychScript):Void
  {
    script.addCallback('getProperty', function(variable:String):Dynamic
    {
      return PsychBridge.getProperty(variable);
    });

    script.addCallback('setProperty', function(variable:String, value:Dynamic):Bool
    {
      return PsychBridge.setProperty(variable, value);
    });

    script.addCallback('getPropertyFromClass', function(className:String, variable:String):Dynamic
    {
      return PsychBridge.getClassProperty(className, variable);
    });

    script.addCallback('setPropertyFromClass', function(className:String, variable:String, value:Dynamic):Bool
    {
      return PsychBridge.setClassProperty(className, variable, value);
    });

    script.addCallback('getPropertyFromGroup', function(group:String, index:Int, variable:String):Dynamic
    {
      var member:Dynamic = memberOf(group, index);
      return member == null ? null : Reflect.getProperty(member, variable);
    });

    script.addCallback('setPropertyFromGroup', function(group:String, index:Int, variable:String, value:Dynamic):Bool
    {
      var member:Dynamic = memberOf(group, index);
      if (member == null) return false;

      Reflect.setProperty(member, variable, value);
      return true;
    });

    script.addCallback('setVar', function(name:String, value:Dynamic):Void
    {
      PsychBridge.variables.set(name, value);
    });

    script.addCallback('getVar', function(name:String):Dynamic
    {
      return PsychBridge.variables.get(name);
    });
  }

  //
  // OBJECTS
  //

  static function registerObjects(script:PsychScript):Void
  {
    script.addCallback('makeLuaSprite', function(tag:String, ?image:String, ?x:Float, ?y:Float):Void
    {
      var sprite:FunkinSprite = new FunkinSprite(x == null ? 0 : x, y == null ? 0 : y);
      if (image != null && image != '') sprite.loadTexture(image);

      PsychBridge.objects.set(tag, sprite);
    });

    script.addCallback('makeAnimatedLuaSprite', function(tag:String, image:String, ?x:Float, ?y:Float):Void
    {
      var sprite:FunkinSprite = new FunkinSprite(x == null ? 0 : x, y == null ? 0 : y);
      sprite.loadSparrow(image);

      PsychBridge.objects.set(tag, sprite);
    });

    script.addCallback('addAnimationByPrefix', function(tag:String, name:String, prefix:String, ?fps:Int, ?loop:Bool):Bool
    {
      var sprite:Dynamic = PsychBridge.resolveObject(tag);
      if (sprite == null || !Std.isOfType(sprite, FlxSprite)) return false;

      var casted:FlxSprite = cast sprite;
      casted.animation.addByPrefix(name, prefix, fps == null ? 24 : fps, loop == null ? true : loop);

      // Psych plays the first animation you add, so a sprite is never left blank.
      if (casted.animation.curAnim == null) casted.animation.play(name, true);

      return true;
    });

    script.addCallback('addAnimationByIndices', function(tag:String, name:String, prefix:String, indices:Dynamic, ?fps:Int, ?loop:Bool):Bool
    {
      var sprite:Dynamic = PsychBridge.resolveObject(tag);
      if (sprite == null || !Std.isOfType(sprite, FlxSprite)) return false;

      var frames:Array<Int> = [];
      if (Std.isOfType(indices, String))
      {
        for (piece in (cast indices : String).split(','))
          frames.push(Std.parseInt(StringTools.trim(piece)));
      }
      else if (Std.isOfType(indices, Array))
      {
        for (piece in (cast indices : Array<Dynamic>))
          frames.push(Std.int(piece));
      }

      var casted:FlxSprite = cast sprite;
      casted.animation.addByIndices(name, prefix, frames, '', fps == null ? 24 : fps, loop == null ? false : loop);
      return true;
    });

    script.addCallback('playAnim', function(tag:String, name:String, ?forced:Bool, ?reverse:Bool, ?startFrame:Int):Bool
    {
      var sprite:Dynamic = PsychBridge.resolveObject(tag);
      if (sprite == null || !Std.isOfType(sprite, FlxSprite)) return false;

      var casted:FlxSprite = cast sprite;
      if (casted.animation.getByName(name) == null) return false;

      casted.animation.play(name, forced == null ? false : forced, reverse == null ? false : reverse, startFrame == null ? 0 : startFrame);
      return true;
    });

    script.addCallback('characterPlayAnim', function(character:String, name:String, ?forced:Bool):Void
    {
      var target:Dynamic = PsychBridge.resolveObject(character);
      if (target == null) return;

      // Characters here go through playAnimation, which knows about hold timers and
      // animation offsets; calling animation.play directly would skip both.
      Reflect.callMethod(target, Reflect.getProperty(target, 'playAnimation'), [name, forced == null ? false : forced]);
    });

    script.addCallback('addLuaSprite', function(tag:String, ?front:Bool):Bool
    {
      var game:Null<PlayState> = PlayState.instance;
      var sprite:Dynamic = PsychBridge.objects.get(tag);

      if (game == null || sprite == null || !Std.isOfType(sprite, FlxBasic)) return false;

      var basic:FlxBasic = cast sprite;

      // Psych's `front` means "over everything, including the notes". Without it a sprite
      // goes just above the stage, which is where a modchart background belongs - behind
      // the characters' UI but in front of the scenery.
      if (front == true || game.currentStage == null) game.add(basic);
      else
        game.insert(game.members.indexOf(game.currentStage) + 1, basic);

      return true;
    });

    script.addCallback('removeLuaSprite', function(tag:String, ?destroy:Bool):Bool
    {
      var game:Null<PlayState> = PlayState.instance;
      var sprite:Dynamic = PsychBridge.objects.get(tag);

      if (sprite == null || !Std.isOfType(sprite, FlxBasic)) return false;

      var basic:FlxBasic = cast sprite;
      if (game != null) game.remove(basic, true);

      if (destroy != false)
      {
        basic.destroy();
        PsychBridge.objects.remove(tag);
      }

      return true;
    });

    script.addCallback('setObjectCamera', function(tag:String, camera:String):Bool
    {
      var sprite:Dynamic = PsychBridge.resolveObject(tag);
      if (sprite == null || !Std.isOfType(sprite, FlxBasic)) return false;

      var target:Null<FlxCamera> = cameraNamed(camera);
      if (target == null) return false;

      (cast sprite : FlxBasic).cameras = [target];
      return true;
    });

    script.addCallback('luaSpriteExists', function(tag:String):Bool
    {
      return Std.isOfType(PsychBridge.objects.get(tag), FlxSprite);
    });
  }

  //
  // CAMERAS
  //

  static function registerCameras(script:PsychScript):Void
  {
    script.addCallback('cameraFlash', function(camera:String, color:String, duration:Float, ?forced:Bool):Void
    {
      var target:Null<FlxCamera> = cameraNamed(camera);
      if (target == null) return;

      target.flash(colorOf(color), duration, null, forced == true);
    });

    script.addCallback('cameraFade', function(camera:String, color:String, duration:Float, ?fadeOut:Bool, ?forced:Bool):Void
    {
      var target:Null<FlxCamera> = cameraNamed(camera);
      if (target == null) return;

      target.fade(colorOf(color), duration, fadeOut == true, null, forced == true);
    });

    script.addCallback('cameraShake', function(camera:String, intensity:Float, duration:Float):Void
    {
      var target:Null<FlxCamera> = cameraNamed(camera);
      if (target == null) return;

      target.shake(intensity, duration);
    });
  }

  //
  // TIMING
  //

  static function registerTiming(script:PsychScript):Void
  {
    script.addCallback('runTimer', function(tag:String, time:Float, ?loops:Int):Void
    {
      // Captured now, while the calling script is known. By the time the timer fires,
      // something else entirely may be the running script.
      var owner:Null<PsychScript> = PsychScript.current;
      if (owner == null) return;

      new FlxTimer().start(time, function(timer:FlxTimer):Void
      {
        if (owner.closed) return;

        // Psych hands the callback the tag, how many loops have run and how many were
        // asked for, in that order. Mods switch on the tag, so it has to come first.
        owner.call('onTimerCompleted', [tag, timer.loops - timer.loopsLeft, timer.loops]);
      }, loops == null ? 1 : loops);
    });
  }

  //
  // HELPERS
  //

  static function memberOf(group:String, index:Int):Dynamic
  {
    var resolved:Dynamic = PsychBridge.resolveObject(group);
    if (resolved == null) return null;

    var members:Dynamic = Reflect.getProperty(resolved, 'members');
    if (members == null || !Std.isOfType(members, Array)) return null;

    var list:Array<Dynamic> = cast members;
    return (index < 0 || index >= list.length) ? null : list[index];
  }

  static function cameraNamed(name:String):Null<FlxCamera>
  {
    var game:Null<PlayState> = PlayState.instance;
    if (game == null) return null;

    return switch (name)
    {
      case 'camHUD' | 'hud': game.camHUD;
      case 'camOther' | 'other': game.camCutscene;
      default: game.camGame;
    }
  }

  /**
   * Psych takes colours as hex strings, with or without a leading hash or `0x`.
   */
  static function colorOf(value:String):FlxColor
  {
    if (value == null || value == '') return FlxColor.WHITE;

    var parsed:Null<FlxColor> = FlxColor.fromString(StringTools.startsWith(value, '#') ? value : '#${value}');
    return parsed == null ? FlxColor.WHITE : parsed;
  }
}
#end
