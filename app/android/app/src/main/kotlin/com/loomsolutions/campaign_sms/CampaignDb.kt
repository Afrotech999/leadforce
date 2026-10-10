package com.loomsolutions.campaign_sms

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import java.util.Calendar

/**
 * Native-side access to the same SQLite file Flutter uses.
 *
 * Design note (spec 1: pick one and say why): the send engine, the sent/delivered
 * receivers and the inbound SMS receiver all have to touch the database at moments
 * when no Flutter engine is guaranteed to be alive (process death mid-batch, an SMS
 * arriving while the app is swiped away). So the native side talks to the DB directly.
 *
 * The Dart side uses `sqflite`, which is a thin wrapper over Android's own
 * `android.database.sqlite` — the exact engine used here. Same library, same file,
 * no cross-engine WAL concerns. That is why this app uses sqflite rather than drift
 * (drift bundles its own SQLite build, which would have two different SQLite versions
 * writing one WAL file).
 *
 * Schema creation lives in Dart (`lib/data/database.dart`) and only there. This class
 * never creates tables; if the file does not exist yet, nothing native can run anyway.
 */
object CampaignDb {

    fun open(ctx: Context): SQLiteDatabase? {
        val f = ctx.getDatabasePath(Const.DB_NAME)
        if (!f.exists()) return null
        return try {
            val db = SQLiteDatabase.openDatabase(
                f.absolutePath,
                null,
                SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.ENABLE_WRITE_AHEAD_LOGGING
            )
            // rawQuery, not execSQL: execSQL refuses statements that return rows,
            // and `PRAGMA busy_timeout = N` returns its new value. Getting this
            // wrong throws, open() returns null, and the send engine silently
            // does nothing at all.
            db.rawQuery("PRAGMA busy_timeout = 8000", null).close()
            db
        } catch (e: Exception) {
            Log.e(Const.TAG, "open db failed", e)
            null
        }
    }

    inline fun <T> use(ctx: Context, block: (SQLiteDatabase) -> T): T? {
        val db = open(ctx) ?: return null
        return try {
            block(db)
        } catch (e: Exception) {
            Log.e(Const.TAG, "db op failed", e)
            null
        } finally {
            try {
                db.close()
            } catch (_: Exception) {
            }
        }
    }

    // ---------- settings ----------

    /**
     * The contact row for a raw address the user wants to write to — an sms:
     * link from the dialer, or the in-app new-message sheet. Finds the existing
     * row or creates an ad-hoc one exactly the way the inbound receiver does:
     * never batchable, never part of a campaign.
     */
    fun contactIdForAddress(ctx: android.content.Context, db: SQLiteDatabase, raw: String): Long {
        val trimmed = raw.trim()
        val key = Phone.normalize(trimmed) ?: trimmed
        db.rawQuery("SELECT id FROM contact WHERE phone_e164 = ?", arrayOf(key)).use { c ->
            if (c.moveToFirst()) return c.getLong(0)
        }
        return db.insert("contact", null, android.content.ContentValues().apply {
            put("phone_e164", key)
            put("phone_local", if (key.startsWith("+251")) Phone.local(key) else trimmed)
            val known = DeviceContacts.lookupName(ctx, trimmed)
            if (known == null) putNull("name") else put("name", known)
            put("source", "compose")
            put("status", "do_not_contact")
            put("is_campaign", 0)
            put("attempts", 0)
            put("created_at", System.currentTimeMillis())
        })
    }

    fun setting(db: SQLiteDatabase, key: String, def: String): String {
        db.rawQuery("SELECT value FROM settings WHERE key = ?", arrayOf(key)).use { c ->
            return if (c.moveToFirst()) c.getString(0) ?: def else def
        }
    }

    fun settingInt(db: SQLiteDatabase, key: String, def: Int): Int =
        setting(db, key, def.toString()).toIntOrNull() ?: def

    fun putSetting(db: SQLiteDatabase, key: String, value: String) {
        // No UPSERT: Android 7 (minSdk 24) ships SQLite 3.9, which predates ON CONFLICT DO UPDATE.
        db.execSQL("INSERT OR REPLACE INTO settings(key, value) VALUES(?, ?)", arrayOf<Any?>(key, value))
    }

    // ---------- counters ----------

    fun startOfTodayMillis(): Long {
        val c = Calendar.getInstance()
        c.set(Calendar.HOUR_OF_DAY, 0)
        c.set(Calendar.MINUTE, 0)
        c.set(Calendar.SECOND, 0)
        c.set(Calendar.MILLISECOND, 0)
        return c.timeInMillis
    }

    /** Messages that actually left the phone today. Drives the daily cap (spec 2.2). */
    fun sentToday(db: SQLiteDatabase): Int {
        db.rawQuery(
            "SELECT COUNT(*) FROM message WHERE direction = 'outbound' " +
                "AND status IN ('sent','delivered') AND sent_at >= ?",
            arrayOf(startOfTodayMillis().toString())
        ).use { c -> return if (c.moveToFirst()) c.getInt(0) else 0 }
    }

