package com.loomsolutions.campaign_sms

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.telephony.SmsManager
import android.util.Log
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch

/**
 * Handles the per-part sent and delivery receipts.
 *
 * Declared in the manifest (not registered at runtime) so a receipt that lands after
 * the process was killed still reconciles the database instead of being dropped.
 *
 * All part accounting lives in the `message` row (`parts_total/parts_ok/parts_failed`)
 * rather than in memory, for the same reason.
 */
class SendResultReceiver : BroadcastReceiver() {

    companion object {
        /** Latches the send loop waits on. Only meaningful while the process is alive. */
        private val waiters = ConcurrentHashMap<Long, CountDownLatch>()

        fun expect(messageId: Long): CountDownLatch {
            val latch = CountDownLatch(1)
            waiters[messageId] = latch
            return latch
        }

        fun forget(messageId: Long) {
            waiters.remove(messageId)
        }

        private fun release(messageId: Long) {
            waiters.remove(messageId)?.countDown()
        }

        fun errorText(resultCode: Int): String = when (resultCode) {
            SmsManager.RESULT_ERROR_GENERIC_FAILURE -> "Generic failure"
            SmsManager.RESULT_ERROR_NO_SERVICE -> "No service"
            SmsManager.RESULT_ERROR_NULL_PDU -> "Null PDU"
            SmsManager.RESULT_ERROR_RADIO_OFF -> "Radio off"
            SmsManager.RESULT_ERROR_LIMIT_EXCEEDED -> "Send limit exceeded"
            SmsManager.RESULT_ERROR_FDN_CHECK_FAILURE -> "Blocked by fixed dialling"
            else -> "Send error ($resultCode)"
        }

        /**
         * Applies one part receipt. Extracted so the send loop can reuse it when a send
         * throws synchronously and no broadcast will ever arrive.
         */
        fun applyPartResult(db: SQLiteDatabase, messageId: Long, ok: Boolean, error: String?) {
            val now = System.currentTimeMillis()
            // Only wake the send loop once every part of this message is accounted for.
            var messageSettled = false
            db.beginTransaction()
            try {
                if (ok) {
                    db.execSQL("UPDATE message SET parts_ok = parts_ok + 1 WHERE id = ?", arrayOf<Any?>(messageId))
                } else {
                    db.execSQL(
                        "UPDATE message SET parts_failed = parts_failed + 1, error = ? WHERE id = ?",
                        arrayOf<Any?>(error ?: "unknown", messageId)
                    )
                }

                var contactId = -1L
                var campaignId: Long? = null
                var total = 1
                var okCount = 0
                var failedCount = 0
                var status = "pending"
                db.rawQuery(
                    "SELECT contact_id, campaign_id, parts_total, parts_ok, parts_failed, status " +
                        "FROM message WHERE id = ?",
                    arrayOf(messageId.toString())
                ).use { c ->
                    if (!c.moveToFirst()) return@use
                    contactId = c.getLong(0)
                    campaignId = if (c.isNull(1)) null else c.getLong(1)
                    total = c.getInt(2)
                    okCount = c.getInt(3)
                    failedCount = c.getInt(4)
                    status = c.getString(5) ?: "pending"
                }
                if (contactId < 0) {
                    messageSettled = true // nothing to wait for; don't strand the loop
                    return
                }

                // Still waiting on other parts, or already finalized.
                if (okCount + failedCount < total || status != "pending") {
                    messageSettled = status != "pending"
                    db.setTransactionSuccessful()
                    return
                }
                messageSettled = true

                if (failedCount == 0) {
                    db.execSQL(
                        "UPDATE message SET status = 'sent', sent_at = ? WHERE id = ?",
                        arrayOf<Any?>(now, messageId)
                    )
                    // Never clobber a terminal status: a reply or STOP may have landed
                    // between the send and the receipt.
                    db.execSQL(
                        "UPDATE contact SET status = 'sent', last_sent_at = ?, last_error = NULL, " +
                            "attempts = attempts + 1 WHERE id = ? AND status IN ('queued','not_sent','failed')",
                        arrayOf<Any?>(now, contactId)
                    )
                    if (campaignId != null) {
                        db.execSQL(
                            "UPDATE campaign SET sent_count = sent_count + 1 WHERE id = ?",
                            arrayOf<Any?>(campaignId)
                        )
                    }
                } else {
                    db.execSQL("UPDATE message SET status = 'failed' WHERE id = ?", arrayOf<Any?>(messageId))
                    db.execSQL(
                        "UPDATE contact SET status = 'failed', last_error = ?, attempts = attempts + 1 " +
                            "WHERE id = ? AND status IN ('queued','not_sent')",
                        arrayOf<Any?>(error ?: "Send failed", contactId)
                    )
                    if (campaignId != null) {
                        db.execSQL(
                            "UPDATE campaign SET failed_count = failed_count + 1 WHERE id = ?",
                            arrayOf<Any?>(campaignId)
                        )
                    }
                }
                db.setTransactionSuccessful()
            } finally {
                db.endTransaction()
                if (messageSettled) release(messageId)
            }
        }

        private fun applyDelivered(db: SQLiteDatabase, messageId: Long, ok: Boolean) {
            val now = System.currentTimeMillis()
            db.beginTransaction()
            try {
                if (!ok) {
                    db.execSQL(
                        "UPDATE message SET error = COALESCE(error, 'Not delivered') WHERE id = ?",
                        arrayOf<Any?>(messageId)
                    )
                    db.setTransactionSuccessful()
                    return
                }
                val changed = db.compileStatement(
                    "UPDATE message SET status = 'delivered', delivered_at = ? WHERE id = ? AND status = 'sent'"
                ).use { st ->
                    st.bindLong(1, now)
                    st.bindLong(2, messageId)
                    st.executeUpdateDelete()
                }
                if (changed > 0) {
                    db.rawQuery(
                        "SELECT contact_id, campaign_id FROM message WHERE id = ?",
                        arrayOf(messageId.toString())
                    ).use { c ->
                        if (c.moveToFirst()) {
                            val contactId = c.getLong(0)
                            db.execSQL(
                                "UPDATE contact SET status = 'delivered' WHERE id = ? AND status = 'sent'",
                                arrayOf<Any?>(contactId)
                            )
                            if (!c.isNull(1)) {
                                db.execSQL(
                                    "UPDATE campaign SET delivered_count = delivered_count + 1 WHERE id = ?",
                                    arrayOf<Any?>(c.getLong(1))
                                )
                            }
                        }
                    }
                }
                db.setTransactionSuccessful()
            } finally {
                db.endTransaction()
            }
        }

        fun handle(ctx: Context, action: String?, messageId: Long, resultCode: Int) {
            CampaignDb.use(ctx) { db ->
                when (action) {
                    Const.ACTION_SMS_SENT -> applyPartResult(
                        db,
                        messageId,
                        resultCode == Activity.RESULT_OK,
                        if (resultCode == Activity.RESULT_OK) null else errorText(resultCode)
                    )
                    Const.ACTION_SMS_DELIVERED -> applyDelivered(
                        db,
                        messageId,
                        resultCode == Activity.RESULT_OK
                    )
                }
            } ?: Log.w(Const.TAG, "receipt for $messageId dropped: no database")
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val messageId = intent.getLongExtra(Const.EXTRA_MESSAGE_ID, -1L)
        if (messageId < 0) return
        val action = intent.action
        val code = resultCode
        val pending = goAsync()
        Thread {
            try {
                handle(context.applicationContext, action, messageId, code)
            } catch (e: Exception) {
                Log.e(Const.TAG, "receipt handling failed", e)
            } finally {
                pending.finish()
            }
        }.start()
    }
}
