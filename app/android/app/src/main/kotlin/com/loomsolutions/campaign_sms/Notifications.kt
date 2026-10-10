package com.loomsolutions.campaign_sms

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.RemoteInput

object Notifications {

    const val CH_ENGINE = "send_engine"
    const val CH_INBOX = "inbox"
    const val CH_ALERTS = "alerts"
    const val CH_CALLS = "call_notes"

    const val ID_ENGINE = 1001
    const val ID_ALERT = 1002
    const val ID_INBOX_BASE = 2000

    fun ensureChannels(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
        nm.createNotificationChannel(
            NotificationChannel(CH_ENGINE, "Sending", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Progress while a campaign batch is sending"
                setShowBadge(false)
            }
        )
        nm.createNotificationChannel(
            NotificationChannel(CH_INBOX, "Replies", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Incoming SMS"
            }
        )
        nm.createNotificationChannel(
            NotificationChannel(CH_ALERTS, "Alerts", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Daily cap, default-SMS-app reminders"
            }
        )
        // LOW: it appears in the shade without a sound. The user has just put
        // the phone down from a call — chiming at them is not a favour.
        nm.createNotificationChannel(
            NotificationChannel(CH_CALLS, "After-call notes", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Offers to write a note when a call ends"
                setShowBadge(false)
            }
        )
    }

    const val EXTRA_CONTACT_ID = "open_contact_id"

