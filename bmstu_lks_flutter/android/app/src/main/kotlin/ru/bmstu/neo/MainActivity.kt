package ru.bmstu.neo

import android.Manifest
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val WIDGET_CHANNEL = "ru.bmstu.neo/widget"
    private var pendingPermissionResult: MethodChannel.Result? = null
    private val NOTIFICATION_PERMISSION_REQUEST_CODE = 3001

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == NOTIFICATION_PERMISSION_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "updateWidget" -> {
                    val jsonData = call.argument<String>("scheduleJson")
                    if (jsonData != null) {
                        try {
                            val prefs = getSharedPreferences(ScheduleWidgetProvider.PREFS_NAME, Context.MODE_PRIVATE)
                            prefs.edit().putString(ScheduleWidgetProvider.KEY_SCHEDULE_JSON, jsonData).commit()
                            ScheduleWidgetProvider.updateAllWidgets(applicationContext)
                            LiveNotificationManager.updateFromPrefs(applicationContext)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("UPDATE_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGS", "scheduleJson is null", null)
                    }
                }
                "updateLiveNotification" -> {
                    try {
                        val jsonData = call.argument<String>("scheduleJson")
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        LiveNotificationManager.updateNotification(applicationContext, enabled, jsonData)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("NOTIFICATION_ERROR", e.message, null)
                    }
                }
                "setLiveNotificationEnabled" -> {
                    try {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        LiveNotificationManager.setEnabled(applicationContext, enabled)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("NOTIFICATION_ERROR", e.message, null)
                    }
                }
                "isLiveNotificationEnabled" -> {
                    try {
                        val enabled = LiveNotificationManager.isEnabled(applicationContext)
                        result.success(enabled)
                    } catch (e: Exception) {
                        result.success(true)
                    }
                }
                "cancelLiveNotification" -> {
                    try {
                        LiveNotificationManager.cancelNotification(applicationContext)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CANCEL_ERROR", e.message, null)
                    }
                }
                "hasNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        val granted = ContextCompat.checkSelfPermission(
                            this,
                            Manifest.permission.POST_NOTIFICATIONS
                        ) == PackageManager.PERMISSION_GRANTED
                        result.success(granted)
                    } else {
                        val granted = NotificationManagerCompat.from(this).areNotificationsEnabled()
                        result.success(granted)
                    }
                }
                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        val alreadyGranted = ContextCompat.checkSelfPermission(
                            this,
                            Manifest.permission.POST_NOTIFICATIONS
                        ) == PackageManager.PERMISSION_GRANTED
                        if (alreadyGranted) {
                            result.success(true)
                        } else {
                            pendingPermissionResult = result
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                NOTIFICATION_PERMISSION_REQUEST_CODE
                            )
                        }
                    } else {
                        val granted = NotificationManagerCompat.from(this).areNotificationsEnabled()
                        result.success(granted)
                    }
                }
                "isPinningSupported" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val appWidgetManager = AppWidgetManager.getInstance(applicationContext)
                        result.success(appWidgetManager.isRequestPinAppWidgetSupported)
                    } else {
                        result.success(false)
                    }
                }
                "pinWidget" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val appWidgetManager = AppWidgetManager.getInstance(applicationContext)
                        if (appWidgetManager.isRequestPinAppWidgetSupported) {
                            val provider = ComponentName(applicationContext, ScheduleWidgetProvider::class.java)
                            val success = appWidgetManager.requestPinAppWidget(provider, null, null)
                            result.success(success)
                        } else {
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
