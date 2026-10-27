package ru.bmstu.neo

import android.content.Context
import android.util.Log
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import dev.fluttercommunity.workmanager.BackgroundWorker

/**
 * Silent (data-only) FCM pushes wake the same Dart BackgroundSync task the periodic
 * WorkManager check runs. The push carries no student data: it only says "check now".
 */
class PushMessagingService : FirebaseMessagingService() {

    override fun onMessageReceived(message: RemoteMessage) {
        if (message.data["type"] == SYNC_TYPE) {
            Log.d(TAG, "Silent push: scheduling progress sync")
            enqueueSync(applicationContext)
        }
    }

    // The new token is picked up by the app the next time notifications are enabled
    // or it starts; the server learns tokens only through the app.
    override fun onNewToken(token: String) {
        Log.d(TAG, "FCM token refreshed")
        getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY_TOKEN, token).apply()
    }

    companion object {
        private const val TAG = "PushMessagingService"
        const val SYNC_TYPE = "sync"
        // Same name the Dart side registers its periodic task with (BackgroundSync.taskId)
        private const val DART_TASK = "ru.bmstu.neo.sync"
        private const val UNIQUE_WORK = "ru.bmstu.neo.push-sync"
        private const val PREFS = "ru.bmstu.neo.push"
        private const val KEY_TOKEN = "fcm_token"

        fun enqueueSync(context: Context) {
            val request = OneTimeWorkRequestBuilder<BackgroundWorker>()
                .setInputData(workDataOf(BackgroundWorker.DART_TASK_KEY to DART_TASK))
                .setConstraints(Constraints(requiredNetworkType = NetworkType.CONNECTED))
                .build()
            // Several pushes in a row collapse into one pending sync; once the Dart sync has
            // stored a fresh schedule snapshot, redraw the widget and the live notification
            WorkManager.getInstance(context)
                .beginUniqueWork(UNIQUE_WORK, ExistingWorkPolicy.KEEP, request)
                .then(OneTimeWorkRequestBuilder<WidgetRefreshWorker>().build())
                .enqueue()
        }

        /** Turns FCM on (it is off until the student enables notifications) and returns the token. */
        fun enable(onToken: (String?) -> Unit) {
            val messaging = FirebaseMessaging.getInstance()
            messaging.isAutoInitEnabled = true
            messaging.token.addOnCompleteListener { task ->
                if (!task.isSuccessful) Log.w(TAG, "FCM token unavailable", task.exception)
                onToken(if (task.isSuccessful) task.result else null)
            }
        }

        /** Stops FCM and invalidates the token, so this device can no longer be woken up. */
        fun disable(onDone: () -> Unit) {
            val messaging = FirebaseMessaging.getInstance()
            messaging.isAutoInitEnabled = false
            messaging.deleteToken().addOnCompleteListener { onDone() }
        }
    }
}
