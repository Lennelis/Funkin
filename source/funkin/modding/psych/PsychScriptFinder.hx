package funkin.modding.psych;

#if FEATURE_PSYCH_LUA
import funkin.modding.PolymodHandler;
import haxe.io.Path;

/**
 * Finds the Lua files a Psych mod expects to be run.
 *
 * Psych has no manifest for scripts. A file is loaded because of where it sits: anything
 * in a mod's `scripts/` folder runs for every song, and anything in `data/<song>/` runs
 * for that song. That convention is the whole contract, so this reproduces it rather than
 * asking mods to declare anything new.
 *
 * Deliberately read straight off disk rather than through Polymod. Polymod's asset layer
 * exists to let one mod's file replace another's, which is right for images and charts
 * and wrong here: two mods that both ship `scripts/init.lua` both want theirs to run, and
 * going through the asset system would silently drop one of them.
 */
class PsychScriptFinder
{
  /**
   * Where a mod keeps scripts that should run for every song.
   */
  static inline var GLOBAL_FOLDER:String = 'scripts';

  /**
   * Where a mod keeps scripts for one song, under the song's id.
   */
  static inline var SONG_FOLDER:String = 'data';

  static inline var EXTENSION:String = '.lua';

  /**
   * Every script that should be running for a given song, in load order: global scripts
   * first, then the song's own, so a song script can rely on anything a global set up.
   */
  public static function findForSong(songId:String):Array<String>
  {
    var found:Array<String> = [];

    #if sys
    for (dir in PolymodHandler.loadedModDirs)
    {
      collect(Path.join([PolymodHandler.MOD_FOLDER, dir, GLOBAL_FOLDER]), found);
    }

    if (songId != null && songId != '')
    {
      for (dir in PolymodHandler.loadedModDirs)
      {
        collect(Path.join([PolymodHandler.MOD_FOLDER, dir, SONG_FOLDER, songId]), found);
      }
    }
    #end

    return found;
  }

  /**
   * Which mod a script came from, or null if it isn't under one.
   *
   * Scripts ask for their own files by relative path, so this is what tells the API which
   * mod folder to resolve those against.
   */
  public static function modOf(path:String):Null<String>
  {
    #if sys
    var root:String = Path.normalize(PolymodHandler.MOD_FOLDER) + '/';
    var normalized:String = Path.normalize(path);

    if (!StringTools.startsWith(normalized, root)) return null;

    var rest:String = normalized.substr(root.length);
    var slash:Int = rest.indexOf('/');

    return slash == -1 ? rest : rest.substring(0, slash);
    #else
    return null;
    #end
  }

  #if sys
  static function collect(folder:String, into:Array<String>):Void
  {
    if (!sys.FileSystem.exists(folder) || !sys.FileSystem.isDirectory(folder)) return;

    var names:Array<String> = sys.FileSystem.readDirectory(folder);

    // Psych loads whatever the filesystem hands it, which on most machines is already
    // alphabetical; sorting makes the order the same everywhere, so a mod that depends
    // on one script running before another behaves the same on every device.
    names.sort(function(a:String, b:String):Int return a < b ? -1 : (a > b ? 1 : 0));

    for (name in names)
    {
      if (!StringTools.endsWith(name.toLowerCase(), EXTENSION)) continue;

      var full:String = Path.join([folder, name]);
      if (sys.FileSystem.isDirectory(full)) continue;

      into.push(full);
    }
  }
  #end
}
#end
