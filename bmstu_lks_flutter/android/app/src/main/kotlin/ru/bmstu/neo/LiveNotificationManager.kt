package ru.bmstu.neo

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.graphics.drawable.IconCompat
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

object LiveNotificationManager {
    const val CHANNEL_ID = "ru.bmstu.neo.live_activity_v2"
    const val CHANNEL_NAME = "Live Updates (Текущая и следующая пара)"
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
                    NotificationManager.IMPORTANCE_DEFAULT
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
        val scheduleJson = ScheduleWidgetProvider.latestScheduleJson(context)
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
                val time = l.optInt("pairNumber", 0)
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

            val appIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                appIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val builder = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_notif_school)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setSilent(true) // Never beep or vibrate on the per-minute refreshes
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_STATUS)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setColor(0xFF0070F3.toInt())
                .setRequestPromotedOngoing(true) // Android 16 Live Update
                .addAction(R.drawable.ic_notif_calendar, "Расписание", pendingIntent)

            // Header: pair number or break, plus a live countdown the system ticks by itself
            // No bar before the first pair: there is nothing to measure yet
            var progress: NotificationCompat.ProgressStyle? = null
            val countdownTo: Int
            if (currentLesson != null) {
                countdownTo = currentLesson.endMin
                builder.setContentTitle(currentLesson.title)
                    .setContentText(details(currentLesson.room, currentLesson.type, currentLesson.teacher, nextLesson))
                    .setSubText(pairLabel(currentLesson))
                    .setShortCriticalText("до ${currentLesson.endTime}")
                val total = (currentLesson.endMin - currentLesson.startMin).coerceAtLeast(1)
                progress = NotificationCompat.ProgressStyle().setProgressSegments(listOf(NotificationCompat.ProgressStyle.Segment(total)))
                    .setProgress((currentMinutes - currentLesson.startMin).coerceIn(0, total))
                    .setProgressTrackerIcon(IconCompat.createWithResource(context, R.drawable.ic_notif_school))
                    .setProgressEndIcon(IconCompat.createWithResource(context, R.drawable.ic_notif_flag))
            } else if (nextLesson != null) {
                countdownTo = nextLesson.startMin
                val isBreak = currentMinutes >= firstLesson.startMin
                builder.setContentTitle(nextLesson.title)
                    .setContentText(details(nextLesson.room, nextLesson.type, nextLesson.teacher, null, startsAt = nextLesson.startTime))
                    .setSubText(if (isBreak) "Перемена" else "До начала пар")
                    .setShortCriticalText("в ${nextLesson.startTime}")
                if (isBreak) {
                    val prevEnd = lessonList.lastOrNull { it.endMin <= currentMinutes }?.endMin ?: firstLesson.startMin
                    val total = (nextLesson.startMin - prevEnd).coerceAtLeast(1)
                    progress = NotificationCompat.ProgressStyle().setProgressSegments(listOf(NotificationCompat.ProgressStyle.Segment(total)))
                        .setProgress((currentMinutes - prevEnd).coerceIn(0, total))
                        .setProgressTrackerIcon(IconCompat.createWithResource(context, R.drawable.ic_notif_break))
                        .setProgressEndIcon(IconCompat.createWithResource(context, R.drawable.ic_notif_school))
                }
            } else {
                cancelNotification(context)
                return
            }
            val countdownCal = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, countdownTo / 60)
                set(Calendar.MINUTE, countdownTo % 60)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            builder.setShowWhen(true)
                .setWhen(countdownCal.timeInMillis)
                .setUsesChronometer(true)
                .setChronometerCountDown(true)
            progress?.let { builder.setStyle(it) }

            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            notificationManager?.notify(NOTIFICATION_ID, builder.build())

            // Schedule next refresh at next pair boundary
            scheduleNextRefresh(context, lessonList, currentMinutes)
        } catch (e: Exception) {
            // Ignore
        }
    }

    /**
     * Wakes the device at the next pair start or end; in between, refreshes the progress bar
     * once a minute without waking the device (it catches up as soon as the screen turns on).
     */
    private fun scheduleNextRefresh(context: Context, lessonList: List<LessonSlot>, currentMinutes: Int) {
        try {
            val boundary = lessonList
                .flatMap { listOf(it.startMin, it.endMin) }
                .filter { it > currentMinutes }
                .minOrNull() ?: return
            val dayStarted = currentMinutes >= lessonList.first().startMin
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                ALARM_REQUEST_CODE,
                Intent(context, LiveNotificationReceiver::class.java).apply { action = ALARM_ACTION },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val exactAllowed = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()

            if (dayStarted && boundary - currentMinutes > 1) {
                val tick = Calendar.getInstance().apply {
                    add(Calendar.MINUTE, 1)
                    set(Calendar.SECOND, 1)
                    set(Calendar.MILLISECOND, 0)
                }.timeInMillis
                if (exactAllowed) {
                    alarmManager.setExact(AlarmManager.RTC, tick, pendingIntent)
                } else {
                    alarmManager.setWindow(AlarmManager.RTC, tick, 30_000L, pendingIntent)
                }
                return
            }

            val target = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, boundary / 60)
                set(Calendar.MINUTE, boundary % 60)
                set(Calendar.SECOND, 2)
                set(Calendar.MILLISECOND, 0)
            }.timeInMillis
            if (exactAllowed) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, target, pendingIntent)
            } else {
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, target, pendingIntent)
            }
        } catch (e: Exception) {
            // Ignore
        }
    }

    private fun pairLabel(lesson: LessonSlot) = if (lesson.time > 0) "${lesson.time} пара" else "Занятие"

    /** One line with what the title doesn't say: room, type, teacher, then the next pair. */
    private fun details(room: String, type: String, teacher: String, next: LessonSlot?, startsAt: String? = null): String {
        val parts = mutableListOf<String>()
        if (startsAt != null) parts.add("с $startsAt")
        if (room.isNotEmpty() && room != "—") parts.add("ауд. $room")
        if (type.isNotEmpty()) parts.add(type.lowercase())
        if (teacher.isNotEmpty() && teacher != "Кафедра") parts.add(teacher)
        if (next != null) {
            val nextRoom = if (next.room.isNotEmpty() && next.room != "—") ", ${next.room}" else ""
            parts.add("далее в ${next.startTime}: ${next.title}$nextRoom")
        }
        return parts.joinToString(" · ")
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
