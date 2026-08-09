package com.runiac.runiac_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class RuniacPlanNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        RuniacPlanNotificationScheduler(context).showNotificationFromIntent(intent)
    }
}
