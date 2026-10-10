package com.loomsolutions.campaign_sms

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.annotation.RequiresApi
import androidx.core.content.FileProvider
import java.io.File
import java.io.OutputStream

/**
 * Data-loss defence (spec 11): drop the raw database and a status CSV somewhere the
 * user can actually see them, so a reinstall or a lost phone doesn't lose the campaign.
 */
object Backup {

    private const val FOLDER = "LeadForce"

    /** Returns the human-readable locations written, or throws with a usable message. */
    fun export(ctx: Context, csv: String, stamp: String): List<String> {
        val written = mutableListOf<String>()
        val dbFile = ctx.getDatabasePath(Const.DB_NAME)

        written += write(ctx, "contacts-$stamp.csv", "text/csv") {
            it.write(csv.toByteArray(Charsets.UTF_8))
        }
        if (dbFile.exists()) {
            // Streamed, never `readBytes()`. Years of messages and six
            // thousand contacts make a database of tens of megabytes, and
            // holding all of it in one array to hand to the writer is an
            // out-of-memory kill on the cheap phones this app is for.
            written += write(ctx, "leadforce-$stamp.db", "application/octet-stream") { out ->
                dbFile.inputStream().use { it.copyTo(out) }
            }
        }
        return written
    }

    /**
     * Hands the backup to whatever the user wants to send it with — Gmail,
     * Telegram, Drive.
     *
     * Writing to Documents is a good archive and a poor way to move a phone:
     * the user has to find the file, and on a phone they no longer have they
     * cannot. Sharing puts it somewhere that survives the handset.
     *
     * The copy goes to cache and through a FileProvider, because a raw
     * `file://` on Android 7 and up throws FileUriExposedException the moment
     * another app touches it.
     */
    fun share(ctx: Context, stamp: String): String? {
        val db = ctx.getDatabasePath(Const.DB_NAME)
        if (!db.exists()) return "There is nothing to back up yet."

        return try {
            val outbox = File(ctx.cacheDir, "backup").apply { mkdirs() }
            // One file per share, cleaned each time, so an old backup is never
            // the one that gets sent.
            outbox.listFiles()?.forEach { it.delete() }
            val copy = File(outbox, "leadforce-backup-$stamp.db")
            db.copyTo(copy, overwrite = true)

            val uri = FileProvider.getUriForFile(
                ctx,
                "${ctx.packageName}.files",
                copy
            )
            val send = Intent(Intent.ACTION_SEND).apply {
                type = "application/octet-stream"
                putExtra(Intent.EXTRA_STREAM, uri)
                putExtra(Intent.EXTRA_SUBJECT, "LeadForce backup")
                putExtra(
                    Intent.EXTRA_TEXT,
                    "LeadForce backup taken $stamp. Open LeadForce on the " +
                        "new phone, go to Settings and choose Restore from backup."
                )
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            ctx.startActivity(
                Intent.createChooser(send, "Send backup")
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            null
        } catch (e: Exception) {
            e.message ?: "Could not share the backup."
        }
    }

    /**
     * Opens the destination and hands [body] the stream to fill. Callers write
     * into it rather than handing over a finished array, so a file bigger than
     * comfortable memory is never held whole.
     */
    private fun write(ctx: Context, name: String, mime: String, body: (OutputStream) -> Unit): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            writeViaMediaStore(ctx, name, mime, body)
        } else {
            writeLegacy(name, body)
        }
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun writeViaMediaStore(
        ctx: Context,
        name: String,
        mime: String,
        body: (OutputStream) -> Unit
    ): String {
        val relative = "${Environment.DIRECTORY_DOCUMENTS}/$FOLDER"
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relative)
        }
        val collection = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = ctx.contentResolver.insert(collection, values)
            ?: throw IllegalStateException("Could not create $name in Documents/$FOLDER")
        try {
            ctx.contentResolver.openOutputStream(uri)?.use(body)
                ?: throw IllegalStateException("Could not write $name")
        } catch (e: Exception) {
            // A half-written backup in the user's Documents is worse than
            // none: it looks like a backup and restores as a corrupt file.
            runCatching { ctx.contentResolver.delete(uri, null, null) }
            throw e
        }
        return "Documents/$FOLDER/$name"
    }

    @Suppress("DEPRECATION")
    private fun writeLegacy(name: String, body: (OutputStream) -> Unit): String {
        val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS), FOLDER)
        if (!dir.exists() && !dir.mkdirs()) {
            throw IllegalStateException("Could not create ${dir.absolutePath}")
        }
        val f = File(dir, name)
        try {
            f.outputStream().use(body)
        } catch (e: Exception) {
            runCatching { f.delete() }
            throw e
        }
        return f.absolutePath
    }
}
