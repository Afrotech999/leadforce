package com.loomsolutions.campaign_sms

import android.content.Context
import android.provider.ContactsContract
import android.util.Log

/**
 * Reads the phone's own contacts so a campaign list can be built without a CSV.
 *
 * Native for the same reason as [Permissions] and [FilePick]: the two contact
 * plugins on pub.dev both carry their own Android build opinions, and two of those
 * have already cost this project a build each.
 *
 * Normalization, deduplication and the needs-review split all happen in Dart, on
 * exactly the same path a CSV takes — this only hands over raw name/number pairs.
 */
object DeviceContacts {

    fun read(ctx: Context): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        val projection = arrayOf(
            ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
            ContactsContract.CommonDataKinds.Phone.NUMBER
        )
        try {
            ctx.contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                projection,
                null,
                null,
                "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} ASC"
            )?.use { c ->
                val nameIndex = c.getColumnIndex(projection[0])
                val numberIndex = c.getColumnIndex(projection[1])
                if (nameIndex < 0 || numberIndex < 0) return emptyList()
                while (c.moveToNext()) {
                    val number = c.getString(numberIndex) ?: continue
                    out.add(
                        mapOf(
                            "name" to c.getString(nameIndex),
                            "phone" to number
                        )
                    )
                }
            }
        } catch (e: SecurityException) {
            Log.w(Const.TAG, "READ_CONTACTS not granted", e)
            return emptyList()
        } catch (e: Exception) {
            Log.e(Const.TAG, "reading device contacts failed", e)
            return emptyList()
        }
        return out
    }

    /**
     * The name the phone book has for one number, or null. Used when a message
     * arrives from somebody the app has never seen: the phone already knows who
     * they are, and an inbox of raw numbers is an inbox of strangers.
     *
     * Safe to call without the permission — PhoneLookup just throws and this
     * answers null, and the sender is stored by number as before.
     */
    fun lookupName(ctx: Context, phone: String): String? =
        lookup(ctx, phone, ContactsContract.PhoneLookup.DISPLAY_NAME)

    /**
     * The contact's photo as raw bytes, or null when they have none.
     *
     * The thumbnail, not the full-size picture: this fills a 46px circle in a
     * list, and the large photo is up to a megabyte per contact.
     */
    fun lookupPhoto(ctx: Context, phone: String): ByteArray? {
        val uri = lookup(ctx, phone, ContactsContract.PhoneLookup.PHOTO_THUMBNAIL_URI)
            ?: return null
        return try {
            ctx.contentResolver.openInputStream(android.net.Uri.parse(uri))
                ?.use { it.readBytes() }
        } catch (e: Exception) {
            null
        }
    }

    private fun lookup(ctx: Context, phone: String, column: String): String? {
        if (phone.isBlank()) return null
        return try {
            val uri = android.net.Uri.withAppendedPath(
                ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
                android.net.Uri.encode(phone)
            )
            ctx.contentResolver.query(uri, arrayOf(column), null, null, null)?.use { c ->
                if (c.moveToFirst()) c.getString(0)?.takeIf { it.isNotBlank() } else null
            }
        } catch (e: Exception) {
            null
        }
    }
}