    fun openAppIntent(ctx: Context): PendingIntent {
        val i = Intent(ctx, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(
            ctx, 0, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /**
     * Opens straight into one conversation.
     *
     * Tapping an inbox notification used to land on whatever screen was last open,
     * which left the message read but its thread — and so the badge — untouched.
     * The request code is per-contact so two notifications do not collapse into one
     * PendingIntent pointing at the wrong person.
     */
    private fun openThreadIntent(ctx: Context, contactId: Long): PendingIntent {
        val i = Intent(ctx, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .putExtra(EXTRA_CONTACT_ID, contactId)
        return PendingIntent.getActivity(
            ctx,
            (contactId % 100000).toInt() + 1000,
            i,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun serviceAction(ctx: Context, action: String, requestCode: Int): PendingIntent {
        val i = Intent(ctx, SendService::class.java).setAction(action)
        return PendingIntent.getService(
            ctx, requestCode, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    fun engineNotification(
        ctx: Context,
        title: String,
        text: String,
        progress: Int,
        max: Int,
        paused: Boolean
    ): Notification {
        val b = NotificationCompat.Builder(ctx, CH_ENGINE)
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(openAppIntent(ctx))
        if (max > 0) b.setProgress(max, progress, false)
        if (paused) {
            b.addAction(0, "Resume", serviceAction(ctx, SendService.ACTION_RESUME, 11))
        } else {
            b.addAction(0, "Pause", serviceAction(ctx, SendService.ACTION_PAUSE, 12))
        }
        b.addAction(0, "Stop", serviceAction(ctx, SendService.ACTION_STOP, 13))
        return b.build()
    }

    fun alert(ctx: Context, title: String, text: String) {
        ensureChannels(ctx)
        val n = NotificationCompat.Builder(ctx, CH_ALERTS)
            .setSmallIcon(android.R.drawable.stat_notify_error)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setAutoCancel(true)
            .setContentIntent(openAppIntent(ctx))
            .build()
        safeNotify(ctx, ID_ALERT, n)
    }

    private fun inboxId(contactId: Long) = ID_INBOX_BASE + (contactId % 500).toInt()

    /**
     * The action buttons on an incoming message: a reply box that sends
     * without opening the app, and a way to clear the badge.
     *
     * The reply PendingIntent must be MUTABLE — that is the whole mechanism:
     * the system writes the typed text into the intent before delivering it.
     * Everything else in this app is immutable by default.
     */
    private fun replyAction(ctx: Context, contactId: Long, notificationId: Int): NotificationCompat.Action {
        val remoteInput = RemoteInput.Builder(NotificationActions.KEY_REPLY)
            .setLabel("Reply")
            .build()
        val intent = Intent(ctx, NotificationActions::class.java)
            .setAction(NotificationActions.ACTION_REPLY)
            .putExtra(NotificationActions.EXTRA_CONTACT_ID, contactId)
            .putExtra(NotificationActions.EXTRA_NOTIFICATION_ID, notificationId)
        val pending = PendingIntent.getBroadcast(
            ctx,
            notificationId * 4,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        )
        return NotificationCompat.Action.Builder(0, "Reply", pending)
            .addRemoteInput(remoteInput)
            .setAllowGeneratedReplies(true)
            .setSemanticAction(NotificationCompat.Action.SEMANTIC_ACTION_REPLY)
            .setShowsUserInterface(false)
            .build()
    }

    private fun markReadAction(ctx: Context, contactId: Long, notificationId: Int): NotificationCompat.Action {
        val intent = Intent(ctx, NotificationActions::class.java)
            .setAction(NotificationActions.ACTION_MARK_READ)
            .putExtra(NotificationActions.EXTRA_CONTACT_ID, contactId)
            .putExtra(NotificationActions.EXTRA_NOTIFICATION_ID, notificationId)
        val pending = PendingIntent.getBroadcast(
            ctx,
            notificationId * 4 + 1,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Action.Builder(0, "Mark read", pending)
            .setSemanticAction(NotificationCompat.Action.SEMANTIC_ACTION_MARK_AS_READ)
            .setShowsUserInterface(false)
            .build()
    }

    fun incoming(ctx: Context, who: String, body: String, contactId: Long) {
        ensureChannels(ctx)
        val id = inboxId(contactId)
        val n = NotificationCompat.Builder(ctx, CH_INBOX)
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setContentTitle(who)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setContentIntent(openThreadIntent(ctx, contactId))
            .addAction(replyAction(ctx, contactId, id))
            .addAction(markReadAction(ctx, contactId, id))
            .build()
        safeNotify(ctx, id, n)
    }

    /**
     * A reply typed in the shade that never left the phone. Shown with the
     * text still in it, so the user can open the thread and try again rather
     * than discovering later that nothing was sent.
     */
    fun replyFailed(
        ctx: Context,
        contactId: Long,
        text: String,
        reason: String,
        notificationId: Int
    ) {
        ensureChannels(ctx)
        val n = NotificationCompat.Builder(ctx, CH_INBOX)
            .setSmallIcon(android.R.drawable.stat_notify_error)
            .setContentTitle("Reply not sent")
            .setContentText(text)
            .setStyle(
                NotificationCompat.BigTextStyle()
                    .bigText("$text\n\n$reason — open the conversation to try again.")
            )
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_ERROR)
            .setContentIntent(openThreadIntent(ctx, contactId))
            .build()
        safeNotify(ctx, if (notificationId >= 0) notificationId else inboxId(contactId), n)
    }

    const val ID_APPOINTMENT_BASE = 3000
    const val ID_CALL_NOTE_BASE = 4000

    const val EXTRA_CALL_NOTE_CONTACT = "call_note_contact_id"
    const val EXTRA_CALL_NOTE_PREFILL = "call_note_prefill"

    /**
     * "You just talked with Dawit (4 min) — write it down?"
     *
     * Tapping opens the note editor already attached to that person, with the
     * call's facts as the first line, so the user only types what was agreed.
     */
    fun callNote(ctx: Context, contactId: Long, who: String, seconds: Long, at: Long) {
        ensureChannels(ctx)
        val id = ID_CALL_NOTE_BASE + (contactId % 500).toInt()
        val time = android.text.format.DateFormat.getTimeFormat(ctx).format(java.util.Date(at))
        val length = if (seconds < 60) "${seconds}s" else "${(seconds + 30) / 60} min"
        val prefill = "Call · $time · $length\n"

        val intent = Intent(ctx, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .putExtra(EXTRA_CALL_NOTE_CONTACT, contactId)
            .putExtra(EXTRA_CALL_NOTE_PREFILL, prefill)
        val writeIt = PendingIntent.getActivity(
            ctx,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        // "Not now" clears the shade without opening anything — a nudge with
        // no polite refusal is nagging, not nudging.
        val notNow = PendingIntent.getBroadcast(
            ctx,
            id * 4 + 2,
            Intent(ctx, NotificationActions::class.java)
                .setAction(NotificationActions.ACTION_DISMISS)
                .putExtra(NotificationActions.EXTRA_NOTIFICATION_ID, id),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val n = NotificationCompat.Builder(ctx, CH_CALLS)
            .setSmallIcon(android.R.drawable.stat_notify_voicemail)
            .setContentTitle("You just talked with $who")
            .setContentText("$length — write it down while you remember?")
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_EVENT)
            .setContentIntent(writeIt)
            .addAction(0, "Write it down", writeIt)
            .addAction(0, "Not now", notNow)
            .build()
        safeNotify(ctx, id, n)
    }

    /**
     * A viewing is about to happen. Tapping it opens the conversation with
     * whoever it is with, which is nearly always the next thing wanted —
     * "on my way", or "are we still on?".
     */
    fun appointment(
        ctx: Context,
        id: Long,
        title: String,
        who: String?,
        place: String?,
        at: Long,
        contactId: Long
    ) {
        ensureChannels(ctx)
        val time = android.text.format.DateFormat.getTimeFormat(ctx).format(java.util.Date(at))
        val detail = listOfNotNull(
            who?.let { "with $it" },
            place?.let { "at $it" }
        ).joinToString(" ")
        val text = if (detail.isEmpty()) time else "$time · $detail"

        val b = NotificationCompat.Builder(ctx, CH_ALERTS)
            .setSmallIcon(android.R.drawable.ic_menu_my_calendar)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setContentIntent(
                if (contactId > 0) openThreadIntent(ctx, contactId) else openAppIntent(ctx)
            )
        safeNotify(ctx, ID_APPOINTMENT_BASE + (id % 500).toInt(), b.build())
    }

    private fun safeNotify(ctx: Context, id: Int, n: Notification) {
        try {
            NotificationManagerCompat.from(ctx).notify(id, n)
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS not granted; nothing to do.
        }
    }
}
