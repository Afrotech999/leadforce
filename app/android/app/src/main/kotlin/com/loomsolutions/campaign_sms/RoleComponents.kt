package com.loomsolutions.campaign_sms

import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.os.IBinder
import android.util.Log

/**
 * MMS delivery. Android requires a WAP_PUSH_DELIVER receiver before it will offer an
 * app as the default SMS handler (spec 9.1). This app does not implement MMS, so the
 * receiver exists purely to satisfy the role contract.
 */
class MmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.i(Const.TAG, "MMS received; this app does not handle MMS content")
    }
}

/**
 * "Respond via message" from the in-call screen. Required for default-SMS-app
 * eligibility (spec 9.1). Declining to auto-send is deliberate: quick responses would
 * bypass the campaign journal.
 */
class HeadlessSmsSendService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        stopSelf(startId)
        return START_NOT_STICKY
    }
}

/**
 * Resumes an interrupted campaign after a reboot (spec 2.5). The service itself decides
 * whether there is anything to do — if no campaign is `in_progress`, it stops instantly.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val ctx = context.applicationContext
        val hasWork = CampaignDb.use(ctx) { db: SQLiteDatabase ->
            db.rawQuery("SELECT COUNT(*) FROM campaign WHERE status = 'in_progress'", null).use { c ->
                c.moveToFirst() && c.getInt(0) > 0
            }
        } ?: false
        if (hasWork) {
            Log.i(Const.TAG, "resuming interrupted campaign after boot")
            SendService.start(ctx)
        }
        // Alarms do not survive a reboot; the schedule rows do.
        Scheduler.rearmAfterBoot(ctx)
        MessageScheduler.rearmAfterBoot(ctx)
        AppointmentScheduler.rearmAfterBoot(ctx)
    }
}
