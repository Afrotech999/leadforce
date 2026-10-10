package com.loomsolutions.campaign_sms

import android.app.Notification
import android.content.ComponentName
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.os.Bundle
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

/**
 * The messengers LeadForce can watch, and how to ask for permission to.
 *
 * Only these packages are ever considered, and only the ones the user has
 * ticked are ever read — a notification listener that quietly hoovered up
 * everything on the phone would be exactly the app nobody should install.
 */
object ChatApps {

    /** Package to the name a human would call it. Order is the picker's order. */
    val known: List<Pair<String, String>> = listOf(
        "com.whatsapp" to "WhatsApp",
        "com.whatsapp.w4b" to "WhatsApp Business",
        "org.telegram.messenger" to "Telegram",
        "org.thunderdog.challegram" to "Telegram X",
        "com.instagram.android" to "Instagram",
        "com.facebook.orca" to "Messenger",
        "com.viber.voip" to "Viber",
        "com.imo.android.imoim" to "imo",
        "org.thoughtcrime.securesms" to "Signal",
    )

    /** The known messengers that are actually on this phone. */
    fun installed(ctx: Context): List<Map<String, Any?>> {
        val pm = ctx.packageManager
        return known.mapNotNull { (pkg, label) ->
            try {
                pm.getPackageInfo(pkg, 0)
                mapOf("package" to pkg, "label" to label)
            } catch (e: Exception) {
                null
            }
        }
    }

    /**
     * Has the user granted notification access in the system settings? There
     * is no dialog for this one — Android only offers its own page.
     */
    fun hasAccess(ctx: Context): Boolean {
        return try {
            val flat = Settings.Secure.getString(
                ctx.contentResolver,
                "enabled_notification_listeners"
            ) ?: return false
            val mine = ComponentName(ctx, ChatCapture::class.java)
            flat.split(':').any {
                val cn = ComponentName.unflattenFromString(it)
                cn != null && cn.packageName == mine.packageName
            }
        } catch (e: Exception) {
            false
        }
    }

    fun accessIntent(): Intent =
        Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)

    /**
     * An app's own launcher icon, as PNG bytes.
     *
     * Drawn rather than read: a modern icon is an adaptive drawable with a
     * background and foreground layer, not a file, so the only way to get a
     * picture of it is to give it a canvas and ask it to paint.
     */
    fun icon(ctx: Context, pkg: String, size: Int = 96): ByteArray? {
        return try {
            val drawable = ctx.packageManager.getApplicationIcon(pkg)
            val bitmap = android.graphics.Bitmap.createBitmap(
                size,
                size,
                android.graphics.Bitmap.Config.ARGB_8888
            )
            val canvas = android.graphics.Canvas(bitmap)
            drawable.setBounds(0, 0, size, size)
            drawable.draw(canvas)
            val out = java.io.ByteArrayOutputStream()
            bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, out)
            bitmap.recycle()
            out.toByteArray()
        } catch (e: Exception) {
            null
        }
    }

    /** Opens another app at its own front door — the reply happens there. */
    fun open(ctx: Context, pkg: String): Boolean {
        return try {
            val intent = ctx.packageManager.getLaunchIntentForPackage(pkg)
                ?: return false
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ctx.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.w(Const.TAG, "could not open $pkg", e)
            false
        }
    }
}

/**
 * Reads incoming messages from the messengers the user has ticked, so a car
 * offered on WhatsApp counts as talking to that person the same way an SMS
 * does — and nothing is missed because it arrived in the wrong app.
 *
 * Deliberately read-only. Android does allow replying through a
 * notification's own action, but that channel dies the moment the message is
 * read anywhere else, which makes for a reply button that works only
 * sometimes. Tapping a row opens the real app instead, where replying always
 * works.
 *
 * Nothing leaves the phone. Nothing is stored for an app that is not ticked.
 */
