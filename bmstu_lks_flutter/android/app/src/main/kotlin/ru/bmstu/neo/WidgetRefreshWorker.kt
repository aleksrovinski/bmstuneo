package ru.bmstu.neo

import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters

/** Redraws the home-screen widget and the live notification from the latest snapshot. */
class WidgetRefreshWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        ScheduleWidgetProvider.updateAllWidgets(applicationContext)
        LiveNotificationManager.updateFromPrefs(applicationContext)
        return Result.success()
    }
}
