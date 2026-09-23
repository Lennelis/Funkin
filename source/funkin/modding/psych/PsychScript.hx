package funkin.modding.psych;

#if FEATURE_PSYCH_LUA
import llua.Convert;
import llua.Lua;
import llua.LuaL;
import llua.Lua_helper;
import llua.State;

/**
 * One Psych Engine Lua file, and the interpreter running it.
 *
 * Psych mods are written against a flat global API - `setProperty('health', 2)`,
 * `function onBeatHit()` - rather than against a class. So a script is not an object
 * with methods; it is a Lua state with globals in it, and calling a "callback" means
 * looking up a global by name and seeing whether one is there.
 *
 * This class is only the runtime: loading a file, reading and writing globals, calling
 * a function, reporting an error somewhere a modder will see it. What the API actually
 * *does* lives in `PsychApi`, and what drives the callbacks lives in `PsychScriptHandler`.
 */
class PsychScript
{
  /**
   * What a Psych callback returns to say what should happen next.
   *
   * A callback that returns nothing at all means "carry on", which is why `CONTINUE` is
   * what a missing function and a failed call both come back as - a script that does not
   * implement `onBeatHit` must not be able to cancel a beat by staying silent.
   */
  public static final CONTINUE:String = '##PSYCHLUA_FUNCTIONCONTINUE';

  public static final STOP:String = '##PSYCHLUA_FUNCTIONSTOP';
  public static final STOP_LUA:String = '##PSYCHLUA_FUNCTIONSTOPLUA';
  public static final STOP_HSCRIPT:String = '##PSYCHLUA_FUNCTIONSTOPHSCRIPT';
  public static final STOP_ALL:String = '##PSYCHLUA_FUNCTIONSTOPALL';

  /**
   * The script whose callback is currently running, or null.
   *
   * The API needs this: `addLuaScript('foo.lua')` is written relative to the calling
   * script's mod, and there is nothing in the Lua call itself that says which script
   * that was.
   */
  public static var current(default, null):Null<PsychScript> = null;

  /**
   * The file this came from, as an absolute path.
   */
  public var path(default, null):String;

  /**
   * The mod folder this script belongs to, or null for one shipped with the game.
   * Psych scripts use it to find their own assets.
   */
  public var modId(default, null):Null<String>;

  /**
   * False once the script has asked to be shut down, or has been.
   * A closed script is inert: calls return `CONTINUE` and change nothing.
   */
  public var closed(default, null):Bool = false;

  var lua:Null<State> = null;

  public function new(path:String, ?modId:String)
  {
    this.path = path;
    this.modId = modId;
  }

  /**
   * Starts the interpreter and runs the file top to bottom.
   * @return Whether the script loaded. A script that failed to load is closed.
   */
  public function load():Bool
  {
    lua = LuaL.newstate();

    if (lua == null)
    {
      trace('[PSYCHLUA] Could not create a Lua state for ${path}');
      closed = true;
      return false;
    }

    LuaL.openlibs(lua);

    PsychApi.register(this);

    // Top-level code in the file can call the API as freely as a callback can, so the
    // "which script is running" answer has to be true here too.
    var previous:Null<PsychScript> = current;
    current = this;

    var result:Dynamic = LuaL.dofile(lua, path);
    var message:String = Lua.tostring(lua, result);

    current = previous;

    // dofile returns 0 for a clean run. Anything else leaves the error on the stack.
    if (result != 0 && message != null)
    {
      reportError(message);
      stop();
      return false;
    }

    return true;
  }

  /**
   * Sets a Lua global.
   */
  public function set(name:String, value:Dynamic):Void
  {
    if (lua == null) return;

    Convert.toLua(lua, value);
    Lua.setglobal(lua, name);
  }

  /**
   * Reads a Lua global.
   */
  public function get(name:String):Dynamic
  {
    if (lua == null) return null;

    Lua.getglobal(lua, name);
    var value:Dynamic = Convert.fromLua(lua, -1);
    Lua.pop(lua, 1);
    return value;
  }

  /**
   * Registers a function the script can call.
   */
  public function addCallback(name:String, callback:Dynamic):Void
  {
    if (lua == null) return;

    Lua_helper.add_callback(lua, name, callback);
  }

  /**
   * Calls a global function, if the script defines one by that name.
   *
   * A script that doesn't define it isn't an error - most scripts implement a handful of
   * the several dozen callbacks Psych offers - so that comes back as `CONTINUE` like a
   * function that ran and said nothing.
   */
  public function call(name:String, args:Array<Dynamic>):Dynamic
  {
    if (closed || lua == null) return CONTINUE;

    var previous:Null<PsychScript> = current;
    current = this;

    try
    {
      Lua.getglobal(lua, name);

      if (Lua.type(lua, -1) != Lua.LUA_TFUNCTION)
      {
        // A global of the wrong type is worth saying something about: it usually means a
        // variable has shadowed the callback and the script has silently stopped working.
        if (Lua.type(lua, -1) > Lua.LUA_TNIL) reportError('${name} is not a function');

        Lua.pop(lua, 1);
        current = previous;
        return CONTINUE;
      }

      for (arg in args)
        Convert.toLua(lua, arg);

      var status:Int = Lua.pcall(lua, args.length, 1, 0);

      if (status != Lua.LUA_OK)
      {
        reportError(errorMessage(status));
        current = previous;
        return CONTINUE;
      }

      var result:Dynamic = Convert.fromLua(lua, -1);
      Lua.pop(lua, 1);

      current = previous;
      if (closed) shutdown();

      return result == null ? CONTINUE : result;
    }
    catch (e:Dynamic)
    {
      trace('[PSYCHLUA] ${path}: ${e}');
    }

    current = previous;
    return CONTINUE;
  }

  /**
   * Marks the script as finished. The interpreter is torn down once it is safe to -
   * a script may call `close()` from inside a callback, and freeing the state it is
   * running in would take the ground out from under it.
   */
  public function stop():Void
  {
    closed = true;

    if (current != this) shutdown();
  }

  function shutdown():Void
  {
    if (lua == null) return;

    Lua.close(lua);
    lua = null;
  }

  function errorMessage(status:Int):String
  {
    var reason:String = switch (status)
    {
      case Lua.LUA_ERRRUN: 'Runtime Error';
      case Lua.LUA_ERRMEM: 'Memory Allocation Error';
      case Lua.LUA_ERRERR: 'Critical Error';
      default: 'Unknown Error';
    }

    var detail:Null<String> = Lua.tostring(lua, -1);
    Lua.pop(lua, 1);

    return detail == null ? reason : '${reason}: ${detail}';
  }

  /**
   * Where a script's mistakes go.
   *
   * Deliberately not a modal: Psych puts these on screen while the song keeps playing,
   * and a dialog box in the middle of a chart would be worse than the bug it reports.
   * `PsychScriptHandler` picks these up and draws them.
   */
  function reportError(message:String):Void
  {
    var name:String = haxe.io.Path.withoutDirectory(path);
    trace('[PSYCHLUA] ${name}: ${message}');
    PsychScriptHandler.reportError('${name}: ${message}');
  }
}
#end
