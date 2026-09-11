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

    return copyIntoJNI(treeUri, relativePath, sourcePath) == true;
  }
}
#end
