package com.loomsolutions.campaign_sms

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.database.sqlite.SQLiteDatabase
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import java.util.concurrent.TimeUnit

/**
 * The send engine (spec 7). Foreground service + wake lock, one message at a time,
 * journalled to the database *before* each send.
 *
 * Everything it needs is in the database: the campaign row with `status = 'in_progress'`
 * is the whole instruction set. That is what makes resume-after-death trivial — the
 * service is restarted by the system (or by the app on launch) and simply picks the
 * campaign back up.
 *
 * The UI does not get pushed progress events; it polls the same database. One source
 * of truth, no event ordering to get wrong.
 */
class SendService : Service() {

    companion object {
        const val ACTION_START = "com.loomsolutions.campaign_sms.START"
        const val ACTION_PAUSE = "com.loomsolutions.campaign_sms.PAUSE"
        const val ACTION_RESUME = "com.loomsolutions.campaign_sms.RESUME"
        const val ACTION_STOP = "com.loomsolutions.campaign_sms.STOP"

        @Volatile
        private var running = false

        @Volatile
        private var paused = false

        @Volatile
        private var stopRequested = false

        fun start(ctx: Context) {
            val i = Intent(ctx, SendService::class.java).setAction(ACTION_START)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) ctx.startForegroundService(i)
            else ctx.startService(i)
        }

