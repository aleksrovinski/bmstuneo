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
                val pairLabel = if (currentLesson.time > 0) "${currentLesson.time} пара" else "Занятие"
                val typePart = if (currentLesson.type.isNotEmpty()) " (${currentLesson.type})" else ""
                val roomPart = if (currentLesson.room.isNotEmpty() && currentLesson.room != "—") " • ауд. ${currentLesson.room}" else ""
                val teacherPart = if (currentLesson.teacher.isNotEmpty() && currentLesson.teacher != "Кафедра") " • ${currentLesson.teacher}" else ""
                val nextPart = if (nextLesson != null) {
                    val nextLabel = if (nextLesson.time > 0) "${nextLesson.time} пара" else "след. занятие"
                    " • Далее: $nextLabel (${nextLesson.startTime})"
                } else {
                    " • Последняя пара 🎉"
                }

                notificationTitle = "Идёт $pairLabel (до ${currentLesson.endTime}): ${currentLesson.title}$typePart"
                notificationText = "${currentLesson.room.let { if (it.isNotEmpty() && it != "—") "Ауд. $it" else "" }}$teacherPart$nextPart".trimStart(' ', '•')

                bigTextBuilder.append("⏳ Текущая: $pairLabel (${currentLesson.startTime}–${currentLesson.endTime})\n")
                bigTextBuilder.append("${currentLesson.title}$typePart")
                if (currentLesson.room.isNotEmpty() && currentLesson.room != "—") bigTextBuilder.append("\n📍 Ауд. ${currentLesson.room}")
                if (currentLesson.teacher.isNotEmpty() && currentLesson.teacher != "Кафедра") bigTextBuilder.append("\n👤 ${currentLesson.teacher}")

                if (nextLesson != null) {
                    val nextLabel = if (nextLesson.time > 0) "${nextLesson.time} пара" else "следующее занятие"
                    val nextType = if (nextLesson.type.isNotEmpty()) " (${nextLesson.type})" else ""
                    bigTextBuilder.append("\n\n➡️ Далее: $nextLabel (${nextLesson.startTime}–${nextLesson.endTime})\n")
                    bigTextBuilder.append("${nextLesson.title}$nextType")
                    if (nextLesson.room.isNotEmpty() && nextLesson.room != "—") bigTextBuilder.append(" • ауд. ${nextLesson.room}")
                } else {
                    bigTextBuilder.append("\n\n🎉 Это последняя пара на сегодня!")
                }
            } else if (nextLesson != null) {
                val until = nextLesson.startMin - currentMinutes
                val isBreak = currentMinutes >= firstLesson.startMin
                val nextLabel = if (nextLesson.time > 0) "${nextLesson.time} пара" else "Занятие"
                val typePart = if (nextLesson.type.isNotEmpty()) " (${nextLesson.type})" else ""
                val roomPart = if (nextLesson.room.isNotEmpty() && nextLesson.room != "—") " • ауд. ${nextLesson.room}" else ""
                val teacherPart = if (nextLesson.teacher.isNotEmpty() && nextLesson.teacher != "Кафедра") " • ${nextLesson.teacher}" else ""

                if (isBreak) {
                    notificationTitle = "Перемена (до ${nextLesson.startTime}) • $nextLabel"
                    notificationText = "${nextLesson.title}$typePart$roomPart$teacherPart"
                    bigTextBuilder.append("☕ Перемена! До звонка осталось $until мин\n\n")
                } else {
                    notificationTitle = "Пары сегодня с ${nextLesson.startTime} • $nextLabel"
                    notificationText = "${nextLesson.title}$typePart$roomPart$teacherPart"
                    bigTextBuilder.append("☀️ До начала занятий осталось $until мин\n\n")
                }

                bigTextBuilder.append("➡️ $nextLabel (${nextLesson.startTime}–${nextLesson.endTime})\n")
                bigTextBuilder.append("${nextLesson.title}$typePart")
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

            // Setup live chronometer target time (countdown to end of pair or to start of next pair)
            val countdownTargetCal = Calendar.getInstance().apply {
                if (currentLesson != null) {
                    set(Calendar.HOUR_OF_DAY, currentLesson.endMin / 60)
                    set(Calendar.MINUTE, currentLesson.endMin % 60)
                    set(Calendar.SECOND, 0)
                } else if (nextLesson != null) {
                    set(Calendar.HOUR_OF_DAY, nextLesson.startMin / 60)
                    set(Calendar.MINUTE, nextLesson.startMin % 60)
                    set(Calendar.SECOND, 0)
                }
            }

            val builder = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(notificationTitle)
                .setContentText(notificationText)
                .setStyle(NotificationCompat.BigTextStyle().bigText(bigTextBuilder.toString()))
                .setContentIntent(pendingIntent)
                .setOngoing(true) // Promoted Live Update ongoing event
                .setOnlyAlertOnce(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setCategory(NotificationCompat.CATEGORY_EVENT)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setColor(0xFF0070F3.toInt()) // BMSTU Blue accent
                .setShowWhen(true)
                .setWhen(countdownTargetCal.timeInMillis)
                .setUsesChronometer(true)
                .setChronometerCountDown(true) // Live countdown ticking on lockscreen & status bar pill
                .addAction(R.mipmap.ic_launcher, "Открыть расписание", pendingIntent)

            // Calculate live progress
            if (currentLesson != null) {
                val totalDuration = (currentLesson.endMin - currentLesson.startMin).coerceAtLeast(1)
                val elapsed = (currentMinutes - currentLesson.startMin).coerceIn(0, totalDuration)
                builder.setProgress(totalDuration, elapsed, false)
                builder.setSubText("Пара ${currentLesson.time} • Live Update")
            } else if (nextLesson != null) {
                val prevEnd = lessonList.findLast { it.endMin <= currentMinutes }?.endMin ?: firstLesson.startMin
                val breakDuration = (nextLesson.startMin - prevEnd).coerceAtLeast(1)
                val elapsed = (currentMinutes - prevEnd).coerceIn(0, breakDuration)
                builder.setProgress(breakDuration, elapsed, false)
                builder.setSubText("Перемена • Live Update")
            }

            // Android 16+ Promoted Ongoing Notification (Live Updates) request
            builder.extras.putBoolean("android.requestPromotedOngoing", true)
            try {
                val setPromotedMethod = builder.javaClass.getMethod("setRequestPromotedOngoing", Boolean::class.javaPrimitiveType)
                setPromotedMethod.invoke(builder, true)
            } catch (e: Exception) {
                // Compatibility mode: already added to extras Bundle
            }

            val notification = builder.build()
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
