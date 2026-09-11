package funkin.ui.debug.charedit;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

/**
 * Bringing characters in from mods that live somewhere else on the device.
 *
 * The game keeps its mods in its own storage, and on a recent Android one
 * app cannot simply read another's — but the game publishes that folder
 * through a document provider, which means the system folder picker can
 * reach it. What comes back from the picker is a tree URI rather than a
 * path, so the copy goes through the document provider too.
 *
 * Only the parts of a mod that a character needs are taken. A mod is mostly
 * songs and video, and copying all of that to look at a character would take
 * a while and fill the phone up for nothing.
 */
class ModImport
{
  /**
   * The parts of a mod worth copying for the sake of its characters.
   */
  static final WANTED:Array<String> = ['data/characters', 'images/characters', 'shared/images/characters'];

  /**
   * What a folder name is allowed to be made of.
   */
  static final PLAIN:EReg = ~/[A-Za-z0-9_\-]/;

  /**
   * Find the mods in a folder and copy their characters into the editor's own.
   *
   * Forgiving about what was picked: the game's data folder, the mods folder
   * inside it, or a single mod all work, since which of those someone lands
   * on in a file picker is mostly luck.
   *
   * @param folder What the folder picker returned.
   * @param modRoot The editor's own mods folder.
   * @return What was brought in.
   */
  public static function importFrom(folder:String, modRoot:String):ImportResult
  {
    var result:ImportResult = {mods: [], characters: 0, trouble: []};

    #if sys
    var meta:String = polymod.PolymodConfig.modMetadataFile;

    funkin.util.FileUtil.createDirIfNotExists(modRoot);

    // A single mod, picked on its own. It has no directory name to take, so
    // the copy is named after what the mod calls itself.
    if (names(folder, '').indexOf(meta) != -1)
    {
      if (importOne(folder, '', modRoot, nameFromMeta(folder, '', modRoot), result) == null)
      {
        result.trouble.push('No characters in that mod.');
      }

      return result;
    }

    // Otherwise it is either the folder the mods are in, or the folder that
    // one is in -- which of those someone lands on in a file picker is
    // mostly luck, so both work.
    var inside:String = folders(folder, '').indexOf('mods') != -1 ? 'mods' : '';

    var dirs:Array<String> = folders(folder, inside);

    if (dirs.length == 0)
    {
      result.trouble.push('No mods in there.');
      return result;
    }

    for (dir in dirs)
    {
      var at:String = inside == '' ? dir : '$inside/$dir';

      // A folder without one of these is not a mod, and the game would skip
      // it too rather than guess.
      if (names(folder, at).indexOf(meta) == -1) continue;

      importOne(folder, at, modRoot, dir, result);
    }

    if (result.mods.length == 0 && result.trouble.length == 0) result.trouble.push('No mods in there.');
    #else
    result.trouble.push('Reading mods needs a filesystem.');
    #end

    return result;
  }

  #if sys
  /**
   * Copy one mod's characters in, under a name of its own.
   *
   * @return The name it was filed under, or null if it had no characters.
   */
  static function importOne(folder:String, at:String, modRoot:String, named:String, result:ImportResult):Null<String>
  {
    var meta:String = polymod.PolymodConfig.modMetadataFile;
    var dest:String = haxe.io.Path.join([modRoot, named]);

    // Nothing to show for it unless it has characters, and a mod folder with
    // no characters in it would be one more thing for the game to load.
    if (names(folder, join(at, 'data/characters')).length == 0) return null;

    funkin.util.FileUtil.createDirIfNotExists(modRoot);
    funkin.util.FileUtil.createDirIfNotExists(dest);

    if (!pull(folder, join(at, meta), haxe.io.Path.join([dest, meta])))
    {
      result.trouble.push('Could not read $named.');
      return null;
    }

    for (part in WANTED)
    {
      // Asked for whether or not it is there: a mod has its art under one of
      // these and not the others, and which one is not worth guessing.
      if (names(folder, join(at, part)).length == 0) continue;

      if (!pull(folder, join(at, part), haxe.io.Path.join([dest, part]))) result.trouble.push('Could not read $named/$part.');
    }

    var brought:Int = characterCount(haxe.io.Path.join([dest, 'data/characters']));

    result.mods.push(named);
    result.characters += brought;

    return named;
  }

