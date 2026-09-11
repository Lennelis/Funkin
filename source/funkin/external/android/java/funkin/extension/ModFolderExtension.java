package funkin.extensions;

import android.content.Context;
import android.net.Uri;
import android.provider.DocumentsContract;
import android.util.Log;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

import org.haxe.extension.Extension;

/**
 * Reading and writing a folder the user picked.
 *
 * Android stopped letting an app reach arbitrary paths, so a folder chosen
 * through the system picker does not come back as a path at all: it comes
 * back as a tree URI, and the only way through one is to ask the document
 * provider about each directory and each file in turn.
 *
 * That is what this is for. Everything else in the editor reads and writes
 * with ordinary file calls, inside the app's own storage where they still
 * work -- so what comes out of a picked folder is copied in there first.
 */
public class ModFolderExtension extends Extension
{
  public static final String LOG_TAG = "ModFolderExtension";

  /**
   * Something to ask the content resolver through.
   *
   * The activity as well as the context, because which of the two the host
   * has filled in is not something anything here gets a say in, and a null
   * one turns every call below into a silent nothing.
   */
  private static Context context()
  {
    if (mainContext != null) return mainContext;

    return mainActivity;
  }

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
      if (existing != null) DocumentsContract.deleteDocument(context().getContentResolver(), existing);

      Uri file = DocumentsContract.createDocument(context().getContentResolver(), directory, "application/octet-stream", name);
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
        out = context().getContentResolver().openOutputStream(file, "wt");

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
   * What is inside a folder, one name per line.
   *
   * Directories are marked with a trailing "/", since a document provider
   * answers about type rather than about shape of name and the caller has no
   * other way to tell one from the other.
   *
   * @param treeUriString The tree URI the folder picker returned.
   * @param relativePath Where inside that folder to look, "/" separated, or
   *   empty for the folder itself.
   * @return The listing, or null if there is nothing there to list.
   */
  public static String listChildren(String treeUriString, String relativePath)
  {
    if (treeUriString == null) return null;

    Uri directory = resolve(treeUriString, relativePath);
    if (directory == null) return null;

    android.database.Cursor cursor = null;
    StringBuilder found = new StringBuilder();

    try
    {
      Uri children = DocumentsContract.buildChildDocumentsUriUsingTree(directory, DocumentsContract.getDocumentId(directory));

      cursor = context().getContentResolver()
        .query(children,
          new String[]
          {
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE
          }, null, null, null);

      if (cursor == null) return null;

      while (cursor.moveToNext())
      {
        String name = cursor.getString(0);
        if (name == null) continue;

        found.append(name);
        if (DocumentsContract.Document.MIME_TYPE_DIR.equals(cursor.getString(1))) found.append("/");
        found.append("\n");
      }
    }
    catch (Exception e)
    {
      Log.e(LOG_TAG, "Could not list " + relativePath + ": " + e.getMessage());
      return null;
    }
    finally
    {
      if (cursor != null) cursor.close();
    }

    return found.toString();
  }

  /**
   * Copy something out of a picked folder into ordinary storage.
   *
   * A directory is copied whole, everything under it included.
   *
   * @param treeUriString The tree URI the folder picker returned.
   * @param relativePath What inside that folder to copy, "/" separated.
   * @param destPath Where to put it, as an ordinary path.
   * @return Whether anything was copied.
   */
  public static boolean copyOut(String treeUriString, String relativePath, String destPath)
  {
    if (treeUriString == null || destPath == null) return false;

    Uri source = resolve(treeUriString, relativePath);
    if (source == null) return false;

    return copyDocument(source, new File(destPath));
  }

  /**
   * Copy one document, or a whole directory of them, to a path.
   */
  private static boolean copyDocument(Uri source, File dest)
  {
    if (isDirectory(source))
    {
      if (!dest.exists() && !dest.mkdirs())
      {
        Log.e(LOG_TAG, "Could not make: " + dest.getPath());
        return false;
      }

      android.database.Cursor cursor = null;
      boolean all = true;

      try
      {
        Uri children = DocumentsContract.buildChildDocumentsUriUsingTree(source, DocumentsContract.getDocumentId(source));

        cursor = context().getContentResolver()
          .query(children,
            new String[]
            {
              DocumentsContract.Document.COLUMN_DOCUMENT_ID,
              DocumentsContract.Document.COLUMN_DISPLAY_NAME
            }, null, null, null);

        if (cursor == null) return false;

        while (cursor.moveToNext())
        {
          String name = cursor.getString(1);
          if (name == null) continue;

          Uri child = DocumentsContract.buildDocumentUriUsingTree(source, cursor.getString(0));
          if (!copyDocument(child, new File(dest, name))) all = false;
        }
      }
      catch (Exception e)
      {
        Log.e(LOG_TAG, "Could not copy out of " + source + ": " + e.getMessage());
        return false;
      }
      finally
      {
        if (cursor != null) cursor.close();
      }

      return all;
    }

    File parent = dest.getParentFile();
    if (parent != null && !parent.exists() && !parent.mkdirs())
    {
      Log.e(LOG_TAG, "Could not make: " + parent.getPath());
      return false;
    }

    InputStream in = null;
    OutputStream out = null;

    try
    {
      in = context().getContentResolver().openInputStream(source);

      if (in == null)
      {
        Log.e(LOG_TAG, "Could not open for reading: " + source);
        return false;
      }

      out = new FileOutputStream(dest);

      byte[] buffer = new byte[8192];
      int read;
      while ((read = in.read(buffer)) != -1)
        out.write(buffer, 0, read);

      out.flush();
      return true;
    }
    catch (Exception e)
    {
      Log.e(LOG_TAG, "Failed to read " + source + ": " + e.getMessage());
      return false;
    }
    finally
    {
      try
      {
        if (in != null) in.close();
        if (out != null) out.close();
      }
      catch (IOException e)
      {
        Log.e(LOG_TAG, "Could not close " + dest.getPath() + ": " + e.getMessage());
      }
    }
  }

  /**
   * Whether a document is a directory.
   */
  private static boolean isDirectory(Uri document)
  {
    android.database.Cursor cursor = null;

    try
    {
      cursor = context().getContentResolver()
        .query(document, new String[] {DocumentsContract.Document.COLUMN_MIME_TYPE}, null, null, null);

      if (cursor == null || !cursor.moveToFirst()) return false;

      return DocumentsContract.Document.MIME_TYPE_DIR.equals(cursor.getString(0));
    }
    catch (Exception e)
    {
      return false;
    }
    finally
    {
      if (cursor != null) cursor.close();
    }
  }

  /**
   * Walk down to something inside a picked folder, without making anything.
   */
  private static Uri resolve(String treeUriString, String relativePath)
  {
    try
    {
      Uri tree = Uri.parse(treeUriString);
      Uri at = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree));

      if (relativePath == null || relativePath.isEmpty()) return at;

      for (String part : relativePath.split("/"))
      {
        if (part.isEmpty()) continue;

        at = findChild(at, part);
        if (at == null) return null;
      }

      return at;
    }
    catch (Exception e)
    {
      Log.e(LOG_TAG, "Could not reach " + relativePath + ": " + e.getMessage());
      return null;
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
      return DocumentsContract.createDocument(context().getContentResolver(), parent, DocumentsContract.Document.MIME_TYPE_DIR, name);
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

      cursor = context().getContentResolver()
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
