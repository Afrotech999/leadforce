package com.loomsolutions.campaign_sms

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.telephony.SmsManager
import android.util.Log

/**
 * The one place that actually hands a message to the radio.
 *
 * Every part gets its own sent- and delivery-PendingIntent so nothing is ever marked
 * "sent" optimistically (spec 2.6). Results land in [SendResultReceiver].
 */
object SmsSender {

    @Suppress("DEPRECATION")
    fun managerFor(ctx: Context, subscriptionId: Int?): SmsManager {
        val useSub = subscriptionId != null && subscriptionId >= 0
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val base = ctx.getSystemService(SmsManager::class.java)
            if (useSub) base.createForSubscriptionId(subscriptionId!!) else base
        } else {
            if (useSub) SmsManager.getSmsManagerForSubscriptionId(subscriptionId!!)
            else SmsManager.getDefault()
        }
    }

    fun divide(ctx: Context, subscriptionId: Int?, body: String): ArrayList<String> =
        managerFor(ctx, subscriptionId).divideMessage(body) ?: arrayListOf(body)

    /**
     * Fires the message. Returns null on success, or an error string if the send threw
     * before it ever reached the radio.
     */
    fun send(
        ctx: Context,
        destination: String,
        subscriptionId: Int?,
        parts: ArrayList<String>,
        messageId: Long
    ): String? {
        return try {
            val sent = ArrayList<PendingIntent>(parts.size)
            val delivered = ArrayList<PendingIntent>(parts.size)
            for (i in parts.indices) {
                sent.add(resultIntent(ctx, Const.ACTION_SMS_SENT, messageId, i, parts.size))
                delivered.add(resultIntent(ctx, Const.ACTION_SMS_DELIVERED, messageId, i, parts.size))
            }
            managerFor(ctx, subscriptionId)
                .sendMultipartTextMessage(destination, null, parts, sent, delivered)
            null
        } catch (e: Exception) {
            Log.e(Const.TAG, "send failed for $destination", e)
            e.message ?: e.javaClass.simpleName
        }
    }

    private fun resultIntent(
        ctx: Context,
        action: String,
        messageId: Long,
        partIndex: Int,
        partCount: Int
    ): PendingIntent {
        val intent = Intent(action)
            .setPackage(ctx.packageName)
            // Unique data, otherwise Android collapses PendingIntents that differ only by extras.
            .setData(Uri.parse("campaignsms://result/$action/$messageId/$partIndex"))
            .putExtra(Const.EXTRA_MESSAGE_ID, messageId)
            .putExtra(Const.EXTRA_PART_INDEX, partIndex)
            .putExtra(Const.EXTRA_PART_COUNT, partCount)
        val requestCode = (messageId * 64 + partIndex).toInt()
        return PendingIntent.getBroadcast(
            ctx,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}