    /**
     * What the operator actually counted today.
     *
     * A message is one row here but one *or more* SMS on the network: 160 Latin
     * characters per segment, and only 70 in Amharic, which forces UCS-2. A cap of
     * 100 messages is a cap of 300 SMS if the template runs to three segments — three
     * times the bundle, and three times the traffic a carrier sees.
     */
    fun segmentsSentToday(db: SQLiteDatabase): Int {
        db.rawQuery(
            "SELECT COALESCE(SUM(segments), 0) FROM message WHERE direction = 'outbound' " +
                "AND status IN ('sent','delivered') AND sent_at >= ?",
            arrayOf(startOfTodayMillis().toString())
        ).use { c -> return if (c.moveToFirst()) c.getInt(0) else 0 }
    }

    /**
     * Rescues contacts stranded by a send that never reported back.
     *
     * `sendOne` waits 90 seconds for the sent receipt. If the radio wedges and no
     * receipt ever arrives, the message stays 'pending' and its contact stays
     * 'queued' — and 'queued' is excluded from every future batch, so that person
     * silently drops out of the campaign with nobody ever told. Anything still
     * pending well past that window is settled as failed, which puts the contact in
     * the retry queue where it is visible and actionable.
     *
     * The cutoff must stay comfortably above the 90-second receipt wait so a send
     * that is genuinely in flight is never touched.
     */
    fun sweepStalePending(db: SQLiteDatabase, olderThanMillis: Long = 10 * 60 * 1000L): Int {
        val cutoff = System.currentTimeMillis() - olderThanMillis
        val stale = mutableListOf<Long>()
        db.rawQuery(
            "SELECT contact_id FROM message WHERE direction = 'outbound' " +
                "AND status = 'pending' AND created_at < ?",
            arrayOf(cutoff.toString())
        ).use { c ->
            while (c.moveToNext()) stale.add(c.getLong(0))
        }
        if (stale.isEmpty()) return 0

        db.beginTransaction()
        try {
            db.execSQL(
                "UPDATE message SET status = 'failed', error = 'No delivery receipt', " +
                    "parts_failed = parts_total WHERE direction = 'outbound' " +
                    "AND status = 'pending' AND created_at < ?",
                arrayOf<Any?>(cutoff)
            )
            for (contactId in stale.distinct()) {
                db.execSQL(
                    "UPDATE contact SET status = 'failed', " +
                        "last_error = 'No delivery receipt' WHERE id = ? AND status = 'queued'",
                    arrayOf<Any?>(contactId)
                )
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
        return stale.size
    }

    // ---------- messages ----------

    fun insertOutboundMessage(
        db: SQLiteDatabase,
        contactId: Long,
        campaignId: Long?,
        body: String,
        parts: Int
    ): Long {
        val v = ContentValues().apply {
            put("contact_id", contactId)
            if (campaignId != null) put("campaign_id", campaignId) else putNull("campaign_id")
            put("direction", "outbound")
            put("body", body)
            put("segments", parts)
            put("status", "pending")
            put("created_at", System.currentTimeMillis())
            put("parts_total", parts)
            put("parts_ok", 0)
            put("parts_failed", 0)
        }
        return db.insert("message", null, v)
    }

    /**
     * Records an actual conversation with this person — a connected call, or a
     * personal message in either direction. Campaign blasts never call this;
     * "going cold" is measured against real talking. Never moves the clock
     * backwards, and swallows the error on a database Dart has not migrated to
     * v9 yet — a missing stamp is never worth failing a message over.
     */
    fun touchContact(db: SQLiteDatabase, contactId: Long, at: Long) {
        try {
            db.execSQL(
                "UPDATE contact SET last_talked_at = ? WHERE id = ? " +
                    "AND (last_talked_at IS NULL OR last_talked_at < ?)",
                arrayOf<Any?>(at, contactId, at)
            )
        } catch (e: Exception) {
            Log.w(Const.TAG, "touchContact skipped", e)
        }
    }

    /** [touchContact] keyed by normalized number, for callers that never look the row up. */
    fun touchContactByKey(db: SQLiteDatabase, key: String, at: Long) {
        try {
            db.execSQL(
                "UPDATE contact SET last_talked_at = ? WHERE phone_e164 = ? " +
                    "AND (last_talked_at IS NULL OR last_talked_at < ?)",
                arrayOf<Any?>(at, key, at)
            )
        } catch (e: Exception) {
            Log.w(Const.TAG, "touchContact skipped", e)
        }
    }

    /** Creates the thread if absent, otherwise refreshes it and adds [unread] to the badge. */
    fun touchThread(db: SQLiteDatabase, contactId: Long, kind: String, snippet: String, at: Long, unread: Int) {
        val updated = db.compileStatement(
            "UPDATE thread SET last_message_at = ?, snippet = ?, kind = ?, " +
                "unread_count = unread_count + ? WHERE contact_id = ?"
        ).use { st ->
            st.bindLong(1, at)
            st.bindString(2, snippet)
            st.bindString(3, kind)
            st.bindLong(4, unread.toLong())
            st.bindLong(5, contactId)
            st.executeUpdateDelete()
        }
        if (updated == 0) {
            db.insert("thread", null, ContentValues().apply {
                put("contact_id", contactId)
                put("kind", kind)
                put("last_message_at", at)
                put("unread_count", unread)
                put("snippet", snippet)
            })
        }
    }
}
