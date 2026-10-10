package com.loomsolutions.campaign_sms

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Scheduled sending (planned feature, approved): one alarm per scheduled
 * campaign, firing a broadcast that promotes the row to `in_progress` and
 * wakes the ordinary send service. The campaign row itself is the schedule —
 * the alarm is only the wake-up call, which is why a reboot can rebuild every
 * alarm from the database alone.
 *
 * `setAndAllowWhileIdle` rather than an exact alarm: exact alarms need their
 * own permission grant on Android 12+, and a campaign that starts at 9:03
 * instead of 9:00 is indistinguishable from one that started on time.
 */
object Scheduler {

    private const val ACTION_FIRE = "com.loomsolutions.campaign_sms.SCHEDULE_FIRE"
    private const val EXTRA_CAMPAIGN_ID = "campaign_id"

    private fun pending(ctx: Context, campaignId: Long): PendingIntent {
        val intent = Intent(ctx, ScheduleReceiver::class.java)
            .setAction(ACTION_FIRE)
            .putExtra(EXTRA_CAMPAIGN_ID, campaignId)
        return PendingIntent.getBroadcast(
            ctx,
            campaignId.toInt(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    fun schedule(ctx: Context, campaignId: Long, atMillis: Long) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pending(ctx, campaignId))
        Log.i(Const.TAG, "campaign $campaignId scheduled for $atMillis")
    }

    fun cancel(ctx: Context, campaignId: Long) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(pending(ctx, campaignId))
    }

    /**
     * Flips a scheduled campaign live. Guarded on status so a stale alarm for
     * a cancelled schedule promotes nothing.
     */
    fun fire(ctx: Context, campaignId: Long) {
        val promoted = CampaignDb.use(ctx) { db ->
            db.execSQL(
                "UPDATE campaign SET status = 'in_progress', started_at = ? " +
                    "WHERE id = ? AND status = 'scheduled'",
                arrayOf<Any?>(System.currentTimeMillis(), campaignId)
            )
            db.rawQuery(
                "SELECT COUNT(*) FROM campaign WHERE id = ? AND status = 'in_progress'",
                arrayOf(campaignId.toString())
            ).use { c -> c.moveToFirst() && c.getInt(0) > 0 }
        } ?: false
        if (promoted) {
            Log.i(Const.TAG, "scheduled campaign $campaignId firing")
            SendService.start(ctx)
        }
    }

    /**
     * After a reboot every alarm is gone; the database still knows. Overdue
     * schedules fire immediately, future ones are re-armed.
     */
    fun rearmAfterBoot(ctx: Context) {
        val rows = CampaignDb.use(ctx) { db ->
            val out = mutableListOf<Pair<Long, Long>>()
            try {
                db.rawQuery(
                    "SELECT id, COALESCE(scheduled_at, 0) FROM campaign WHERE status = 'scheduled'",
                    null
                ).use { c ->
                    while (c.moveToNext()) out.add(c.getLong(0) to c.getLong(1))
                }
            } catch (e: Exception) {
                // A database the app has not yet migrated has no scheduled_at
                // column — and can have no schedules either.
                Log.w(Const.TAG, "no schedules to re-arm", e)
            }
            out
        } ?: return
        val now = System.currentTimeMillis()
        for ((id, at) in rows) {
            if (at <= now) fire(ctx, id) else schedule(ctx, id, at)
        }
    }

    class ScheduleReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != ACTION_FIRE) return
            val id = intent.getLongExtra(EXTRA_CAMPAIGN_ID, -1L)
            if (id > 0) fire(context.applicationContext, id)
        }
    }
}
