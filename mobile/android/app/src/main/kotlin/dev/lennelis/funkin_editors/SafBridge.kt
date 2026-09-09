package dev.lennelis.funkin_editors

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * The Storage Access Framework, exposed to Dart.
 *
 * From Android 11 an app cannot open a mod folder on shared storage by path,
 * however plainly the path is written on screen. What it can do is ask for a
 * folder once, take a persistable grant on it, and address everything inside
 * by document URI from then on. That is what this does, and the grant survives
 * a reboot so the person picks their mod folder once rather than every launch.
 *
 * Every method answers with plain maps so the Dart side never has to know what
 * a document URI is made of.
 */
class SafBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    var activity: Activity? = null

    private var pendingPick: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "pickTree" -> pickTree(result)
                "savedTrees" -> result.success(savedTrees())
                "forgetTree" -> {
                    forgetTree(requireUri(call))
                    result.success(null)
                }
                "list" -> result.success(list(requireUri(call)))
                "child" -> result.success(child(requireUri(call), call.argument<String>("name")!!))
                "read" -> result.success(read(requireUri(call)))
                "write" -> {
                    write(requireUri(call), call.argument<ByteArray>("bytes")!!)
                    result.success(null)
                }
                "createFile" -> result.success(
                    createChild(requireUri(call), call.argument<String>("name")!!, false)
                )
                "createDirectory" -> result.success(
                    createChild(requireUri(call), call.argument<String>("name")!!, true)
                )
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error("saf_error", error.message ?: error.toString(), null)
        }
    }

    private fun requireUri(call: MethodCall): Uri =
        Uri.parse(call.argument<String>("uri") ?: throw IllegalArgumentException("No uri given"))

    // -- picking ------------------------------------------------------------

    private fun pickTree(result: MethodChannel.Result) {
        val host = activity ?: throw IllegalStateException("No activity to show the picker from")

        // Only one picker can be up at a time, and the second caller would
        // otherwise wait forever for a result that goes to the first.
        pendingPick?.error("saf_cancelled", "Another folder picker replaced this one", null)
        pendingPick = result

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            )
        }

        host.startActivityForResult(intent, PICK_TREE_REQUEST)
    }

    /** Returns true when this was our request, whatever came of it. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_TREE_REQUEST) return false

        val result = pendingPick
        pendingPick = null

        if (result == null) return true

        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            // Backing out of the picker is an ordinary thing to do, not an error.
            result.success(null)
            return true
        }

        try {
            context.contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
            result.success(treeEntry(uri))
        } catch (error: Exception) {
            result.error("saf_error", error.message ?: error.toString(), null)
        }

        return true
    }

    private fun savedTrees(): List<Map<String, Any?>> =
        context.contentResolver.persistedUriPermissions
            .filter { it.isReadPermission && it.isWritePermission }
            .mapNotNull {
                try {
                    treeEntry(it.uri)
                } catch (error: Exception) {
                    // A folder that was moved or deleted since it was granted.
                    // Nothing to do about it; leave it out of the list.
                    null
                }
            }

    /**
     * Dart holds folders as the document URIs [treeEntry] hands out, but the
     * grant is held on the tree those were built from, so releasing the
     * document URI would silently do nothing.
     */
    private fun forgetTree(uri: Uri) {
        context.contentResolver.releasePersistableUriPermission(
            treeOf(uri),
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        )
    }

    /**
     * A tree URI names the folder that was granted, and is not itself a
     * document URI — asking it for a display name gives nothing back until it
     * is turned into one.
     */
    private fun treeEntry(tree: Uri): Map<String, Any?> {
        val documentId = DocumentsContract.getTreeDocumentId(tree)
        val document = DocumentsContract.buildDocumentUriUsingTree(tree, documentId)

        val entry = query(document)
            ?: mapOf(
                "uri" to document.toString(),
                "name" to (documentId.substringAfterLast(':').substringAfterLast('/')),
                "isDirectory" to true,
                "size" to 0L,
                "modified" to 0L
            )

        // Children are found through the tree the grant was taken on, so the
        // tree URI has to travel with the folder rather than the document one.
        return entry + mapOf("uri" to document.toString(), "tree" to tree.toString())
    }

    // -- reading ------------------------------------------------------------

    private fun list(directory: Uri): List<Map<String, Any?>> {
        val tree = treeOf(directory)
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(
            tree,
            DocumentsContract.getDocumentId(directory)
        )

        val entries = mutableListOf<Map<String, Any?>>()

        context.contentResolver.query(children, COLUMNS, null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                entries.add(rowToEntry(cursor, tree))
            }
        }

        return entries
    }

    /**
     * One named child. Going through [list] rather than building the child's
     * URI by hand, because a document id is the provider's business and only
     * happens to look like a path on some of them.
     */
    private fun child(directory: Uri, name: String): Map<String, Any?>? =
        list(directory).firstOrNull { it["name"] == name }

    private fun read(file: Uri): ByteArray {
        context.contentResolver.openInputStream(file).use { input ->
            if (input == null) throw IllegalStateException("Could not open $file")

            val buffer = ByteArrayOutputStream()
            val chunk = ByteArray(64 * 1024)

            while (true) {
                val read = input.read(chunk)
                if (read <= 0) break
                buffer.write(chunk, 0, read)
            }

            return buffer.toByteArray()
        }
    }

    // -- writing ------------------------------------------------------------

    private fun write(file: Uri, bytes: ByteArray) {
        // "wt" truncates. Plain "w" leaves whatever of the old file ran past
        // the end of the new one, which turns a chart that lost a few notes
        // into a chart with garbage after its closing brace. Not every provider
        // takes "wt", so the fallback truncates the file itself first.
        val output = try {
            context.contentResolver.openOutputStream(file, "wt")
        } catch (error: IllegalArgumentException) {
            truncate(file)
            context.contentResolver.openOutputStream(file, "w")
        } ?: throw IllegalStateException("Could not write to $file")

        output.use {
            it.write(bytes)
            it.flush()
        }
    }

    /** Empty a file for a provider that will not truncate on open. */
    private fun truncate(file: Uri) {
        context.contentResolver.openFileDescriptor(file, "w")?.use { descriptor ->
            android.system.Os.ftruncate(descriptor.fileDescriptor, 0)
        }
    }

    private fun createChild(directory: Uri, name: String, isDirectory: Boolean): Map<String, Any?> {
        val existing = child(directory, name)
        if (existing != null) return existing

        val mime = if (isDirectory) {
            DocumentsContract.Document.MIME_TYPE_DIR
        } else {
            mimeForName(name)
        }

        val created = DocumentsContract.createDocument(
            context.contentResolver,
            directory,
            mime,
            name
        ) ?: throw IllegalStateException("Could not create $name")

        // Providers are free to rename around a clash, so what comes back is
        // read rather than assumed.
        return query(created) ?: mapOf(
            "uri" to created.toString(),
            "name" to name,
            "isDirectory" to isDirectory,
            "size" to 0L,
            "modified" to 0L
        )
    }

    private fun mimeForName(name: String): String = when (name.substringAfterLast('.', "")) {
        "json" -> "application/json"
        "xml" -> "text/xml"
        "txt" -> "text/plain"
        "png" -> "image/png"
        "ogg" -> "audio/ogg"
        "mp3" -> "audio/mpeg"
        else -> "application/octet-stream"
    }

    // -- plumbing -----------------------------------------------------------

    private fun query(document: Uri): Map<String, Any?>? {
        context.contentResolver.query(document, COLUMNS, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) return rowToEntry(cursor, treeOf(document))
        }
        return null
    }

    private fun rowToEntry(cursor: Cursor, tree: Uri): Map<String, Any?> {
        val documentId = cursor.getString(0)
        val name = cursor.getString(1) ?: documentId.substringAfterLast('/')
        val mime = cursor.getString(2)
        val size = if (cursor.isNull(3)) 0L else cursor.getLong(3)
        val modified = if (cursor.isNull(4)) 0L else cursor.getLong(4)

        return mapOf(
            "uri" to DocumentsContract.buildDocumentUriUsingTree(tree, documentId).toString(),
            "name" to name,
            "isDirectory" to (mime == DocumentsContract.Document.MIME_TYPE_DIR),
            "size" to size,
            "modified" to modified,
            "tree" to tree.toString()
        )
    }

    /**
     * The tree a document URI belongs to. Children can only be listed through
     * the tree the grant was taken on, and a document URI built from one keeps
     * that tree in its own path, so it can be recovered rather than tracked.
     */
    private fun treeOf(document: Uri): Uri {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && DocumentsContract.isTreeUri(document)) {
            val treeId = DocumentsContract.getTreeDocumentId(document)
            return DocumentsContract.buildTreeDocumentUri(document.authority, treeId)
        }
        return document
    }

    companion object {
        const val PICK_TREE_REQUEST = 0x5AF0

        private val COLUMNS = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED
        )
    }
}
