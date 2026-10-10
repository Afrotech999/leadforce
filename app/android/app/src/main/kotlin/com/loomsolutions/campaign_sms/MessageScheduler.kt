package com.loomsolutions.campaign_sms

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * "Send this to one person at this time."
 *
 * The same shape as [Scheduler] but for a single personal message rather than
 * a campaign: the `scheduled_message` row is the schedule, the alarm only
 * wakes us, and a reboot rebuilds every alarm from the table. The row is
 * deleted once the message has been journalled, so a duplicate alarm — the
 * classic way scheduled sends go out twice — finds nothing to send.
 */
object MessageScheduler {

    private const val ACTION_FIRE = "com.loomsolutions.campaign_sms.MESSAGE_FIRE"
    private const val EXTRA_ID = "scheduled_message_id"

    private fun pending(ctx: Context, id: Long): PendingIntent {
        val intent = Intent(ctx, MessageReceiver::class.java)
            .setAction(ACTION_FIRE)
            .putExtra(EXTRA_ID, id)
        return PendingIntent.getBroadcast(
            ctx,
            // Offset well clear of Scheduler's campaign request codes.
            (id + 500000).toInt(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    fun schedule(ctx: Context, id: Long, atMillis: Long) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pending(ctx, id))
        Log.i(Const.TAG, "message $id scheduled for $atMillis")
    }

    fun cancel(ctx: Context, id: Long) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(pending(ctx, id))
    }

    /**
     * Claims the row and sends it. Claiming first — read then delete inside one
     * transaction — is what makes a double alarm harmless.
     */
    fun fire(ctx: Context, id: Long) {
        val claimed = CampaignDb.use(ctx) { db ->
            db.beginTransaction()
            try {
                val row = db.rawQuery(
                    "SELECT contact_id, body FROM scheduled_message WHERE id = ?",
                    arrayOf(id.toString())
                ).use { c ->
                    if (c.moveToFirst()) c.getLong(0) to c.getString(1) else null
                }
                if (row != null) {
                    db.execSQL("DELETE FROM scheduled_message WHERE id = ?", arrayOf<Any?>(id))
                }
                db.setTransactionSuccessful()
                row
            } finally {
                db.endTransaction()
            }
        } ?: return

        val (contactId, body) = claimed
        val error = PersonalSend.send(ctx, contactId, body ?: "")
        if (error != null) {
            Notifications.alert(
                ctx,
                "Scheduled message not sent",
                "$error — the message is in the conversation, marked failed."
            )
        }
    }

    /** After a reboot the alarms are gone; the table still knows. */
    fun rearmAfterBoot(ctx: Context) {
        val rows = CampaignDb.use(ctx) { db ->
            val out = mutableListOf<Pair<Long, Long>>()
            try {
                db.rawQuery("SELECT id, send_at FROM scheduled_message", null).use { c ->
                    while (c.moveToNext()) out.add(c.getLong(0) to c.getLong(1))
                }
            } catch (e: Exception) {
                // A database this app has not yet migrated has no such table.
                Log.w(Const.TAG, "no scheduled messages to re-arm", e)
            }
            out
        } ?: return
        val now = System.currentTimeMillis()
        for ((id, at) in rows) {
            if (at <= now) fire(ctx, id) else schedule(ctx, id, at)
        }
    }

    class MessageReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != ACTION_FIRE) return
            val id = intent.getLongExtra(EXTRA_ID, -1L)
            if (id <= 0) return
            val ctx = context.applicationContext
            val pending = goAsync()
            Thread {
                try {
                    fire(ctx, id)
                } catch (e: Exception) {
                    Log.e(Const.TAG, "scheduled message failed", e)
                } finally {
                    pending.finish()
                }
            }.start()
        }
    }
}
