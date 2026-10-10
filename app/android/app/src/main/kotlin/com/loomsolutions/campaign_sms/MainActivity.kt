package com.loomsolutions.campaign_sms

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var bridge: NativeBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val b = NativeBridge(applicationContext)
        b.activity = this
        bridge = b
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NativeBridge.CHANNEL)
            .setMethodCallHandler(b)
        b.pendingThreadContactId = threadFrom(intent)
        callNoteFrom(intent)?.let { b.pendingCallNote = it }
        ShareIn.from(applicationContext, intent)?.let { b.pendingShare = it }
    }

    /**
     * The activity is singleTop, so a second notification tap arrives here rather
     * than through onCreate. Dart picks it up on resume.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        threadFrom(intent)?.let { bridge?.pendingThreadContactId = it }
        callNoteFrom(intent)?.let { bridge?.pendingCallNote = it }
        ShareIn.from(applicationContext, intent)?.let { bridge?.pendingShare = it }
    }

    /** The after-call nudge's payload: who the note is about, and its first line. */
    private fun callNoteFrom(intent: Intent?): Pair<Long, String>? {
        if (intent == null) return null
        val id = intent.getLongExtra(Notifications.EXTRA_CALL_NOTE_CONTACT, -1L)
        if (id <= 0) return null
        return id to (intent.getStringExtra(Notifications.EXTRA_CALL_NOTE_PREFILL) ?: "")
    }

    /**
     * Which conversation this launch is about: a notification tap carries the
     * contact id as an extra; the dialer and contact apps hand us an
     * sms:/smsto: uri with the number. Before this read the uri, tapping
     * "message" on a contact opened LeadForce on the dashboard and forgot who you
     * were trying to text.
     */
    private fun threadFrom(intent: Intent?): Long? {
        if (intent == null) return null
        intent.getLongExtra(Notifications.EXTRA_CONTACT_ID, -1L)
            .takeIf { it > 0 }
            ?.let { return it }

        val data = intent.data ?: return null
        if (data.scheme !in setOf("sms", "smsto", "mms", "mmsto")) return null
        val raw = android.net.Uri.decode(data.schemeSpecificPart ?: return null)
            .substringBefore('?')
            .trim()
        if (raw.none { it.isDigit() }) return null
        return CampaignDb.use(applicationContext) { db ->
            CampaignDb.contactIdForAddress(applicationContext, db, raw)
        }?.takeIf { it > 0 }
    }

    @Deprecated("Flutter's embedding still routes results through this callback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == DefaultSmsRole.REQUEST_CODE) {
            // The result code is not trustworthy across OEMs and API levels; what matters
            // is who actually holds the role now.
            bridge?.onRoleRequestFinished()
        }
        if (requestCode == FilePick.REQUEST_CODE) {
            bridge?.onFilePicked(if (resultCode == RESULT_OK) data?.data else null)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == Permissions.REQUEST_CODE) {
            bridge?.onPermissionsResult()
        }
        if (requestCode == Permissions.CONTACTS_REQUEST_CODE) {
            bridge?.onContactsPermissionResult()
        }
        if (requestCode == Permissions.CALL_LOG_REQUEST_CODE) {
            bridge?.onCallLogPermissionResult()
        }
    }

    override fun onDestroy() {
        bridge?.activity = null
        bridge = null
        super.onDestroy()
    }
}
