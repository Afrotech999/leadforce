package com.loomsolutions.campaign_sms

/**
 * Ethiopian phone normalization, mirroring `lib/data/phone.dart`.
 *
 * Kept as a tiny duplicate rather than a channel round-trip because inbound SMS is
 * handled in a broadcast receiver that may run with no Flutter engine alive.
 */
object Phone {

    /** Returns `+2519XXXXXXXX` / `+2517XXXXXXXX`, or null if the input can't be a valid number. */
    fun normalize(raw: String?): String? {
        if (raw.isNullOrBlank()) return null
        var d = raw.filter { it.isDigit() }
        if (d.isEmpty()) return null

        when {
            d.startsWith("00251") -> d = d.substring(5)
            d.startsWith("251") -> d = d.substring(3)
            d.startsWith("0") -> d = d.trimStart('0')
        }

        if (d.length != 9) return null
        if (d[0] != '9' && d[0] != '7') return null
        return "+251$d"
    }

    /** Display form: `09XXXXXXXX`. */
    fun local(e164: String): String =
        if (e164.startsWith("+251") && e164.length == 13) "0" + e164.substring(4) else e164
}
