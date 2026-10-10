package com.loomsolutions.campaign_sms

object Const {
    const val TAG = "CampaignSMS"

    const val DB_NAME = "campaign_sms.db"

    const val ACTION_SMS_SENT = "com.loomsolutions.campaign_sms.SMS_SENT"
    const val ACTION_SMS_DELIVERED = "com.loomsolutions.campaign_sms.SMS_DELIVERED"

    const val EXTRA_MESSAGE_ID = "message_id"
    const val EXTRA_PART_INDEX = "part_index"
    const val EXTRA_PART_COUNT = "part_count"

    // Settings keys (mirrored in lib/data/settings.dart)
    const val S_DAILY_CAP = "daily_cap"
    const val S_DELAY_SECONDS = "default_delay_seconds"
    const val S_SIM_SUB_ID = "current_sim_subscription_id"
    const val S_CAMPAIGN_ACTIVE = "campaign_active"
    const val S_ENGINE_STATE = "engine_state" // idle | running | paused
    const val S_PREVIOUS_SMS_APP = "previous_sms_app"
    const val S_STOP_KEYWORDS = "stop_keywords"
    const val S_MAX_ATTEMPTS = "max_attempts"
    const val S_NAME_FALLBACK = "name_fallback"
    const val S_CAP_COUNTS_SEGMENTS = "cap_counts_segments"
    const val S_QUIET_ENABLED = "quiet_hours_enabled"
    const val S_QUIET_START = "quiet_start_hour"
    const val S_QUIET_END = "quiet_end_hour"
    const val S_LAST_NUDGED_CALL = "last_nudged_call_id"
    const val S_CALL_OVERLAY = "call_overlay_enabled"
    const val S_OVERLAY_Y = "call_overlay_y"

    /** Comma-separated packages the chat feed is allowed to read. */
    const val S_CHAT_APPS = "chat_apps"

    const val DEFAULT_STOP_KEYWORDS = "STOP,STOPP,UNSUBSCRIBE,QUIT,CANCEL,END,አቁም,አቁሙ,ተው,ተዉ,በቃ,አታድርጉ,አታክሉኝ"
}
