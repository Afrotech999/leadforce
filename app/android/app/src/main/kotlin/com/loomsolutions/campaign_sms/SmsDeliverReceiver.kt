package com.loomsolutions.campaign_sms

import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.provider.Telephony
import android.util.Log

/**
 * Inbound SMS while this app holds the default-SMS role (spec 8).
 *
 * Two kinds of message arrive here:
 *  - from a contact on the campaign list  -> that contact becomes `replied` (terminal,
 *    so it never appears in another batch) and the thread lands in "Campaign replies";
 *  - from anyone else (personal texts, bank OTPs) -> stored as an "Other" thread, and
 *    also mirrored into the system SMS inbox so the user's normal Messages app still
 *    has it after they switch the default back. Nothing is sent off the device.
 */
class SmsDeliverReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_DELIVER_ACTION) return
        val messages = try {
            Telephony.Sms.Intents.getMessagesFromIntent(intent)
        } catch (e: Exception) {
            Log.e(Const.TAG, "cannot parse inbound SMS", e)
            null
        } ?: return
        if (messages.isEmpty()) return

        val sender = messages[0].displayOriginatingAddress ?: return
        val body = messages.joinToString("") { it.displayMessageBody ?: "" }
        val timestamp = messages[0].timestampMillis.takeIf { it > 0 } ?: System.currentTimeMillis()

        val ctx = context.applicationContext
        val pending = goAsync()
        Thread {
            try {
                store(ctx, sender, body, timestamp)
            } catch (e: Exception) {
                Log.e(Const.TAG, "inbound handling failed", e)
            } finally {
                pending.finish()
            }
        }.start()
    }

    private fun store(ctx: Context, rawSender: String, body: String, timestamp: Long) {
        val e164 = Phone.normalize(rawSender)

        CampaignDb.use(ctx) { db ->
            // A sender we cannot normalize (short codes like "8100", international numbers)
            // is still worth keeping — key it by the raw address.
            val key = e164 ?: rawSender.trim()
            val existing = findContact(db, key)
            val isCampaignContact = existing?.isCampaign == true
            // Quiet means stored but silent: no notification, no unread badge.
            // Muted is the user's word for it on personal senders; a blocked
            // campaign contact (STOP, or blocked by hand) gets the same
            // silence — they asked not to be talked to, so their replies
            // should not ring the phone either.
            val quiet = existing != null &&
                (existing.muted || (existing.isCampaign && existing.blocked))

            val contactId = existing?.id ?: insertAdHocContact(ctx, db, key, rawSender)
            if (contactId <= 0) return@use

            // A sender the app knows only as a number might be somebody the
            // phone book knows by name. Filled in on every message, not just
            // the first, so granting the contacts permission later still
            // names the threads that arrived before it.
            if (existing != null) {
                DeviceContacts.lookupName(ctx, rawSender)?.let { name ->
                    db.execSQL(
                        "UPDATE contact SET name = ? WHERE id = ? " +
                            "AND (name IS NULL OR name = '')",
                        arrayOf<Any?>(name, contactId)
                    )
                }
            }

            db.beginTransaction()
            try {
                db.insert("message", null, ContentValues().apply {
                    put("contact_id", contactId)
                    putNull("campaign_id")
                    put("direction", "inbound")
                    put("body", body)
                    put("segments", 1)
                    put("status", "delivered")
                    put("created_at", timestamp)
                    put("delivered_at", timestamp)
                    put("parts_total", 1)
                    put("parts_ok", 1)
                    put("parts_failed", 0)
                })

                if (isCampaignContact) {
                    // Any inbound message is terminal for campaigns (spec 4).
                    db.execSQL(
                        "UPDATE contact SET status = 'replied' WHERE id = ? " +
                            "AND status <> 'do_not_contact'",
                        arrayOf<Any?>(contactId)
                    )
                    if (isStopKeyword(db, body)) {
                        db.execSQL(
                            "UPDATE contact SET status = 'do_not_contact' WHERE id = ?",
                            arrayOf<Any?>(contactId)
                        )
                    }
                }

                CampaignDb.touchThread(
                    db,
                    contactId,
                    if (isCampaignContact) "campaign" else "other",
                    body.take(160),
                    timestamp,
                    if (quiet) 0 else 1
                )
                db.setTransactionSuccessful()
            } finally {
                db.endTransaction()
            }

            // They wrote to us — that is talking, whoever they are.
            CampaignDb.touchContact(db, contactId, timestamp)

            if (!quiet) {
                val who = contactLabel(db, contactId, key)
                Notifications.incoming(ctx, who, body, contactId)
            }

            if (!isCampaignContact) {
                mirrorToSystemInbox(ctx, rawSender, body, timestamp)
            }
        }
    }

    private data class Sender(
        val id: Long,
        val isCampaign: Boolean,
        val muted: Boolean,
        val blocked: Boolean
    )

    private fun findContact(db: SQLiteDatabase, key: String): Sender? {
        // The muted column arrived in schema v5, and Dart owns migrations —
        // this receiver can fire on a database the app has not been opened to
        // upgrade yet. Losing an inbound message over a missing column would
        // be the worst possible trade, so fall back to the old shape.
        try {
            db.rawQuery(
                "SELECT id, is_campaign, muted, status FROM contact WHERE phone_e164 = ?",
                arrayOf(key)
            ).use { c ->
                return if (c.moveToFirst()) {
                    Sender(
                        c.getLong(0),
                        c.getInt(1) == 1,
                        c.getInt(2) == 1,
                        c.getString(3) == "do_not_contact"
                    )
                } else null
            }
        } catch (e: Exception) {
            db.rawQuery(
                "SELECT id, is_campaign, status FROM contact WHERE phone_e164 = ?",
                arrayOf(key)
            ).use { c ->
                return if (c.moveToFirst()) {
                    Sender(
                        c.getLong(0),
                        c.getInt(1) == 1,
                        muted = false,
                        blocked = c.getString(2) == "do_not_contact"
                    )
                } else null
            }
        }
    }

    private fun insertAdHocContact(
        ctx: Context,
        db: SQLiteDatabase,
        key: String,
        raw: String
    ): Long =
        db.insert("contact", null, ContentValues().apply {
            put("phone_e164", key)
            put("phone_local", if (key.startsWith("+251")) Phone.local(key) else raw)
            val known = DeviceContacts.lookupName(ctx, raw)
            if (known == null) putNull("name") else put("name", known)
            put("source", "inbox")
            // Never batchable: not on the campaign list, and marked so explicitly.
            put("status", "do_not_contact")
            put("is_campaign", 0)
            put("attempts", 0)
            put("created_at", System.currentTimeMillis())
        })

    private fun contactLabel(db: SQLiteDatabase, contactId: Long, fallback: String): String {
        db.rawQuery("SELECT name FROM contact WHERE id = ?", arrayOf(contactId.toString())).use { c ->
            if (c.moveToFirst() && !c.isNull(0)) {
                val n = c.getString(0)
                if (!n.isNullOrBlank()) return n
            }
        }
        return fallback
    }

    private fun isStopKeyword(db: SQLiteDatabase, body: String): Boolean {
        val keywords = CampaignDb.setting(db, Const.S_STOP_KEYWORDS, Const.DEFAULT_STOP_KEYWORDS)
            .split(',')
            .map { it.trim() }
            .filter { it.isNotEmpty() }
        val normalized = body.trim().trim('.', '!', '?', ',').uppercase()
        return keywords.any { normalized == it.uppercase() || normalized.startsWith(it.uppercase() + " ") }
    }

    /**
     * Keeps personal texts and OTPs where the user expects them. This is a local
     * ContentProvider write, not a forward to anywhere (spec 13).
     */
    private fun mirrorToSystemInbox(ctx: Context, sender: String, body: String, timestamp: Long) {
        try {
            if (Telephony.Sms.getDefaultSmsPackage(ctx) != ctx.packageName) return
            ctx.contentResolver.insert(
                Telephony.Sms.Inbox.CONTENT_URI,
                ContentValues().apply {
                    put(Telephony.Sms.ADDRESS, sender)
                    put(Telephony.Sms.BODY, body)
                    put(Telephony.Sms.DATE, timestamp)
                    put(Telephony.Sms.DATE_SENT, timestamp)
                    put(Telephony.Sms.READ, 0)
                    put(Telephony.Sms.SEEN, 0)
                }
            )
        } catch (e: Exception) {
            Log.w(Const.TAG, "could not mirror to system inbox", e)
        }
    }
}
