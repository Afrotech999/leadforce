package com.loomsolutions.campaign_sms

import android.app.Application

class CampaignSmsApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Notifications.ensureChannels(this)
    }
}
