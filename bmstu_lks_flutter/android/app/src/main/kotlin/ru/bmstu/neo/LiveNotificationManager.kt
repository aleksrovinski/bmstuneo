package ru.bmstu.neo

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

object LiveNotificationManager {
    const val CHANNEL_ID = "ru.bmstu.neo.live_activity"
    const val CHANNEL_NAME = "Live Activity (Текущая и следующая пара)"
    const val NOTIFICATION_ID = 2002
    const val KEY_NOTIFICATION_ENABLED = "live_notification_enabled"
    private const val ALARM_ACTION = "ru.bmstu.neo.ACTION_REFRESH_LIVE_NOTIFICATION"
    private const val ALARM_REQUEST_CODE = 2003

    fun createNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            val existing = notificationManager?.getNotificationChannel(CHANNEL_ID)
            if (existing == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Отображает текущую пару, время до конца и следующую пару в дни занятий"
                    setShowBadge(false)
                    enableVibration(false)
                    setSound(null, null)
                }
                notificationManager?.createNotificationChannel(channel)
            }
        }
    }

    fun isEnabled(context: Context): Boolean {
        val prefs = context.getSharedPreferences(ScheduleWidgetProvider.PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getBoolean(KEY_NOTIFICATION_ENABLED, true)
    }

    fun setEnabled(context: Context, enabled: Boolean) {
        val prefs = context.getSharedPreferences(ScheduleWidgetProvider.PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().putBoolean(KEY_NOTIFICATION_ENABLED, enabled).commit()
        if (!enabled) {
            cancelNotification(context)
        } else {
            updateFromPrefs(context)
        }
    }

    fun cancelNotification(context: Context) {
        try {
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            notificationManager?.cancel(NOTIFICATION_ID)

            // Cancel any scheduled alarm
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
            val intent = Intent(context, LiveNotificationReceiver::class.java).apply {
                action = ALARM_ACTION
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                ALARM_REQUEST_CODE,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            alarmManager?.cancel(pendingIntent)
        } catch (e: Exception) {
            // Ignore
        }
    }

    fun updateFromPrefs(context: Context) {
        val prefs = context.getSharedPreferences(ScheduleWidgetProvider.PREFS_NAME, Context.MODE_PRIVATE)
        val enabled = prefs.getBoolean(KEY_NOTIFICATION_ENABLED, true)
        val scheduleJson = prefs.getString(ScheduleWidgetProvider.KEY_SCHEDULE_JSON, null)
        updateNotification(context, enabled, scheduleJson)
    }

    fun updateNotification(context: Context, enabled: Boolean, scheduleJson: String?) {
        if (!enabled || scheduleJson == null) {
            cancelNotification(context)
            return
        }

        try {
            createNotificationChannel(context)
            val json = JSONObject(scheduleJson)
            val isTomorrow = json.optBoolean("isTomorrow", false)
            val lessons = json.optJSONArray("lessons") ?: JSONArray()

            // Requirement: "появляется только в день когда есть пары"
            // If today is a day without lessons or today has finished (isTomorrow=true), hide notification
            if (isTomorrow || lessons.length() == 0) {
                cancelNotification(context)
                return
            }

            val cal = Calendar.getInstance()
            val currentMinutes = cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE)

            // Parse lessons into list
            val lessonList = mutableListOf<LessonSlot>()
            for (i in 0 until lessons.length()) {
                val l = lessons.optJSONObject(i) ?: continue
                val time = l.optInt("time", i + 1)
                val startTime = l.optString("startTime", "")
                val endTime = l.optString("endTime", "")
                val title = l.optString("disciplineTitle", "")
                val type = l.optString("actTypeTitle", "")
                val room = l.optString("audiencesFormatted", "")
                val teacher = l.optString("teachersFormatted", "")

                val startMin = parseTimeToMinutes(startTime)
                val endMin = parseTimeToMinutes(endTime)
                if (startMin != null && endMin != null) {
                    lessonList.add(LessonSlot(time, startTime, endTime, startMin, endMin, title, type, room, teacher))
                }
            }

            if (lessonList.isEmpty()) {
                cancelNotification(context)
                return
            }

            lessonList.sortBy { it.startMin }

            val firstLesson = lessonList.first()
            val lastLesson = lessonList.last()

            // If the day's lessons are entirely over, dismiss notification
            if (currentMinutes > lastLesson.endMin) {
                cancelNotification(context)
                return
            }

            var currentLesson: LessonSlot? = null
            var nextLesson: LessonSlot? = null

            for (l in lessonList) {
                if (currentMinutes in l.startMin..l.endMin) {
                    currentLesson = l
                } else if (currentMinutes < l.startMin && nextLesson == null) {
                    nextLesson = l
                }
            }

            val notificationTitle: String
            val notificationText: String
            val bigTextBuilder = StringBuilder()

            if (currentLesson != null) {
                val remaining = currentLesson.endMin - currentMinutes
                notificationTitle = "Идёт ${currentLesson.time} пара: ${currentLesson.title}"
                val roomPart = if (currentLesson.room.isNotEmpty() && currentLesson.room != "—") " • ауд. ${currentLesson.room}" else ""
                val nextPart = if (nextLesson != null) " • Далее: ${nextLesson.time} пара (${nextLesson.startTime})" else " • Последняя пара"
                notificationText = "Осталось $remaining мин$roomPart$nextPart"

                bigTextBuilder.append("⏳ Текущая: ${currentLesson.time} пара (${currentLesson.startTime}–${currentLesson.endTime})\n")
                bigTextBuilder.append("${currentLesson.title}")
                if (currentLesson.type.isNotEmpty()) bigTextBuilder.append(" (${currentLesson.type})")
                if (currentLesson.room.isNotEmpty() && currentLesson.room != "—") bigTextBuilder.append("\n📍 Ауд. ${currentLesson.room}")
                if (currentLesson.teacher.isNotEmpty() && currentLesson.teacher != "Кафедра") bigTextBuilder.append("\n👤 ${currentLesson.teacher}")
                bigTextBuilder.append("\n⏱ Осталось: $remaining мин")

                if (nextLesson != null) {
                    bigTextBuilder.append("\n\n➡️ Следующая: ${nextLesson.time} пара (${nextLesson.startTime})\n")
                    bigTextBuilder.append("${nextLesson.title}")
                    if (nextLesson.room.isNotEmpty() && nextLesson.room != "—") bigTextBuilder.append(" • ауд. ${nextLesson.room}")
                } else {
                    bigTextBuilder.append("\n\n🎉 Это последняя пара на сегодня!")
                }
            } else if (nextLesson != null) {
                val until = nextLesson.startMin - currentMinutes
                val isBreak = currentMinutes >= firstLesson.startMin
                val roomPart = if (nextLesson.room.isNotEmpty() && nextLesson.room != "—") " • ауд. ${nextLesson.room}" else ""

                if (isBreak) {
                    notificationTitle = "Перемена • След. пара в ${nextLesson.startTime} (через $until мин)"
                    notificationText = "${nextLesson.time} пара: ${nextLesson.title}$roomPart"
                    bigTextBuilder.append("☕ Перемена! До пары осталось $until мин\n\n")
                } else {
                    notificationTitle = "Сегодня пары с ${nextLesson.startTime} (через $until мин)"
                    notificationText = "1-я пара: ${nextLesson.title}$roomPart"
                    bigTextBuilder.append("☀️ До первой пары осталось $until мин\n\n")
                }

                bigTextBuilder.append("➡️ ${nextLesson.time} пара (${nextLesson.startTime}–${nextLesson.endTime})\n")
                bigTextBuilder.append("${nextLesson.title}")
                if (nextLesson.type.isNotEmpty()) bigTextBuilder.append(" (${nextLesson.type})")
                if (nextLesson.room.isNotEmpty() && nextLesson.room != "—") bigTextBuilder.append("\n📍 Ауд. ${nextLesson.room}")
                if (nextLesson.teacher.isNotEmpty() && nextLesson.teacher != "Кафедра") bigTextBuilder.append("\n👤 ${nextLesson.teacher}")
            } else {
                cancelNotification(context)
                return
            }

            val appIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                appIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(notificationTitle)
                .setContentText(notificationText)
                .setStyle(NotificationCompat.BigTextStyle().bigText(bigTextBuilder.toString()))
                .setContentIntent(pendingIntent)
                .setOngoing(true) // Live Activity sticky behavior!
                .setOnlyAlertOnce(true)
                .setShowWhen(false)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setCategory(NotificationCompat.CATEGORY_STATUS)
                .build()

            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            notificationManager?.notify(NOTIFICATION_ID, notification)

            // Schedule next refresh at next pair boundary
            scheduleNextRefresh(context, lessonList, currentMinutes)
        } catch (e: Exception) {
            // Ignore
        }
    }

    private fun scheduleNextRefresh(context: Context, lessonList: List<LessonSlot>, currentMinutes: Int) {
        try {
            var nextTriggerMinutes: Int? = null

            for (l in lessonList) {
                if (l.startMin > currentMinutes) {
                    if (nextTriggerMinutes == null || l.startMin < nextTriggerMinutes) {
                        nextTriggerMinutes = l.startMin
                    }
                }
                if (l.endMin > currentMinutes) {
                    if (nextTriggerMinutes == null || l.endMin < nextTriggerMinutes) {
                        nextTriggerMinutes = l.endMin
                    }
                }
            }

            if (nextTriggerMinutes != null) {
                val targetCal = Calendar.getInstance().apply {
                    set(Calendar.HOUR_OF_DAY, nextTriggerMinutes / 60)
                    set(Calendar.MINUTE, nextTriggerMinutes % 60)
                    set(Calendar.SECOND, 2)
                    set(Calendar.MILLISECOND, 0)
                }

                val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
                val intent = Intent(context, LiveNotificationReceiver::class.java).apply {
                    action = ALARM_ACTION
                }
                val pendingIntent = PendingIntent.getBroadcast(
                    context,
                    ALARM_REQUEST_CODE,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )

                if (alarmManager != null) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        alarmManager.setExactAndAllowWhileIdle(
                            AlarmManager.RTC_WAKEUP,
                            targetCal.timeInMillis,
                            pendingIntent
                        )
                    } else {
                        alarmManager.setExact(
                            AlarmManager.RTC_WAKEUP,
                            targetCal.timeInMillis,
                            pendingIntent
                        )
                    }
                }
            }
        } catch (e: Exception) {
            // Ignore
        }
    }

    private fun parseTimeToMinutes(timeStr: String): Int? {
        val parts = timeStr.trim().split(":")
        if (parts.size >= 2) {
            val h = parts[0].toIntOrNull()
            val m = parts[1].toIntOrNull()
            if (h != null && m != null) {
                return h * 60 + m
            }
        }
        return null
    }

    private data class LessonSlot(
        val time: Int,
        val startTime: String,
        val endTime: String,
        val startMin: Int,
        val endMin: Int,
        val title: String,
        val type: String,
        val room: String,
        val teacher: String
    )
}
