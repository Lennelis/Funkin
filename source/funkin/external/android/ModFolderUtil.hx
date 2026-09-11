package funkin.external.android;

#if android
/**
 * Writing into a folder the user picked.
 *
 * Android hands back a tree URI rather than a path when someone chooses a
 * folder, and nothing that writes by path can do anything with one — so
 * placing a file inside it goes through the document provider on the Java
 * side instead.
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