  /**
   * What a mod calls itself, for when it was picked on its own and there is
   * no directory name to take.
   */
  static function nameFromMeta(folder:String, at:String, modRoot:String):String
  {
    var meta:String = polymod.PolymodConfig.modMetadataFile;
    var scratch:String = haxe.io.Path.join([modRoot, '.picked-$meta']);

    var title:String = 'imported';

    if (pull(folder, join(at, meta), scratch))
    {
      try
      {
        var parsed:Dynamic = haxe.Json.parse(File.getContent(scratch));

        var said:Dynamic = parsed.title;
        if (said == null) said = parsed.name;

        if (said != null && Std.isOfType(said, String) && said != '') title = said;
      }
      catch (e)
      {
        // Left as it is; a mod whose metadata will not parse still has
        // characters worth reading.
      }

      try
      {
        FileSystem.deleteFile(scratch);
      }
      catch (e) {}
    }

    return asFolderName(title);
  }

  /**
   * A title as something that can be a folder.
   */
  static function asFolderName(title:String):String
  {
    var out:StringBuf = new StringBuf();

    for (i in 0...title.length)
    {
      var c:String = title.charAt(i);
      out.add(PLAIN.match(c) ? c : '-');
    }

    var name:String = out.toString();
    while (name.indexOf('--') != -1)
      name = StringTools.replace(name, '--', '-');

    name = ~/^-+|-+$/g.replace(name, '');

    return name == '' ? 'imported' : name;
  }

  /**
   * How many characters a folder of them holds.
   */
  static function characterCount(path:String):Int
  {
    if (!FileSystem.exists(path) || !FileSystem.isDirectory(path)) return 0;

    var found:Int = 0;

    for (name in FileSystem.readDirectory(path))
      if (haxe.io.Path.extension(name) == 'json') found++;

    return found;
  }

  static function join(at:String, part:String):String
  {
    return at == '' ? part : '$at/$part';
  }

  /**
   * The names of the files in a folder, directories left out.
   */
  static function names(folder:String, at:String):Array<String>
  {
    return [for (entry in entries(folder, at)) if (!StringTools.endsWith(entry, '/')) entry];
  }

  /**
   * The names of the directories in a folder, files left out.
   */
  static function folders(folder:String, at:String):Array<String>
  {
    return [for (entry in entries(folder, at)) if (StringTools.endsWith(entry, '/')) entry.substr(0, entry.length - 1)];
  }

  /**
   * What is inside a folder, directories marked with a trailing "/".
   */
  static function entries(folder:String, at:String):Array<String>
  {
    #if android
    if (StringTools.startsWith(folder, 'content://')) return funkin.external.android.ModFolderUtil.listChildren(folder, at);
    #end

    var path:String = at == '' ? folder : haxe.io.Path.join([folder, at]);

    if (!FileSystem.exists(path) || !FileSystem.isDirectory(path)) return [];

    return [
      for (name in FileSystem.readDirectory(path))
        FileSystem.isDirectory(haxe.io.Path.join([path, name])) ? '$name/' : name
    ];
  }

  /**
   * Copy something out of the picked folder, a directory and all.
   */
  static function pull(folder:String, at:String, destPath:String):Bool
  {
    #if android
    if (StringTools.startsWith(folder, 'content://')) return funkin.external.android.ModFolderUtil.copyOut(folder, at, destPath);
    #end

    return copyTree(haxe.io.Path.join([folder, at]), destPath);
  }

  static function copyTree(sourcePath:String, destPath:String):Bool
  {
    if (!FileSystem.exists(sourcePath)) return false;

    if (!FileSystem.isDirectory(sourcePath))
    {
      var parent:String = haxe.io.Path.directory(destPath);
      if (parent != '') FileSystem.createDirectory(parent);

      File.copy(sourcePath, destPath);
      return true;
    }

    FileSystem.createDirectory(destPath);

    var all:Bool = true;

    for (name in FileSystem.readDirectory(sourcePath))
      if (!copyTree(haxe.io.Path.join([sourcePath, name]), haxe.io.Path.join([destPath, name]))) all = false;

    return all;
  }
  #end
}

/**
 * What came of reading a folder of mods.
 */
typedef ImportResult =
{
  var mods:Array<String>;
  var characters:Int;
  var trouble:Array<String>;
}
