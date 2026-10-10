package com.loomsolutions.campaign_sms

import android.content.Context
import android.util.Log

/**
 * One message to one person, sent from outside the app's UI.
 *
 * Two things need this and neither can wait for Flutter: a reply typed into a
 * notification (the app may not be running at all) and a scheduled personal
 * message firing at midnight. Both take exactly the same path a reply typed in
 * the thread screen takes — journal first, then the radio — so the message
 * appears in the conversation whether or not the send succeeds, and the
 * sent/delivered receipts settle it the usual way.
 *
 * Campaign statistics are untouched: `campaign_id` stays null.
 */
object PersonalSend {

    /** Returns null when the message reached the radio, or a reason it did not. */
    fun send(ctx: Context, contactId: Long, body: String): String? {
        if (body.isBlank()) return "Nothing to send"

        val phoneAndSub = CampaignDb.use(ctx) { db ->
            val phone = db.rawQuery(
                "SELECT phone_e164 FROM contact WHERE id = ?",
                arrayOf(contactId.toString())
            ).use { c -> if (c.moveToFirst()) c.getString(0) else null } ?: return@use null
            val sub = CampaignDb.setting(db, Const.S_SIM_SUB_ID, "").toIntOrNull()
            phone to sub
        } ?: return "That contact is gone"

        val (phone, subId) = phoneAndSub
        val parts = SmsSender.divide(ctx, subId, body)

        val messageId = CampaignDb.use(ctx) { db ->
            val id = CampaignDb.insertOutboundMessage(db, contactId, null, body, parts.size)
            if (id > 0) {
                val kind = db.rawQuery(
                    "SELECT is_campaign FROM contact WHERE id = ?",
                    arrayOf(contactId.toString())
                ).use { c ->
                    if (c.moveToFirst() && c.getInt(0) == 1) "campaign" else "other"
                }
                CampaignDb.touchThread(db, contactId, kind, body, System.currentTimeMillis(), 0)
                CampaignDb.touchContact(db, contactId, System.currentTimeMillis())
            }
            id
        } ?: -1L
        if (messageId <= 0) return "Could not save the message"

        val error = SmsSender.send(ctx, phone, subId, parts, messageId)
        if (error != null) {
            Log.w(Const.TAG, "personal send failed: $error")
            CampaignDb.use(ctx) { db ->
                db.execSQL(
                    "UPDATE message SET status = 'failed', error = ? WHERE id = ?",
                    arrayOf<Any?>(error, messageId)
                )
            }
        }
        return error
    }
}
