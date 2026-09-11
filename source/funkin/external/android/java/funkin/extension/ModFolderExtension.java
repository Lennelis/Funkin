package funkin.extensions;

import android.content.Context;
import android.net.Uri;
import android.provider.DocumentsContract;
import android.util.Log;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

import org.haxe.extension.Extension;

/**
 * Writing files into a folder the user picked.
 *
 * Android stopped letting an app write to arbitrary paths, so a folder
 * chosen through the system picker does not come back as a path at all: it
 * comes back as a tree URI, and the only way to put anything inside it is to
 * ask the document provider to make each directory and each file in turn.
 *
 * That is what this is for. Everything else in the editor writes with
 * ordinary file calls, into the app's own storage where they still work.
 */
public class ModFolderExtension extends Extension
{
  public static final String LOG_TAG = "ModFolderExtension";

  /**
   * Copy a file into a folder the user picked, making the directories on the
   * way if they are not there.
   *
   * @param treeUriString The tree URI the folder picker returned.
   * @param relativePath Where inside that folder it goes, with "/" between
   *   the parts. For example "data/characters/bf.json".
   * @param sourcePath The file to copy, as an ordinary path.
   * @return Whether it was written.
   */
  public static boolean copyInto(String treeUriString, String relativePath, String sourcePath)
  {
    if (treeUriString == null || relativePath == null || sourcePath == null) return false;

    File source = new File(sourcePath);
    if (!source.exists())
    {
      Log.e(LOG_TAG, "Nothing to copy at: " + sourcePath);
      return false;
    }

    try
    {
      Uri tree = Uri.parse(treeUriString);
      Uri directory = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree));

      String[] parts = relativePath.split("/");

      // Everything but the last part is a directory that has to exist.
      for (int i = 0; i < parts.length - 1; i++)
      {
        if (parts[i].isEmpty()) continue;

        directory = findOrCreateDirectory(directory, parts[i]);
        if (directory == null) return false;
      }

      String name = parts[parts.length - 1];

      // A document provider will happily make a second file with the same
      // name rather than replacing the first, so an existing one goes.
      Uri existing = findChild(directory, name);
      if (existing != null) DocumentsContract.deleteDocument(mainContext.getContentResolver(), existing);

      Uri file = DocumentsContract.createDocument(mainContext.getContentResolver(), directory, "application/octet-stream", name);
      if (file == null)
      {
        Log.e(LOG_TAG, "Could not create: " + relativePath);
        return false;
      }

      InputStream in = null;
      OutputStream out = null;

      try
      {
        in = new FileInputStream(source);
        out = mainContext.getContentResolver().openOutputStream(file, "wt");

        if (out == null)
        {
          Log.e(LOG_TAG, "Could not open for writing: " + relativePath);
          return false;
        }

        byte[] buffer = new byte[8192];
        int read;
        while ((read = in.read(buffer)) != -1)
          out.write(buffer, 0, read);

        out.flush();
      }
      finally
      {
        if (in != null) in.close();
        if (out != null) out.close();
      }

      return true;
    }
    catch (Exception e)
    {
      Log.e(LOG_TAG, "Failed to write " + relativePath + ": " + e.getMessage());
      return false;
    }
  }

  /**
   * The child directory of that name, made if it is not already there.
   */
  private static Uri findOrCreateDirectory(Uri parent, String name)
  {
    Uri existing = findChild(parent, name);
    if (existing != null) return existing;

    try
    {
      return DocumentsContract.createDocument(mainContext.getContentResolver(), parent, DocumentsContract.Document.MIME_TYPE_DIR, name);
    }
    catch (Exception e)
    {
      Log.e(LOG_TAG, "Could not create directory " + name + ": " + e.getMessage());
      return null;
    }
  }

  /**
   * Look through a directory for something of that name.
   *
   * A document provider has no notion of a path, so finding anything means
   * listing what is there and comparing names.
   */
  private static Uri findChild(Uri parent, String name)
  {
    android.database.Cursor cursor = null;

    try
    {
      Uri children = DocumentsContract.buildChildDocumentsUriUsingTree(parent, DocumentsContract.getDocumentId(parent));

      cursor = mainContext.getContentResolver()
        .query(children, new String[] {DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME}, null, null, null);

      if (cursor == null) return null;

      while (cursor.moveToNext())
      {
        if (name.equals(cursor.getString(1)))
        {
          return DocumentsContract.buildDocumentUriUsingTree(parent, cursor.getString(0));
        }
      }
    }
    catch (Exception e)
    {
      Log.e(LOG_TAG, "Could not look inside " + parent + ": " + e.getMessage());
    }
    finally
    {
      if (cursor != null) cursor.close();
    }

    return null;
  }
}