class ChatCapture : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        try {
            handle(sbn)
        } catch (e: Exception) {
            Log.w(Const.TAG, "chat capture failed", e)
        }
    }

    private fun handle(sbn: StatusBarNotification) {
        val pkg = sbn.packageName ?: return
        // Never our own notifications: SMS already has a real inbox, and
        // capturing ourselves would double every message.
        if (pkg == packageName) return
        if (ChatApps.known.none { it.first == pkg }) return

        val n = sbn.notification ?: return
        // Ongoing service notices, group summaries and call banners are not
        // messages; storing them would fill the feed with noise.
        if (sbn.isOngoing) return
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        if (n.category == Notification.CATEGORY_CALL ||
            n.category == Notification.CATEGORY_SERVICE ||
            n.category == Notification.CATEGORY_TRANSPORT
        ) {
            return
        }

        val extras = n.extras ?: return
        val room = extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)
            ?.toString()?.trim()?.takeIf { it.isNotEmpty() }
        val fallbackSender = extras.getCharSequence(Notification.EXTRA_TITLE)
            ?.toString()?.trim().orEmpty()

        val items = mutableListOf<Triple<String, String, Long>>() // sender, body, at

        // MessagingStyle carries each message with its own sender and time,
        // which is the only way to tell "3 new messages" apart.
        @Suppress("DEPRECATION")
        val history = extras.getParcelableArray(Notification.EXTRA_MESSAGES)
        if (history != null && history.isNotEmpty()) {
            for (item in history) {
                val b = item as? Bundle ?: continue
                val text = b.getCharSequence("text")?.toString()?.trim().orEmpty()
                if (text.isEmpty()) continue
                val who = b.getCharSequence("sender")?.toString()?.trim()
                    ?.takeIf { it.isNotEmpty() }
                    ?: fallbackSender
                val at = b.getLong("time").takeIf { it > 0 } ?: sbn.postTime
                items.add(Triple(who, text, at))
            }
        } else {
            val text = extras.getCharSequence(Notification.EXTRA_TEXT)
                ?.toString()?.trim().orEmpty()
            // A summary like "5 new messages" has no body worth keeping.
            if (text.isEmpty() || fallbackSender.isEmpty()) return
            if (SUMMARY.containsMatchIn(text)) return
            items.add(Triple(fallbackSender, text, sbn.postTime))
        }
        if (items.isEmpty()) return

        CampaignDb.use(applicationContext) { db ->
            val chosen = CampaignDb.setting(db, Const.S_CHAT_APPS, "")
                .split(',').map { it.trim() }.filter { it.isNotEmpty() }
            if (!chosen.contains(pkg)) return@use

            for ((sender, body, at) in items) {
                if (exists(db, pkg, sender, body, at)) continue
                val contactId = resolve(db, pkg, sender)
                db.insert("chat_message", null, ContentValues().apply {
                    put("app", pkg)
                    put("sender", sender)
                    if (room == null) putNull("room") else put("room", room)
                    put("body", body)
                    put("at", at)
                    if (contactId == null) {
                        putNull("contact_id")
                    } else {
                        put("contact_id", contactId)
                    }
                    put("seen", 0)
                })
                // Talking is talking, whatever app it arrived in — this is
                // what makes "going cold" honest across every messenger.
                if (contactId != null) {
                    CampaignDb.touchContact(db, contactId, at)
                }
            }
        }
    }

    /** The same message arrives again every time the notification updates. */
    private fun exists(
        db: SQLiteDatabase,
        pkg: String,
        sender: String,
        body: String,
        at: Long
    ): Boolean {
        db.rawQuery(
            "SELECT 1 FROM chat_message WHERE app = ? AND sender = ? " +
                "AND body = ? AND at = ? LIMIT 1",
            arrayOf(pkg, sender, body, at.toString())
        ).use { c -> return c.moveToFirst() }
    }

    /**
     * Who this is, if the app can tell: a link the user made by hand first,
     * then a plain name match against the contact list. A notification never
     * carries a phone number, so this is as far as certainty goes.
     */
    private fun resolve(db: SQLiteDatabase, pkg: String, sender: String): Long? {
        db.rawQuery(
            "SELECT contact_id FROM chat_link WHERE app = ? AND sender = ?",
            arrayOf(pkg, sender)
        ).use { c -> if (c.moveToFirst()) return c.getLong(0) }
        db.rawQuery(
            "SELECT id FROM contact WHERE name = ? COLLATE NOCASE LIMIT 1",
            arrayOf(sender)
        ).use { c -> if (c.moveToFirst()) return c.getLong(0) }
        return null
    }

    private companion object {
        /** "3 new messages", "2 messages from 2 chats" — counts, not content. */
        val SUMMARY = Regex(
            """^\d+\s+(new\s+)?(message|messages|chats?)\b""",
            RegexOption.IGNORE_CASE
        )
    }
}
