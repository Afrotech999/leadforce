package com.loomsolutions.campaign_sms

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings

/**
 * Battery optimisation, which is the single most likely thing to kill a campaign
 * halfway through.
 *
 * A foreground service with a wake lock is supposed to survive, and on stock
 * Android it does. On the phones this app is actually used on it often does not:
 * the aggressive OEM power managers treat any long-running service as a battery
 * leak and stop it. The engine recovers — journalling means it resumes at the
 * next unsent contact — but the user is left staring at a batch that stopped for
 * no visible reason.
 *
 * Exempting the app is the fix, and it has to be the user's choice: Android only
 * accepts it from a dialog they answer themselves.
 */
object Battery {

    fun isOptimized(ctx: Context): Boolean {
        val pm = ctx.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return false
        return !pm.isIgnoringBatteryOptimizations(ctx.packageName)
    }

    /**
     * Asks for the exemption directly, falling back to the system list if this OEM
     * refuses the direct dialog. Returns null on success, or a reason.
     */
    @Suppress("BatteryLife") // Deliberate: a paced send loop must outlive Doze.
    fun requestExemption(ctx: Context): String? {
        if (!isOptimized(ctx)) return null
        val direct = Intent(
            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
            Uri.parse("package:${ctx.packageName}")
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            ctx.startActivity(direct)
            null
        } catch (_: Exception) {
            try {
                ctx.startActivity(
                    Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
                null
            } catch (e: Exception) {
                e.message ?: "This phone does not expose that setting."
            }
        }
    }
}
