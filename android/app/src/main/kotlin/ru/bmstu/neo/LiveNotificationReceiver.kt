package ru.bmstu.neo

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class LiveNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        LiveNotificationManager.updateFromPrefs(context)
    }
}
