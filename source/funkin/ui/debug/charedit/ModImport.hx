package funkin.ui.debug.charedit;

#if sys
import sys.FileSystem;
import sys.io.File;
#end
import funkin.util.FileUtil;
import funkin.util.FileUtil.FileWriteMode;

/**
 * Bringing characters in from mods that live somewhere else on the device.
 *
 * The game keeps its mods in its own storage, and on a recent Android one
 * app cannot simply read another's — but the game publishes that folder
 * through a document provider, which means the system folder picker can
 * reach it. What comes back from the picker is a tree URI rather than a
 * path, so the reading goes through the document provider too.
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
   * @param folder What the folder picker returned.
   * @param modRoot The editor's own mods folder.
   * @return What was brought in.
   */
  public static function importFrom(folder:String, modRoot:String):ImportResult
  {
    var result:ImportResult = {mods: [], characters: 0, trouble: [], saw: []};

    #if sys
    FileUtil.createDirIfNotExists(modRoot);

    // Kept for the sake of saying what was there when nothing comes of it. A
    // folder picker on a phone gives very little away about where it has
    // actually landed, and "found nothing" on its own is not something
    // anyone can act on.
    result.saw = entries(folder, '');

    var places:Array<Place> = findMods(folder);

    if (places.length == 0)
    {
      result.trouble.push('No data/characters folder in there.');
      return result;
    }

    for (place in places)
      importOne(folder, place.at, modRoot, place.named, result);
    #else
    result.trouble.push('Reading mods needs a filesystem.');
    #end

    return result;
  }

  #if sys
  /**
   * Where the mods are inside whatever was picked.
   *
   * Which of the game's data folder, its mods folder, or one mod on its own
   * somebody lands on in a file picker is mostly luck, so all three work.
   *
   * What makes a folder a mod here is having characters in it, rather than
   * having the metadata file the game looks for: a mod missing that file is
   * a mod the game would skip and one worth reading anyway, and the copy is
   * given a metadata file of its own either way.
   */
  static function findMods(folder:String):Array<Place>
  {
    var places:Array<Place> = [];

    if (hasCharacters(folder, '')) places.push({at: '', named: nameFromMeta(folder, '')});

    var top:Array<String> = folders(folder, '');

    for (root in ['', 'mods'])
    {
      if (root != '' && top.indexOf(root) == -1) continue;

      for (dir in folders(folder, root))
      {
        var at:String = root == '' ? dir : '$root/$dir';

        if (hasCharacters(folder, at)) places.push({at: at, named: asFolderName(dir)});
      }
    }

    return places;
  }

  /**
   * Whether a folder holds characters, which is what makes it worth taking.
   */
  static function hasCharacters(folder:String, at:String):Bool
  {
    for (name in names(folder, join(at, 'data/characters')))
      if (haxe.io.Path.extension(name) == 'json') return true;

    return false;
  }

  /**
   * Copy one mod's characters in, under a name of its own.
   */
  static function importOne(folder:String, at:String, modRoot:String, named:String, result:ImportResult):Void
  {
    var meta:String = polymod.PolymodConfig.modMetadataFile;
    var dest:String = haxe.io.Path.join([modRoot, named]);

    FileUtil.createDirIfNotExists(dest);

    // Taken if it is there and written if it is not: without one the game
    // skips the folder, so the copy has to have one whatever the original
    // did.
    var metaPath:String = haxe.io.Path.join([dest, meta]);

    if (!pull(folder, join(at, meta), metaPath)) FileUtil.writeStringToPath(metaPath, ownMeta(named), Force);

    var copied:Bool = false;

    for (part in WANTED)
    {
      // Asked for whether or not it is there: a mod keeps its art under one
      // of these and not the others, and which one is not worth guessing.
      if (entries(folder, join(at, part)).length == 0) continue;

      if (pull(folder, join(at, part), haxe.io.Path.join([dest, part]))) copied = true;
      else
        result.trouble.push('Could not read $named/$part.');
    }

    if (!copied)
    {
      result.trouble.push('Nothing readable in $named.');
      return;
    }

    result.mods.push(named);
    result.characters += characterCount(haxe.io.Path.join([dest, 'data/characters']));
  }

  /**
   * What makes the copy a mod, for one that arrived without it.
   *
   * `api_version` has to satisfy the game's own rule or the scan skips the
   * folder with a warning, exactly as if the file were not there.
   */
  static function ownMeta(named:String):String
  {
    return haxe.Json.stringify({
      title: named,
      description: 'Characters read out of a mod folder.',
      contributors: [],
      api_version: "0.8.0",
      mod_version: "1.0.0",
      license: "Unlicense"
    }, null, '  ');
  }

  /**
   * What a mod calls itself, for when it was picked on its own and there is
   * no directory name to take.
   */
  static function nameFromMeta(folder:String, at:String):String
  {
    var meta:String = polymod.PolymodConfig.modMetadataFile;
    var scratch:String = 'picked-$meta';

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
        // Left as it is. A mod whose metadata will not parse still has
        // characters worth reading.
      }

      try
      {
        FileSystem.deleteFile(scratch);
      }
      catch (e)
      {
        // Nothing to be done about a scratch file that will not go.
      }
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

  /**
   * What was in the picked folder, for saying so when nothing came of it.
   */
  var saw:Array<String>;
}

/**
 * A mod found inside the picked folder, and what to file it under.
 */
typedef Place =
{
  var at:String;
  var named:String;
}
