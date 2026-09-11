package funkin.external.android;

#if android
/**
 * Reading and writing a folder the user picked.
 *
 * Android hands back a tree URI rather than a path when someone chooses a
 * folder, and nothing that works by path can do anything with one — so
 * reaching inside it goes through the document provider on the Java side
 * instead.
 */
class ModFolderUtil
{
  /**
   * Copy a file into a chosen folder, making the directories on the way.
   *
   * @param treeUri The tree URI the folder picker returned.
   * @param relativePath Where inside that folder it goes, "/" separated.
   * @param sourcePath The file to copy, as an ordinary path.
   * @return Whether it was written.
   */
  public static function copyInto(treeUri:String, relativePath:String, sourcePath:String):Bool
  {
    final copyIntoJNI:Null<Dynamic> = JNIUtil.createStaticMethod('funkin/extensions/ModFolderExtension', 'copyInto',
      '(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Z');

    if (copyIntoJNI == null) return false;

    return copyIntoJNI(treeUri, relativePath, absolute(sourcePath)) == true;
  }

  /**
   * What is inside a folder the user picked.
   *
   * @param treeUri The tree URI the folder picker returned.
   * @param relativePath Where inside it to look, "/" separated, or empty for
   *   the folder itself.
   * @return The names, directories marked with a trailing "/". Empty if
   *   there is nothing there, or nothing there to look in.
   */
  public static function listChildren(treeUri:String, relativePath:String = ''):Array<String>
  {
    final listChildrenJNI:Null<Dynamic> = JNIUtil.createStaticMethod('funkin/extensions/ModFolderExtension', 'listChildren',
      '(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;');

    if (listChildrenJNI == null) return [];

    final listing:Null<String> = listChildrenJNI(treeUri, relativePath);

    if (listing == null || listing == '') return [];

    return [for (name in listing.split('\n')) if (name != '') name];
  }

  /**
   * Copy something out of a folder the user picked, into ordinary storage.
   *
   * A directory comes out whole, everything under it included.
   *
   * @param treeUri The tree URI the folder picker returned.
   * @param relativePath What inside it to copy, "/" separated.
   * @param destPath Where to put it, as an ordinary path.
   * @return Whether anything was copied.
   */
  public static function copyOut(treeUri:String, relativePath:String, destPath:String):Bool
  {
    final copyOutJNI:Null<Dynamic> = JNIUtil.createStaticMethod('funkin/extensions/ModFolderExtension', 'copyOut',
      '(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Z');

    if (copyOutJNI == null) return false;

    return copyOutJNI(treeUri, relativePath, absolute(destPath)) == true;
  }

  /**
   * A path the Java side will understand.
   *
   * The game moves its own working directory at startup and everything here
   * writes paths against that — but the move is the native one, and Java
   * resolves a relative path against the process's own working directory,
   * which on Android is the root of the filesystem and not somewhere
   * anything can be read from or written to. So a path crossing over is
   * spelled out in full first.
   */
  static function absolute(path:String):String
  {
    if (StringTools.startsWith(path, '/')) return path;

    return haxe.io.Path.join([Sys.getCwd(), path]);
  }
}
#end
