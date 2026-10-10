package com.loomsolutions.campaign_sms

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Log
import java.io.File

/**
 * Document picking via the Storage Access Framework.
 *
 * Done natively for the same reason as [Permissions]: `file_picker` skips applying the
 * Kotlin Gradle plugin when it detects AGP 9 and relies on AGP's built-in Kotlin
 * support, which the Flutter template turns off (`android.builtInKotlin=false`). Its
 * Kotlin therefore never compiles and its plugin class does not exist at link time.
 * This is fifty lines and depends on nothing.
 */
object FilePick {

    const val REQUEST_CODE = 4713

    fun intent(): Intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
        .addCategory(Intent.CATEGORY_OPENABLE)
        .setType("*/*")

    fun launch(activity: Activity) {
        activity.startActivityForResult(intent(), REQUEST_CODE)
    }

    /**
     * SAF hands back a `content://` URI, which Dart's `File` cannot open. Copy it into
     * the cache directory and return a real path. Imports and backups are small.
     */
    fun copyToCache(ctx: Context, uri: Uri): String? {
        return try {
            val name = displayName(ctx, uri) ?: "picked-file"
            val target = File(ctx.cacheDir, "picked-${System.currentTimeMillis()}-$name")
            ctx.contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            } ?: return null
            target.absolutePath
        } catch (e: Exception) {
            Log.e(Const.TAG, "could not copy picked file", e)
            null
        }
    }

    private fun displayName(ctx: Context, uri: Uri): String? {
        return try {
            ctx.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { c ->
                    if (c.moveToFirst() && !c.isNull(0)) {
                        c.getString(0).replace(Regex("[^A-Za-z0-9._-]"), "_")
                    } else {
                        null
                    }
                }
        } catch (e: Exception) {
            null
        }
    }
}
