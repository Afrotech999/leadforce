package com.loomsolutions.campaign_sms

import android.app.Activity
import android.app.role.RoleManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.provider.Telephony

/**
 * Default-SMS-app role handling (spec 9).
 *
 * Android will not let an app silently take or give back the role; every path below
 * ends in a system dialog the user confirms. What we can do is make it one tap and
 * remember which app to hand the role back to.
 */
object DefaultSmsRole {

    const val REQUEST_CODE = 4711

    fun currentDefaultPackage(ctx: Context): String? =
        try {
            Telephony.Sms.getDefaultSmsPackage(ctx)
        } catch (e: Exception) {
            null
        }

    fun isDefault(ctx: Context): Boolean = ctx.packageName == currentDefaultPackage(ctx)

    fun requestIntent(ctx: Context): Intent =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val rm = ctx.getSystemService(RoleManager::class.java)
            rm.createRequestRoleIntent(RoleManager.ROLE_SMS)
        } else {
            @Suppress("DEPRECATION")
            Intent(Telephony.Sms.Intents.ACTION_CHANGE_DEFAULT)
                .putExtra(Telephony.Sms.Intents.EXTRA_PACKAGE_NAME, ctx.packageName)
        }

    /**
     * Hands the role back. ACTION_CHANGE_DEFAULT still works above API 29 and is the
     * only way to propose a *specific* app, so we prefer it over dumping the user in
     * the default-apps settings screen. If we never recorded a previous app, fall back
     * to the settings screen.
     */
    fun restoreIntent(ctx: Context, previousPackage: String?): Intent {
        if (!previousPackage.isNullOrBlank() && previousPackage != ctx.packageName) {
            @Suppress("DEPRECATION")
            return Intent(Telephony.Sms.Intents.ACTION_CHANGE_DEFAULT)
                .putExtra(Telephony.Sms.Intents.EXTRA_PACKAGE_NAME, previousPackage)
        }
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS)
        } else {
            Intent(Settings.ACTION_SETTINGS)
        }
    }

    fun appLabel(ctx: Context, packageName: String?): String? {
        if (packageName.isNullOrBlank()) return null
        return try {
            val pm = ctx.packageManager
            pm.getApplicationLabel(pm.getApplicationInfo(packageName, 0)).toString()
        } catch (e: Exception) {
            packageName
        }
    }

    /** Remembers whichever app is default right now, so we can offer to restore it later. */
    fun rememberPrevious(ctx: Context) {
        val current = currentDefaultPackage(ctx) ?: return
        if (current == ctx.packageName) return
        CampaignDb.use(ctx) { db -> CampaignDb.putSetting(db, Const.S_PREVIOUS_SMS_APP, current) }
    }

    fun launch(activity: Activity, intent: Intent) {
        activity.startActivityForResult(intent, REQUEST_CODE)
    }
}
