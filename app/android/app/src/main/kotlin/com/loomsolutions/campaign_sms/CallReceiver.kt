package com.loomsolutions.campaign_sms

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.telephony.TelephonyManager
import android.util.Log

/**
 * Both halves of "calls meet notes": while an incoming call RINGS, the
 * caller's notes float over the call screen ([CallOverlay]) — with a Note
 * button for writing one mid-call; when a call ENDS, a notification offers
 * to write new ones.
 *
 * The two use different sources on purpose. The overlay needs the number
 * *during* the ring, when no log row exists yet, so it reads
 * EXTRA_INCOMING_NUMBER — best-effort, because Android has restricted and
 * re-restricted that extra across versions (READ_CALL_LOG is what earns it
 * today). The nudge needs certainty more than speed, so it ignores the extra
 * entirely and reads the newest call-log row after the call ends, which
 * carries number, direction and duration reliably everywhere.
 *
 * Requires READ_PHONE_STATE (already held for the SIM picker) to hear the
 * broadcast at all, and READ_CALL_LOG to read the row. Missing either, this
 * does nothing, quietly.
 */
class CallReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) return
        val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return
        // Present only while ringing, and only on the broadcast that carries
        // it — the system sends the state twice, once with the number and once
        // without, and holding READ_CALL_LOG is what earns the one with.
        @Suppress("DEPRECATION")
        val ringingNumber = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)
        val ctx = context.applicationContext

        // The overlay comes down the moment the call ends, on the main thread
        // where window operations belong.
        if (state == TelephonyManager.EXTRA_STATE_IDLE) {
            CallOverlay.hide(ctx)
        }

        val pending = goAsync()
        Thread {
            try {
                if (state == TelephonyManager.EXTRA_STATE_RINGING) {
                    ringing(ctx, ringingNumber)
                } else {
                    handle(ctx, state)
                }
            } catch (e: Exception) {
                Log.e(Const.TAG, "call state handling failed", e)
            } finally {
                pending.finish()
            }
        }.start()
    }

    /**
     * An incoming call from somebody the app knows: float their notes over the
     * call screen, while the phone is still ringing. Known contacts only, off
     * for muted people, and gated on both the overlay permission and its
     * switch in Settings.
     */
    private fun ringing(ctx: Context, number: String?) {
        if (number.isNullOrBlank()) return
        if (!CallOverlay.hasPermission(ctx)) return

        val data = CampaignDb.use(ctx) { db ->
            if (CampaignDb.setting(db, Const.S_CALL_OVERLAY, "1") != "1") return@use null
            // While the DB is open anyway: recall where they last dragged the card.
            CallOverlay.restoreY(db)
            val key = Phone.normalize(number) ?: number.trim()
            val contact = db.rawQuery(
                "SELECT id, name, phone_local, muted FROM contact WHERE phone_e164 = ?",
                arrayOf(key)
            ).use { c ->
                if (!c.moveToFirst()) null
                else if (c.getInt(3) == 1) null
                else Triple(
                    c.getLong(0),
                    c.getString(1)?.takeIf { it.isNotBlank() } ?: c.getString(2) ?: key,
                    c.getString(2) ?: key
                )
            } ?: return@use null

            val notes = mutableListOf<String>()
            db.rawQuery(
                "SELECT title, body FROM note WHERE contact_id = ? " +
                    "ORDER BY pinned DESC, updated_at DESC LIMIT 3",
                arrayOf(contact.first.toString())
            ).use { c ->
                while (c.moveToNext()) {
                    val title = c.getString(0)?.trim().orEmpty()
                    val body = c.getString(1)?.lineSequence()
                        ?.map { it.trim() }?.firstOrNull { it.isNotEmpty() }
                        .orEmpty()
                    val line = when {
                        title.isNotEmpty() && body.isNotEmpty() -> "$title — $body"
                        title.isNotEmpty() -> title
                        else -> body
                    }
                    if (line.isNotEmpty()) notes.add(line)
                }
            }
            Pair(contact.first, Triple(contact.second, contact.third, notes.toList()))
        } ?: return

        val (contactId, rest) = data
        val (name, local, notes) = rest
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            CallOverlay.show(ctx, contactId, name, local, notes)
        }
    }

    /*
     * There was a check here that asked TelephonyManager whether a call was
     * genuinely ringing before drawing the card, to make a forged PHONE_STATE
     * broadcast from another app do nothing. It is gone, because it cost more
     * than it bought on real phones:
     *
     *   - getCallState() reports the *default* subscription. On a dual-SIM
     *     phone — which is most phones here — a call arriving on the other SIM
     *     reads as IDLE, and the card never appeared.
     *   - This runs on a background thread a moment after the broadcast. A
     *     call answered quickly is already OFFHOOK by the time the state is
     *     read, and again the card never appeared.
     *
     * What the check defended against was a cosmetic spoof: another app could
     * make a notes card appear for a number it chose. What it broke was the
     * feature working at all. The end-of-call nudge, which is the half that
     * writes anything down, reads the call log itself and cannot be forged.
     */

    private fun handle(ctx: Context, state: String) {
        // Only the return to idle is interesting; RINGING and OFFHOOK are a
        // call still happening. Deliberately NOT gated on "the previous state
        // was OFFHOOK": on a dual-SIM phone each subscription broadcasts its
        // own state, and the idle SIM's chatter overwrote the tracked state
        // mid-call — the nudge never fired. The call log itself is the proof a
        // call just ended; the IDLE broadcast is only the knock on the door.
        if (state != TelephonyManager.EXTRA_STATE_IDLE) return

        // The system writes the log row moments after the call ends; give it
        // that moment, and a second look if the first was too early. goAsync
        // allows ~10s, this uses at most half.
        var justEnded: CallLogStore.LatestCall? = null
        for (attempt in 0 until 2) {
            Thread.sleep(2500)
            val newest = CallLogStore.latestCall(ctx) ?: return
            // Recency is measured from when the call ENDED (start + duration).
            // The first version measured from the start and a three-minute
            // window — so any call longer than three minutes never nudged,
            // which for a broker is most of the ones worth writing about.
            val endedAt = newest.date + newest.durationSeconds * 1000L
            if (System.currentTimeMillis() - endedAt <= 90_000L) {
                justEnded = newest
                break
            }
        }
        // The newest call did not just end: this IDLE is a boot, a SIM waking
        // up, or an OEM re-broadcast — not a hang-up.
        val call = justEnded ?: return

        // Connected voice calls only. A missed call is already announced by
        // the phone, and an unanswered dial has nothing to write about.
        if (call.type != android.provider.CallLog.Calls.INCOMING_TYPE &&
            call.type != android.provider.CallLog.Calls.OUTGOING_TYPE
        ) {
            return
        }
        if (call.durationSeconds <= 0) return

        val nudge = CampaignDb.use(ctx) { db ->
            // One nudge per call, however many IDLE broadcasts arrive.
            val last = CampaignDb.setting(db, Const.S_LAST_NUDGED_CALL, "")
            if (last == call.id.toString()) return@use null
            CampaignDb.putSetting(db, Const.S_LAST_NUDGED_CALL, call.id.toString())

            // Only people the app already knows. A wrong number is not a lead,
            // and inventing a contact per phone call would flood the list.
            val key = Phone.normalize(call.number) ?: call.number.trim()

            // A connected call is talking — even with somebody muted, and even
            // though muted people are never nudged below.
            CampaignDb.touchContactByKey(
                db, key, call.date + call.durationSeconds * 1000L
            )
            db.rawQuery(
                "SELECT id, name, phone_local, muted FROM contact WHERE phone_e164 = ?",
                arrayOf(key)
            ).use { c ->
                if (!c.moveToFirst()) null
                else if (c.getInt(3) == 1) null // they muted this person
                else Triple(
                    c.getLong(0),
                    c.getString(1)?.takeIf { it.isNotBlank() } ?: c.getString(2) ?: key,
                    call.durationSeconds
                )
            }
        } ?: return

        val (contactId, who, seconds) = nudge
        Notifications.callNote(ctx, contactId, who, seconds, call.date)
    }
}
