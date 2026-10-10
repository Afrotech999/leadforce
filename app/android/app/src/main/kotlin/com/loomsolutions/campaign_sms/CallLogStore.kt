package com.loomsolutions.campaign_sms

import android.content.Context
import android.provider.CallLog
import android.telephony.PhoneNumberUtils
import android.util.Log

/**
 * Read-only access to the phone's call log.
 *
 * Everything stays on the phone (spec 13); this never writes, never uploads,
 * and asks its own permission the way the phone book does. Distribution note:
 * READ_CALL_LOG is a Play-Store-restricted permission, which is fine for an
 * app installed from an APK — but this file is the first thing to delete if
 * LeadForce ever heads for the store.
 */
object CallLogStore {

    /**
     * Calls exchanged with one number, newest first.
     *
     * The log stores numbers however they were dialled ("0911...", "+2519...",
     * with spaces), so matching is our normalizer first and Android's own
     * lenient [PhoneNumberUtils.compare] as the fallback — the same judgement
     * the dialler itself uses to group a log entry under a contact.
     */
    fun callsFor(ctx: Context, phone: String, limit: Int = 60): List<Map<String, Any?>> {
        if (phone.isBlank()) return emptyList()
        val key = Phone.normalize(phone) ?: phone.trim()
        val out = mutableListOf<Map<String, Any?>>()
        try {
            ctx.contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                arrayOf(
                    CallLog.Calls.NUMBER,
                    CallLog.Calls.TYPE,
                    CallLog.Calls.DATE,
                    CallLog.Calls.DURATION
                ),
                null,
                null,
                "${CallLog.Calls.DATE} DESC"
            )?.use { c ->
                // The whole log is walked rather than SQL-filtered because the
                // stored formats vary; capped so a ten-year-old phone with an
                // enormous log stays quick.
                var scanned = 0
                while (c.moveToNext() && out.size < limit && scanned < 2000) {
                    scanned++
                    val raw = c.getString(0) ?: continue
                    val matches = (Phone.normalize(raw) ?: raw.trim()) == key ||
                        PhoneNumberUtils.compare(raw, phone)
                    if (!matches) continue
                    out.add(
                        mapOf(
                            "type" to c.getInt(1),
                            "date" to c.getLong(2),
                            "duration" to c.getLong(3)
                        )
                    )
                }
            }
        } catch (e: SecurityException) {
            Log.w(Const.TAG, "READ_CALL_LOG not granted", e)
        } catch (e: Exception) {
            Log.e(Const.TAG, "reading call log failed", e)
        }
        return out
    }

    /**
     * The whole recent log, newest first, numbers included — for the Calls
     * screen, which shows everything and lets Dart match rows to contacts.
     */
    fun recent(ctx: Context, limit: Int = 300): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        try {
            ctx.contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                arrayOf(
                    CallLog.Calls.NUMBER,
                    CallLog.Calls.TYPE,
                    CallLog.Calls.DATE,
                    CallLog.Calls.DURATION
                ),
                null,
                null,
                "${CallLog.Calls.DATE} DESC"
            )?.use { c ->
                while (c.moveToNext() && out.size < limit) {
                    out.add(
                        mapOf(
                            "number" to (c.getString(0) ?: ""),
                            "type" to c.getInt(1),
                            "date" to c.getLong(2),
                            "duration" to c.getLong(3)
                        )
                    )
                }
            }
        } catch (e: SecurityException) {
            Log.w(Const.TAG, "READ_CALL_LOG not granted", e)
        } catch (e: Exception) {
            Log.e(Const.TAG, "reading call log failed", e)
        }
        return out
    }

    data class LatestCall(
        val id: Long,
        val number: String,
        val type: Int,
        val date: Long,
        val durationSeconds: Long
    )

    /** The newest entry in the log, or null — for the moment just after a call ends. */
    fun latestCall(ctx: Context): LatestCall? {
        return try {
            // A plain sort and read-first-row. The first version smuggled
            // "LIMIT 1" into the sort clause — an old trick that newer call-log
            // providers reject outright, which killed the after-call nudge on
            // exactly the phones it was built for. Only the first row is read;
            // the cursor is closed immediately.
            ctx.contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                arrayOf(
                    CallLog.Calls._ID,
                    CallLog.Calls.NUMBER,
                    CallLog.Calls.TYPE,
                    CallLog.Calls.DATE,
                    CallLog.Calls.DURATION
                ),
                null,
                null,
                "${CallLog.Calls.DATE} DESC"
            )?.use { c ->
                if (!c.moveToFirst()) null
                else LatestCall(
                    id = c.getLong(0),
                    number = c.getString(1) ?: "",
                    type = c.getInt(2),
                    date = c.getLong(3),
                    durationSeconds = c.getLong(4)
                )
            }
        } catch (e: Exception) {
            // Logged rather than swallowed: a silent null here is a nudge that
            // silently never fires, which took a real phone to notice once.
            Log.e(Const.TAG, "reading newest call failed", e)
            null
        }
    }
}
