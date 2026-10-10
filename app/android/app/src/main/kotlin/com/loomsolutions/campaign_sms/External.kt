package com.loomsolutions.campaign_sms

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log

/**
 * Hands a `tel:` / `mailto:` / `https:` link to whatever app owns it.
 *
 * Written by hand rather than pulled in with `url_launcher` for the same reason as
 * [FilePick] and [Permissions]: every Flutter plugin added to this project so far has
 * cost a build fight with AGP 9, and this is nine lines.
 */
object External {

    /** Returns null on success, or a human-readable reason it did not open. */
    fun open(ctx: Context, url: String): String? {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            ctx.startActivity(intent)
            null
        } catch (e: ActivityNotFoundException) {
            "No app on this phone can open that."
        } catch (e: Exception) {
            Log.w(Const.TAG, "open $url failed", e)
            e.message ?: "Could not open that link."
        }
    }

    /**
     * The app's own page in the phone settings. The way back in once Android
     * has decided to stop showing a permission dialog: after two denials the
     * request comes back refused without a prompt, and settings is the only
     * place left where the user can change their mind.
     */
    fun openAppSettings(ctx: Context): Boolean = try {
        ctx.startActivity(
            Intent(
                android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", ctx.packageName, null)
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        true
    } catch (e: Exception) {
        Log.w(Const.TAG, "open app settings failed", e)
        false
    }
}
