package funkin.external.android;

#if android
/**
 * A Utility class to manage the Application's Data folder on Android.
 */
class DataFolderUtil
{
  /**
   * Whether the data folder was opened from here and has not come back yet.
   *
   * Every activity this app starts reports back through one callback, the
   * system file picker included, so the request code on its own is not proof
   * of which activity is answering. Anything acting on the data folder being
   * closed has to know that it was opened first.
   */
  public static var awaitingClose(default, null):Bool = false;

  /**
   * Opens the data folder on an Android device using JNI.
   */
  public static function openDataFolder():Void
  {
    final openDataFolderJNI:Null<Dynamic> = JNIUtil.createStaticMethod('funkin/util/DataFolderUtil', 'openDataFolder', '(I)V');

    if (openDataFolderJNI != null)
    {
      awaitingClose = true;

      openDataFolderJNI(CallbackUtil.DATA_FOLDER_CLOSED);
    }
  }

  /**
   * Say that the answer has arrived, so the next one is not taken for it.
   */
  public static function markClosed():Void
  {
    awaitingClose = false;
  }
}
#end
