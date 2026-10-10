package com.loomsolutions.campaign_sms

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Reminders for appointments — a viewing, a meeting, a call-back.
 *
 * Same shape as [MessageScheduler] and for the same reasons: the row is the
 * schedule, the alarm is only the wake-up call, and a reboot rebuilds every
 * alarm from the table. Unlike a scheduled message this sends nothing — it
 * raises a notification and leaves the doing to the person.
 *
 * The row is NOT deleted when it fires. A reminder that has gone off is still
 * an appointment that has not happened yet; only the user marking it done, or
 * deleting it, takes it off the list.
 */
object AppointmentScheduler {

    private const val ACTION_FIRE = "com.loomsolutions.campaign_sms.APPOINTMENT_FIRE"
    private const val EXTRA_ID = "appointment_id"

    private fun pending(ctx: Context, id: Long): PendingIntent {
        val intent = Intent(ctx, AppointmentReceiver::class.java)
            .setAction(ACTION_FIRE)
            .putExtra(EXTRA_ID, id)
        return PendingIntent.getBroadcast(
            ctx,
            // Clear of both Scheduler's campaign codes and MessageScheduler's.
            (id + 900000).toInt(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    fun schedule(ctx: Context, id: Long, atMillis: Long) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pending(ctx, id))
        Log.i(Const.TAG, "appointment $id reminder set for $atMillis")
    }

    fun cancel(ctx: Context, id: Long) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(pending(ctx, id))
    }

    fun fire(ctx: Context, id: Long) {
        val row = CampaignDb.use(ctx) { db ->
            db.rawQuery(
                "SELECT a.title, a.place, a.at, a.done, a.contact_id, c.name, c.phone_local " +
                    "FROM appointment a LEFT JOIN contact c ON c.id = a.contact_id " +
                    "WHERE a.id = ?",
                arrayOf(id.toString())
            ).use { c ->
                if (!c.moveToFirst()) null
                else Reminder(
                    title = c.getString(0) ?: "Appointment",
                    place = c.getString(1),
                    at = c.getLong(2),
                    done = c.getInt(3) == 1,
                    contactId = if (c.isNull(4)) 0L else c.getLong(4),
                    who = c.getString(5)?.takeIf { it.isNotBlank() } ?: c.getString(6)
                )
            }
        } ?: return
        // Marked done between the alarm being set and it going off.
        if (row.done) return

        Notifications.appointment(
            ctx,
            id = id,
            title = row.title,
            who = row.who,
            place = row.place,
            at = row.at,
            contactId = row.contactId
        )
    }

    fun rearmAfterBoot(ctx: Context) {
        val rows = CampaignDb.use(ctx) { db ->
            val out = mutableListOf<Pair<Long, Long>>()
            try {
                db.rawQuery(
                    "SELECT id, remind_at FROM appointment WHERE done = 0",
                    null
                ).use { c ->
                    while (c.moveToNext()) out.add(c.getLong(0) to c.getLong(1))
                }
            } catch (e: Exception) {
                Log.w(Const.TAG, "no appointments to re-arm", e)
            }
            out
        } ?: return
        val now = System.currentTimeMillis()
        // A reminder whose moment passed while the phone was off is not raised
        // late — an alert for a viewing that already started is noise. The
        // appointment itself stays on the list, which is where it will be seen.
        for ((id, at) in rows) {
            if (at > now) schedule(ctx, id, at)
        }
    }

    private data class Reminder(
        val title: String,
        val place: String?,
        val at: Long,
        val done: Boolean,
        val contactId: Long,
        val who: String?
    )

    class AppointmentReceiver : BroadcastReceiver() {
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
                    Log.e(Const.TAG, "appointment reminder failed", e)
                } finally {
                    pending.finish()
                }
            }.start()
        }
    }
}
