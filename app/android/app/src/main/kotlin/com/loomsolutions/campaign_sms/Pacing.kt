package com.loomsolutions.campaign_sms

import java.util.Calendar
import kotlin.random.Random

/**
 * How the engine spaces its sends, and when it refuses to send at all.
 *
 * Both rules here exist for the same reason: a hundred messages that leave a
 * handset at exactly 5.0-second intervals, all night, is not what a person
 * texting looks like, and it is the pattern spam filtering is built to notice.
 * Neither of these defeats carrier throttling and neither tries to — the daily
 * cap is still the real limit (spec 13).
 */
object Pacing {

    /**
     * A delay drawn from a shape a person makes, rather than a constant with a
     * ±1 second wobble on it.
     *
     * The old jitter still produced a machine signature: every gap landed inside
     * a two-second band around the same number, forever. Real sending is lumpy —
     * mostly a rhythm, sometimes a pause to read something, occasionally two in
     * quick succession. So: 70% near the base delay, 20% distinctly longer, 10%
     * quicker than usual.
     */
    fun nextDelayMs(baseSeconds: Int, random: Random = Random.Default): Long {
        val base = baseSeconds.coerceAtLeast(1) * 1000.0
        val roll = random.nextInt(100)
        val factor = when {
            roll < 70 -> 0.75 + random.nextDouble() * 0.5   // 0.75× – 1.25×
            roll < 90 -> 1.5 + random.nextDouble() * 1.5    // 1.5×  – 3×
            else -> 0.45 + random.nextDouble() * 0.3        // 0.45× – 0.75×
        }
        return (base * factor).toLong().coerceAtLeast(1500L)
    }

    /** How many messages before the engine puts the phone down for a moment. */
    fun messagesUntilBreak(random: Random = Random.Default): Int = 18 + random.nextInt(13)

    /** That break: long enough to be a gap in the pattern, short enough not to annoy. */
    fun breakMs(random: Random = Random.Default): Long = 45_000L + random.nextInt(75_000).toLong()

    /**
     * True when the clock is inside the user's quiet hours.
     *
     * Windows that wrap midnight are the normal case (21:00 → 08:00), so the
     * comparison flips when start is later than end. Equal start and end means a
     * zero-length window, not a whole silent day — the safer reading of a
     * mis-set pair.
     */
    fun isQuietNow(startHour: Int, endHour: Int, now: Calendar = Calendar.getInstance()): Boolean {
        val start = startHour.coerceIn(0, 23)
        val end = endHour.coerceIn(0, 23)
        if (start == end) return false
        val hour = now.get(Calendar.HOUR_OF_DAY)
        return if (start < end) hour in start until end else hour >= start || hour < end
    }

    fun describeWindow(startHour: Int, endHour: Int): String =
        "%02d:00–%02d:00".format(startHour.coerceIn(0, 23), endHour.coerceIn(0, 23))
}
