package com.loomsolutions.campaign_sms

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.RemoteInput

/**
 * The buttons on an incoming-message notification: reply without opening the
 * app, and mark it read.
 *
 * A reply typed in the shade has to work when no Flutter engine exists — the
 * app may have been swiped away hours ago — so this is native end to end and
 * goes through [PersonalSend], the same journal-then-radio path everything
 * else uses.
 */
class NotificationActions : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val ctx = context.applicationContext
        // Dismiss needs no contact — it only clears the shade, so it is
        // handled before the contact guard.
        if (intent.action == ACTION_DISMISS) {
            cancel(ctx, intent.getIntExtra(EXTRA_NOTIFICATION_ID, -1))
            return
        }
        val contactId = intent.getLongExtra(EXTRA_CONTACT_ID, -1L)
        if (contactId <= 0) return
        val notificationId = intent.getIntExtra(EXTRA_NOTIFICATION_ID, -1)

        when (intent.action) {
            ACTION_REPLY -> {
                val reply = RemoteInput.getResultsFromIntent(intent)
                    ?.getCharSequence(KEY_REPLY)?.toString()?.trim()
                if (reply.isNullOrEmpty()) return
                val pending = goAsync()
                Thread {
                    try {
                        markRead(ctx, contactId)
                        val error = PersonalSend.send(ctx, contactId, reply)
                        // The notification is replaced either way: with the
                        // sent reply, or with why it did not go. Cancelling it
                        // outright on failure would lose the message silently.
                        if (error == null) {
                            cancel(ctx, notificationId)
                        } else {
                            Notifications.replyFailed(ctx, contactId, reply, error, notificationId)
                        }
                    } catch (e: Exception) {
                        Log.e(Const.TAG, "notification reply failed", e)
                    } finally {
                        pending.finish()
                    }
                }.start()
            }

            ACTION_MARK_READ -> {
                val pending = goAsync()
                Thread {
                    try {
                        markRead(ctx, contactId)
                        cancel(ctx, notificationId)
                    } finally {
                        pending.finish()
                    }
                }.start()
            }
        }
    }

    private fun markRead(ctx: Context, contactId: Long) {
        CampaignDb.use(ctx) { db ->
            db.execSQL(
                "UPDATE thread SET unread_count = 0 WHERE contact_id = ?",
                arrayOf<Any?>(contactId)
            )
        }
    }

    private fun cancel(ctx: Context, id: Int) {
        if (id >= 0) NotificationManagerCompat.from(ctx).cancel(id)
    }

    companion object {
        const val ACTION_REPLY = "com.loomsolutions.campaign_sms.NOTIFY_REPLY"
        const val ACTION_DISMISS = "com.loomsolutions.campaign_sms.NOTIFY_DISMISS"
        const val ACTION_MARK_READ = "com.loomsolutions.campaign_sms.NOTIFY_READ"
        const val EXTRA_CONTACT_ID = "contact_id"
        const val EXTRA_NOTIFICATION_ID = "notification_id"
        const val KEY_REPLY = "key_reply_text"
    }
}
