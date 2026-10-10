package com.loomsolutions.campaign_sms

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import java.io.File

/**
 * The receiving end of "Share → LeadForce".
 *
 * A share from another app hands over content URIs that expire with the
 * moment — Telegram's photo URI is dead by the time the user has answered
 * "who sent this?". So everything is copied into the app's own storage the
 * instant the intent arrives, and only the copies' paths travel onward.
 * Nothing here touches the network; a share is Android moving bytes between
 * two apps on the same phone.
 */
object ShareIn {

    data class Payload(val text: String, val photos: List<String>)

    /** Null when [intent] is not a share. Never throws — a bad share is no share. */
    fun from(ctx: Context, intent: Intent?): Payload? {
        if (intent == null) return null
        val uris: List<Uri> = when (intent.action) {
            Intent.ACTION_SEND ->
                listOfNotNull(extraUri(intent))
            Intent.ACTION_SEND_MULTIPLE ->
                extraUris(intent) ?: emptyList()
            else -> return null
        }
        val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: ""
        if (uris.isEmpty() && text.isBlank()) return null

        val dir = File(ctx.filesDir, "cars").apply { mkdirs() }
        val stamp = System.currentTimeMillis()
        val photos = mutableListOf<String>()
        // A share of many photos is capped: a channel post is 1-10 images,
        // and an accidental "share whole gallery" should not fill the phone.
        for ((i, uri) in uris.take(10).withIndex()) {
            try {
                val out = File(dir, "car_${stamp}_$i.jpg")
                ctx.contentResolver.openInputStream(uri)?.use { input ->
                    out.outputStream().use { input.copyTo(it) }
                }
                if (out.length() > 0) photos.add(out.absolutePath) else out.delete()
            } catch (e: Exception) {
                // One unreadable photo must not sink the share.
                Log.w(Const.TAG, "share photo copy failed", e)
            }
        }
        if (photos.isEmpty() && text.isBlank()) return null
        return Payload(text, photos)
    }

    /**
     * Moves a picked file (already copied to cache by [FilePick]) into the
     * permanent car-photo directory. Cache is fair game for Android to clear;
     * a car photo has to outlive next Tuesday.
     */
    fun intoCars(ctx: Context, cachePath: String): String? {
        return try {
            val source = File(cachePath)
            if (!source.exists() || source.length() == 0L) return null
            val dir = File(ctx.filesDir, "cars").apply { mkdirs() }
            val target = File(dir, "car_${System.currentTimeMillis()}_p.jpg")
            source.copyTo(target, overwrite = true)
            source.delete()
            target.absolutePath
        } catch (e: Exception) {
            Log.w(Const.TAG, "photo import failed", e)
            null
        }
    }

    @Suppress("DEPRECATION")
    private fun extraUri(intent: Intent): Uri? =
        if (android.os.Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }

    @Suppress("DEPRECATION")
    private fun extraUris(intent: Intent): List<Uri>? =
        if (android.os.Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
        }
}