        fun signal(ctx: Context, action: String) {
            ctx.startService(Intent(ctx, SendService::class.java).setAction(action))
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var worker: Thread? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        Notifications.ensureChannels(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        // A control signal for a loop that is not running would otherwise leave a bare
        // service instance alive forever (it never calls startForeground).
        if (!running && action != null && action != ACTION_START) {
            stopSelf(startId)
            return START_NOT_STICKY
        }

        when (action) {
            ACTION_PAUSE -> {
                paused = true
                setEngineState("paused")
                pushNotification("Campaign paused", "Tap Resume to continue", 0, 0)
                return START_STICKY
            }
            ACTION_RESUME -> {
                paused = false
                setEngineState("running")
            }
            ACTION_STOP -> {
                stopRequested = true
                paused = false
                return START_STICKY
            }
        }

        // Resume of a system-restarted service (intent == null after process death)
        // falls through here and picks the in-progress campaign back up.

        startForegroundSafely("Preparing…", "", 0, 0)

        if (running) return START_STICKY
        running = true
        stopRequested = false
        paused = false

        acquireWakeLock()
        worker = Thread({ runLoopSafely() }, "campaign-send-loop").also { it.start() }
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        releaseWakeLock()
        super.onDestroy()
    }

    // ---------------------------------------------------------------- loop

    private fun runLoopSafely() {
        try {
            runLoop()
        } catch (e: Exception) {
            Log.e(Const.TAG, "send loop crashed", e)
            CampaignDb.use(this) { db -> CampaignDb.putSetting(db, Const.S_ENGINE_STATE, "idle") }
        } finally {
            running = false
            releaseWakeLock()
            stopForegroundCompat()
            stopSelf()
        }
    }

    private data class Campaign(
        val id: Long,
        val batchId: Long,
        val template: String,
        val subId: Int?,
        val delaySeconds: Int,
        val fallbackName: String
    )

    private data class Target(val id: Long, val phone: String, val name: String?)

    private fun runLoop() {
        val db = CampaignDb.open(this) ?: return
        try {
            val campaign = findInProgressCampaign(db)
            if (campaign == null) {
                CampaignDb.putSetting(db, Const.S_ENGINE_STATE, "idle")
                return
            }

            CampaignDb.putSetting(db, Const.S_ENGINE_STATE, "running")
            CampaignDb.putSetting(db, Const.S_CAMPAIGN_ACTIVE, "1")
            reconcileInterrupted(db, campaign)
            // Contacts left stranded by an earlier wedged send, from this campaign
            // or any other, become retryable rather than sitting invisible.
            CampaignDb.sweepStalePending(db)

            val dailyCap = CampaignDb.settingInt(db, Const.S_DAILY_CAP, 100)
            val capSegments = CampaignDb.settingInt(db, Const.S_CAP_COUNTS_SEGMENTS, 1) == 1
            val quietOn = CampaignDb.settingInt(db, Const.S_QUIET_ENABLED, 1) == 1
            val quietStart = CampaignDb.settingInt(db, Const.S_QUIET_START, 21)
            val quietEnd = CampaignDb.settingInt(db, Const.S_QUIET_END, 8)
            val total = countInBatch(db, campaign.batchId)
            var untilBreak = Pacing.messagesUntilBreak()
            // Out-of-credit detector. When the SIM package runs out, every send
            // fails the same way — and without this the loop would walk the
            // whole batch marking a hundred people failed at five-second
            // intervals. Three in a row smells like the SIM, not the numbers,
            // so the campaign pauses and waits for a top-up instead.
            var consecutiveFailures = 0

            while (true) {
                if (stopRequested) {
                    finish(db, campaign, campaignStatus = "stopped", batchStatus = "partial")
                    Notifications.alert(
                        this,
                        "Campaign stopped",
                        "Unsent contacts stay in the batch and roll into the next run."
                    )
                    break
                }

                if (paused) {
                    Thread.sleep(400)
                    continue
                }

                if (quietOn && Pacing.isQuietNow(quietStart, quietEnd)) {
                    finish(db, campaign, campaignStatus = "completed", batchStatus = "partial")
                    Notifications.alert(
                        this,
                        "Paused for quiet hours",
                        "It is inside ${Pacing.describeWindow(quietStart, quietEnd)}. The batch is " +
                            "marked partial; the rest go out when you start it again in the morning."
                    )
                    break
                }

                val usedToday = if (capSegments) CampaignDb.segmentsSentToday(db)
                else CampaignDb.sentToday(db)
                val unit = if (capSegments) "SMS" else "messages"
                if (usedToday >= dailyCap) {
                    finish(db, campaign, campaignStatus = "completed", batchStatus = "partial")
                    Notifications.alert(
                        this,
                        "Daily cap reached ($dailyCap $unit)",
                        "The batch is marked partial. Remaining contacts stay unsent and will be picked up tomorrow."
                    )
                    break
                }

                val target = nextTarget(db, campaign.batchId)
                if (target == null) {
                    finish(db, campaign, campaignStatus = "completed", batchStatus = "completed")
                    Notifications.alert(
                        this,
                        "Batch finished",
                        "Remember to switch your default SMS app back."
                    )
                    break
                }

                // Rendered here rather than inside sendOne so the cap can be checked
                // against what this particular message costs. Stopping at 100 after
                // sending a three-segment message would put 102 on the bill.
                val body = render(campaign.template, target.name, campaign.fallbackName)
                val parts = SmsSender.divide(this, campaign.subId, body)
                if (capSegments && usedToday + parts.size > dailyCap) {
                    finish(db, campaign, campaignStatus = "completed", batchStatus = "partial")
                    Notifications.alert(
                        this,
                        "Daily cap reached ($dailyCap SMS)",
                        "The next message needs ${parts.size} SMS and only ${dailyCap - usedToday} " +
                            "are left for today. The batch is marked partial."
                    )
                    break
                }

                val done = countDone(db, campaign.batchId)
                pushNotification(
                    "Sending ${batchName(db, campaign.batchId)}",
                    "${done + 1}/$total · ${Phone.local(target.phone)}",
                    done,
                    total
                )

                val sendOk = sendOne(db, campaign, target, body, parts)
                if (sendOk) {
                    consecutiveFailures = 0
                } else if (++consecutiveFailures >= 3) {
                    consecutiveFailures = 0
                    paused = true
                    setEngineState("paused")
                    Notifications.alert(
                        this,
                        "Paused — 3 messages in a row failed",
                        "This usually means the SMS package on the SIM has run out. " +
                            "Top up, then tap Resume; the failed contacts can be retried after."
                    )
                    pushNotification(
                        "Paused — check your SMS package",
                        "3 sends in a row failed. Top up and resume.",
                        countDone(db, campaign.batchId),
                        total
                    )
                    continue
                }

                var sleepMs = Pacing.nextDelayMs(campaign.delaySeconds)
                if (--untilBreak <= 0) {
                    // Every twenty or so, the pause of someone who put the phone down.
                    sleepMs += Pacing.breakMs()
                    untilBreak = Pacing.messagesUntilBreak()
                }
                var slept = 0L
                while (slept < sleepMs && !stopRequested) {
                    Thread.sleep(200)
                    slept += 200
                }
            }
        } finally {
            try {
                CampaignDb.use(this) { d ->
                    CampaignDb.putSetting(d, Const.S_ENGINE_STATE, "idle")
                }
            } catch (_: Exception) {
            }
            try {
                db.close()
            } catch (_: Exception) {
            }
        }
    }

    /**
     * Returns whether the send is believed to have left the phone. False means it
     * definitely failed — thrown before the radio, or the radio said no. A receipt
     * that never arrives counts as true: unknown is not evidence the SIM is empty.
     */
    private fun sendOne(
        db: SQLiteDatabase,
        campaign: Campaign,
        target: Target,
        body: String,
        parts: ArrayList<String>
    ): Boolean {
        // Journal BEFORE the radio is touched (spec 2.5). If we die right here the
        // message row exists as 'pending' and reconciliation will see it.
        val messageId = CampaignDb.insertOutboundMessage(db, target.id, campaign.id, body, parts.size)
        if (messageId <= 0) return true

        db.execSQL(
            "UPDATE contact SET status = 'queued' WHERE id = ? AND status IN ('not_sent','failed')",
            arrayOf<Any?>(target.id)
        )
        CampaignDb.touchThread(db, target.id, "campaign", body, System.currentTimeMillis(), 0)

        val latch = SendResultReceiver.expect(messageId)
        val error = SmsSender.send(this, target.phone, campaign.subId, parts, messageId)

        if (error != null) {
            // Threw before reaching the radio: settle every part as failed.
            SendResultReceiver.forget(messageId)
            repeat(parts.size) { SendResultReceiver.applyPartResult(db, messageId, false, error) }
            return false
        }

        // The receipt may never come (radio wedged). Cap the wait; the message simply
        // stays 'pending' and is reconciled on the next run rather than being resent.
        val settled = latch.await(90, TimeUnit.SECONDS)
        if (!settled) {
            SendResultReceiver.forget(messageId)
            Log.w(Const.TAG, "no sent receipt for message $messageId within 90s")
            return true
        }
        // The receipt has been applied; read what it said. 'failed' here is the
        // radio's own verdict, which is what the out-of-credit detector needs.
        db.rawQuery(
            "SELECT status FROM message WHERE id = ?",
            arrayOf(messageId.toString())
        ).use { c ->
            return !(c.moveToFirst() && c.getString(0) == "failed")
        }
    }

    /**
     * Renders `{name}`. A contact with no name gets the fallback, and we tidy the
     * "Hello ," that a blank fallback would otherwise leave behind.
     */
    private fun render(template: String, name: String?, fallback: String): String {
        val value = name?.trim().takeUnless { it.isNullOrEmpty() } ?: fallback
        return template.replace("{name}", value)
            .replace(Regex("\\s+([,.!?])"), "$1")
            .replace(Regex("[ \\t]{2,}"), " ")
            .trim()
    }

    // ---------------------------------------------------------------- queries

    private fun findInProgressCampaign(db: SQLiteDatabase): Campaign? {
        val fallback = CampaignDb.setting(db, Const.S_NAME_FALLBACK, "there")
        db.rawQuery(
            "SELECT id, batch_id, message_template, sim_subscription_id, delay_seconds " +
                "FROM campaign WHERE status = 'in_progress' ORDER BY id DESC LIMIT 1",
            null
        ).use { c ->
            if (!c.moveToFirst()) return null
            return Campaign(
                id = c.getLong(0),
                batchId = c.getLong(1),
                template = c.getString(2) ?: "",
                subId = if (c.isNull(3)) null else c.getInt(3),
                delaySeconds = c.getInt(4),
                fallbackName = fallback
            )
        }
    }

    /**
     * Contacts left 'queued' by a process death are ambiguous: the SMS may or may not
     * have left the phone. Spec 12.4 demands zero resends, so we do not gamble — the
     * message is marked failed and the contact drops into the retry queue, where the
     * user decides. A message that already has a 'sent' receipt is reconciled instead.
     */
    private fun reconcileInterrupted(db: SQLiteDatabase, campaign: Campaign) {
        db.execSQL(
            "UPDATE contact SET status = 'sent' WHERE status = 'queued' AND id IN (" +
                "  SELECT contact_id FROM message WHERE direction = 'outbound' " +
                "  AND campaign_id = ? AND status IN ('sent','delivered')" +
                ")",
            arrayOf<Any?>(campaign.id)
        )
        db.execSQL(
            "UPDATE message SET status = 'failed', " +
                "error = COALESCE(error, 'Interrupted - result unknown') " +
                "WHERE status = 'pending' AND campaign_id = ?",
            arrayOf<Any?>(campaign.id)
        )
        db.execSQL(
            "UPDATE contact SET status = 'failed', " +
                "last_error = 'Interrupted - result unknown, retry manually' " +
                "WHERE status = 'queued' AND batch_id = ?",
            arrayOf<Any?>(campaign.batchId)
        )
    }

    private fun nextTarget(db: SQLiteDatabase, batchId: Long): Target? {
        db.rawQuery(
            "SELECT id, phone_e164, name FROM contact " +
                "WHERE batch_id = ? AND status = 'not_sent' AND is_campaign = 1 " +
                "ORDER BY id LIMIT 1",
            arrayOf(batchId.toString())
        ).use { c ->
            if (!c.moveToFirst()) return null
            return Target(c.getLong(0), c.getString(1), if (c.isNull(2)) null else c.getString(2))
        }
    }

    private fun countInBatch(db: SQLiteDatabase, batchId: Long): Int =
        scalar(db, "SELECT COUNT(*) FROM contact WHERE batch_id = ?", batchId)

    private fun countDone(db: SQLiteDatabase, batchId: Long): Int =
        scalar(
            db,
            "SELECT COUNT(*) FROM contact WHERE batch_id = ? AND status <> 'not_sent'",
            batchId
        )

    private fun scalar(db: SQLiteDatabase, sql: String, arg: Long): Int {
        db.rawQuery(sql, arrayOf(arg.toString())).use { c ->
            return if (c.moveToFirst()) c.getInt(0) else 0
        }
    }

    private fun batchName(db: SQLiteDatabase, batchId: Long): String {
        db.rawQuery("SELECT name FROM batch WHERE id = ?", arrayOf(batchId.toString())).use { c ->
            return if (c.moveToFirst()) c.getString(0) ?: "batch" else "batch"
        }
    }

    private fun finish(db: SQLiteDatabase, campaign: Campaign, campaignStatus: String, batchStatus: String) {
        val now = System.currentTimeMillis()
        db.execSQL(
            "UPDATE campaign SET status = ?, finished_at = ? WHERE id = ?",
            arrayOf<Any?>(campaignStatus, now, campaign.id)
        )
        db.execSQL(
            "UPDATE batch SET status = ?, completed_at = ? WHERE id = ?",
            arrayOf<Any?>(batchStatus, now, campaign.batchId)
        )
        CampaignDb.putSetting(db, Const.S_CAMPAIGN_ACTIVE, "0")
        CampaignDb.putSetting(db, Const.S_ENGINE_STATE, "idle")
    }

    // ---------------------------------------------------------------- plumbing

    private fun setEngineState(state: String) {
        CampaignDb.use(this) { db -> CampaignDb.putSetting(db, Const.S_ENGINE_STATE, state) }
    }

    private fun startForegroundSafely(title: String, text: String, progress: Int, max: Int) {
        val n = Notifications.engineNotification(this, title, text, progress, max, paused)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(Notifications.ID_ENGINE, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                startForeground(Notifications.ID_ENGINE, n)
            }
        } catch (e: Exception) {
            Log.e(Const.TAG, "startForeground failed", e)
        }
    }

    private fun pushNotification(title: String, text: String, progress: Int, max: Int) {
        startForegroundSafely(title, text, progress, max)
    }

    private fun stopForegroundCompat() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Exception) {
        }
    }

    private fun acquireWakeLock() {
        if (wakeLock != null) return
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "CampaignSMS::send").apply {
            setReferenceCounted(false)
            acquire(4 * 60 * 60 * 1000L)
        }
    }

    private fun releaseWakeLock() {
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {
        }
        wakeLock = null
    }
}
