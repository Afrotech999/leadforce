package com.loomsolutions.campaign_sms

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

/**
 * Runtime permissions, done directly rather than through a plugin.
 *
 * `permission_handler` would be the obvious choice, but its current Android artifact
 * requires compiling against API 37, and the Android Gradle plugin Flutter ships tops
 * out at 36. This is thirty lines and has no such opinion.
 */
object Permissions {

    const val REQUEST_CODE = 4712
    const val CONTACTS_REQUEST_CODE = 4714
    const val CALL_LOG_REQUEST_CODE = 4716

    /** Everything the send engine needs before it can touch the radio. */
    private fun required(): Array<String> {
        val perms = mutableListOf(
            Manifest.permission.SEND_SMS,
            Manifest.permission.RECEIVE_SMS,
            Manifest.permission.READ_SMS,
            Manifest.permission.READ_PHONE_STATE
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            perms.add(Manifest.permission.READ_PHONE_NUMBERS)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            perms.add(Manifest.permission.POST_NOTIFICATIONS)
        }
        return perms.toTypedArray()
    }

    private fun granted(ctx: Context, permission: String): Boolean =
        ContextCompat.checkSelfPermission(ctx, permission) == PackageManager.PERMISSION_GRANTED

    /**
     * SEND_SMS is the only one a campaign cannot proceed without. Notifications and
     * phone state degrade gracefully — no progress notification, no SIM picker — so
     * they are requested but not required.
     */
    fun hasSending(ctx: Context): Boolean = granted(ctx, Manifest.permission.SEND_SMS)

    fun request(activity: Activity) {
        ActivityCompat.requestPermissions(activity, required(), REQUEST_CODE)
    }

    fun hasContacts(ctx: Context): Boolean = granted(ctx, Manifest.permission.READ_CONTACTS)

    /// Asked only when importing from the phone book, never bundled with the SMS
    /// permissions — reading someone's address book deserves its own prompt.
    fun requestContacts(activity: Activity) {
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.READ_CONTACTS),
            CONTACTS_REQUEST_CODE,
        )
    }

    fun hasCallLog(ctx: Context): Boolean = granted(ctx, Manifest.permission.READ_CALL_LOG)

    /// Its own prompt, like contacts: the call log is at least as private as
    /// the phone book and is never bundled into the SMS request.
    fun requestCallLog(activity: Activity) {
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.READ_CALL_LOG),
            CALL_LOG_REQUEST_CODE,
        )
    }
}
