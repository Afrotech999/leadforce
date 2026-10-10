package com.loomsolutions.campaign_sms

import android.app.Activity
import android.content.Context
import android.telephony.SubscriptionManager
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The single platform channel (spec 3). Flutter owns the database schema, the UI and
 * every decision; this bridge only does the things Dart cannot: the SMS radio, the
 * default-app role, SIM enumeration and MediaStore writes.
 *
 * Note the split for sends: Dart writes the `message` row and passes its id down here.
 * Native never invents rows, so there is exactly one place that knows the schema.
 */
class NativeBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.loomsolutions.campaign_sms/native"
    }

    var activity: Activity? = null

    /**
     * Set when the user taps an inbox notification. Read once by Dart, which then
     * opens that conversation — which is what finally clears its unread badge.
     */
    var pendingThreadContactId: Long? = null

    /** Set by the after-call nudge: contact id and the note's prefilled first line. */
    var pendingCallNote: Pair<Long, String>? = null

    /** Set when another app shares content in — the car shelf's front door. */
    var pendingShare: ShareIn.Payload? = null

    /**
     * Held while the system role dialog is up. The Dart caller awaits it, so the
     * compose flow can check the result of the switch instead of racing the dialog.
     */
    private var pendingRoleResult: MethodChannel.Result? = null

    /** Called by [MainActivity] when the role dialog closes. */
    fun onRoleRequestFinished() {
        val pending = pendingRoleResult ?: return
        pendingRoleResult = null
        pending.success(DefaultSmsRole.isDefault(context))
    }

    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingPickResult: MethodChannel.Result? = null
    private var pendingContactsResult: MethodChannel.Result? = null
    private var pendingCallLogResult: MethodChannel.Result? = null

    /** Called by [MainActivity] when the call-log permission dialog closes. */
    fun onCallLogPermissionResult() {
        val pending = pendingCallLogResult ?: return
        pendingCallLogResult = null
        pending.success(Permissions.hasCallLog(context))
    }

    /** Called by [MainActivity] when the contacts permission dialog closes. */
    fun onContactsPermissionResult() {
        val pending = pendingContactsResult ?: return
        pendingContactsResult = null
        pending.success(Permissions.hasContacts(context))
    }

    /** Called by [MainActivity] when the document picker closes. */
    fun onFilePicked(uri: android.net.Uri?) {
        val pending = pendingPickResult ?: return
        pendingPickResult = null
        pending.success(if (uri == null) null else FilePick.copyToCache(context, uri))
    }

    /** Called by [MainActivity] when the runtime permission dialog closes. */
    fun onPermissionsResult() {
        val pending = pendingPermissionResult ?: return
        pendingPermissionResult = null
        pending.success(Permissions.hasSending(context))
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "defaultSmsInfo" -> result.success(defaultSmsInfo())
                "rememberPreviousDefault" -> {
                    DefaultSmsRole.rememberPrevious(context)
                    result.success(null)
                }
                "requestDefaultRole" -> {
                    val a = activity ?: return result.error("no_activity", "No foreground activity", null)
                    DefaultSmsRole.rememberPrevious(context)
                    // Resolved in onRoleRequestFinished once the user answers the dialog.
                    pendingRoleResult?.success(DefaultSmsRole.isDefault(context))
                    pendingRoleResult = result
                    DefaultSmsRole.launch(a, DefaultSmsRole.requestIntent(context))
                }
                "restoreDefaultRole" -> {
                    val a = activity ?: return result.error("no_activity", "No foreground activity", null)
                    val previous = call.argument<String>("package")
                    pendingRoleResult?.success(DefaultSmsRole.isDefault(context))
                    pendingRoleResult = result
                    DefaultSmsRole.launch(a, DefaultSmsRole.restoreIntent(context, previous))
                }
                "hasSmsPermissions" -> result.success(Permissions.hasSending(context))
                "requestSmsPermissions" -> {
                    val a = activity ?: return result.error("no_activity", "No foreground activity", null)
                    if (Permissions.hasSending(context)) return result.success(true)
                    pendingPermissionResult?.success(Permissions.hasSending(context))
                    pendingPermissionResult = result
                    Permissions.request(a)
                }
                "pickFile" -> {
                    val a = activity ?: return result.error("no_activity", "No foreground activity", null)
                    pendingPickResult?.success(null)
                    pendingPickResult = result
                    FilePick.launch(a)
                }
                "hasContactsPermission" -> result.success(Permissions.hasContacts(context))
                "requestContactsPermission" -> {
                    val a = activity ?: return result.error("no_activity", "No foreground activity", null)
                    if (Permissions.hasContacts(context)) return result.success(true)
                    pendingContactsResult?.success(Permissions.hasContacts(context))
                    pendingContactsResult = result
                    Permissions.requestContacts(a)
                }
                "readDeviceContacts" -> result.success(DeviceContacts.read(context))
                "hasCallLogPermission" -> result.success(Permissions.hasCallLog(context))
                "requestCallLogPermission" -> {
                    val a = activity ?: return result.error("no_activity", "No foreground activity", null)
                    if (Permissions.hasCallLog(context)) return result.success(true)
                    pendingCallLogResult?.success(Permissions.hasCallLog(context))
                    pendingCallLogResult = result
                    Permissions.requestCallLog(a)
                }
                "recentCalls" -> result.success(CallLogStore.recent(context))
                "hasOverlayPermission" -> result.success(CallOverlay.hasPermission(context))
                "requestOverlayPermission" -> {
                    val a = activity ?: return result.error("no_activity", "No foreground activity", null)
                    a.startActivity(
                        android.content.Intent(
                            android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            android.net.Uri.parse("package:" + context.packageName)
                        )
                    )
                    result.success(null)
                }
                "callsFor" -> result.success(
                    CallLogStore.callsFor(context, call.argument<String>("phone") ?: "")
                )
                "hasNotificationAccess" -> result.success(ChatApps.hasAccess(context))
                "openNotificationAccess" -> {
                    val a = activity
                    val intent = ChatApps.accessIntent()
                    if (a != null) {
                        a.startActivity(intent)
                    } else {
                        intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                        context.startActivity(intent)
                    }
                    result.success(null)
                }
                "chatApps" -> result.success(ChatApps.installed(context))
                "appIcon" -> result.success(
                    ChatApps.icon(context, call.argument<String>("package") ?: "")
                )
                "openApp" -> result.success(
                    ChatApps.open(context, call.argument<String>("package") ?: "")
                )
                "importCarPhoto" -> result.success(
                    ShareIn.intoCars(context, call.argument<String>("path") ?: "")
                )
                "takePendingShare" -> {
                    val share = pendingShare
                    pendingShare = null
                    result.success(
                        share?.let { mapOf("text" to it.text, "photos" to it.photos) }
                    )
                }
                "takePendingCallNote" -> {
                    val note = pendingCallNote
                    pendingCallNote = null
                    result.success(
                        note?.let { mapOf("contactId" to it.first, "prefill" to it.second) }
                    )
                }
                "takePendingThread" -> {
                    val id = pendingThreadContactId
                    pendingThreadContactId = null
                    result.success(id)
                }
                "openExternal" -> result.success(External.open(context, call.argument<String>("url") ?: ""))
                "openAppSettings" -> result.success(External.openAppSettings(context))
                "contactPhoto" -> result.success(
                    DeviceContacts.lookupPhoto(context, call.argument<String>("phone") ?: "")
                )
                "scheduleMessageAlarm" -> {
                    val id = (call.argument<Number>("id") ?: 0).toLong()
                    val at = (call.argument<Number>("atMillis") ?: 0).toLong()
                    if (id > 0 && at > 0) MessageScheduler.schedule(context, id, at)
                    result.success(null)
                }
                "scheduleAppointmentAlarm" -> {
                    val id = (call.argument<Number>("id") ?: 0).toLong()
                    val at = (call.argument<Number>("atMillis") ?: 0).toLong()
                    if (id > 0 && at > 0) AppointmentScheduler.schedule(context, id, at)
                    result.success(null)
                }
                "cancelAppointmentAlarm" -> {
                    val id = (call.argument<Number>("id") ?: 0).toLong()
                    if (id > 0) AppointmentScheduler.cancel(context, id)
                    result.success(null)
                }
                "cancelMessageAlarm" -> {
                    val id = (call.argument<Number>("id") ?: 0).toLong()
                    if (id > 0) MessageScheduler.cancel(context, id)
                    result.success(null)
                }
                "isBatteryOptimized" -> result.success(Battery.isOptimized(context))
                "requestBatteryExemption" -> result.success(Battery.requestExemption(context))
                "listSims" -> result.success(listSims())
                "startSendService" -> {
                    SendService.start(context)
                    result.success(null)
                }
                "pauseCampaign" -> {
                    SendService.signal(context, SendService.ACTION_PAUSE)
                    result.success(null)
                }
                "resumeCampaign" -> {
                    SendService.signal(context, SendService.ACTION_RESUME)
                    result.success(null)
                }
                "stopCampaign" -> {
                    SendService.signal(context, SendService.ACTION_STOP)
                    result.success(null)
                }
                "sendOneOff" -> result.success(sendOneOff(call))
                "countSegments" -> {
                    val body = call.argument<String>("body") ?: ""
                    val subId = call.argument<Int>("subId")
                    result.success(SmsSender.divide(context, subId, body).size)
                }
                "scheduleAlarm" -> {
                    val id = (call.argument<Number>("campaignId") ?: 0).toLong()
                    val at = (call.argument<Number>("atMillis") ?: 0).toLong()
                    if (id > 0 && at > 0) Scheduler.schedule(context, id, at)
                    result.success(null)
                }
                "cancelAlarm" -> {
                    val id = (call.argument<Number>("campaignId") ?: 0).toLong()
                    if (id > 0) Scheduler.cancel(context, id)
                    result.success(null)
                }
                "shareBackup" -> {
                    val stamp = call.argument<String>("stamp") ?: "backup"
                    result.success(Backup.share(context, stamp))
                }
                "exportBackup" -> {
                    val csv = call.argument<String>("csv") ?: ""
                    val stamp = call.argument<String>("stamp") ?: "backup"
                    result.success(Backup.export(context, csv, stamp))
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.e(Const.TAG, "channel call ${call.method} failed", e)
            result.error("native_error", e.message ?: e.javaClass.simpleName, null)
        }
    }

    private fun defaultSmsInfo(): Map<String, Any?> {
        val current = DefaultSmsRole.currentDefaultPackage(context)
        val previous = CampaignDb.use(context) { db ->
            CampaignDb.setting(db, Const.S_PREVIOUS_SMS_APP, "")
        }?.takeIf { it.isNotBlank() }
        return mapOf(
            "isDefault" to (current == context.packageName),
            "package" to current,
            "label" to DefaultSmsRole.appLabel(context, current),
            "previousPackage" to previous,
            "previousLabel" to DefaultSmsRole.appLabel(context, previous)
        )
    }

    private fun listSims(): List<Map<String, Any?>> {
        return try {
            val sm = context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
                ?: return emptyList()
            @Suppress("MissingPermission")
            val subs = sm.activeSubscriptionInfoList ?: return emptyList()
            subs.map {
                mapOf(
                    "subscriptionId" to it.subscriptionId,
                    "displayName" to (it.displayName?.toString() ?: "SIM ${it.simSlotIndex + 1}"),
                    "carrierName" to (it.carrierName?.toString() ?: ""),
                    "number" to (it.number ?: ""),
                    "slotIndex" to it.simSlotIndex
                )
            }
        } catch (e: SecurityException) {
            // READ_PHONE_STATE not granted yet — the UI falls back to "default SIM".
            emptyList()
        } catch (e: Exception) {
            Log.w(Const.TAG, "listSims failed", e)
            emptyList()
        }
    }

    /**
     * A one-off reply from a thread. Dart already journalled the message row, so all
     * that is left is the radio; results flow back through [SendResultReceiver] exactly
     * like campaign sends do.
     */
    private fun sendOneOff(call: MethodCall): String? {
        val messageId = (call.argument<Number>("messageId") ?: return "missing messageId").toLong()
        val phone = call.argument<String>("phone") ?: return "missing phone"
        val body = call.argument<String>("body") ?: return "missing body"
        val subId = call.argument<Int>("subId")
        val parts = SmsSender.divide(context, subId, body)
        val error = SmsSender.send(context, phone, subId, parts, messageId)
        if (error != null) {
            CampaignDb.use(context) { db ->
                repeat(parts.size) { SendResultReceiver.applyPartResult(db, messageId, false, error) }
            }
        }
        return error
    }
}
