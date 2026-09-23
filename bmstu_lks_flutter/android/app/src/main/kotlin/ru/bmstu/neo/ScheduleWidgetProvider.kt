package ru.bmstu.neo

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

class ScheduleWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_REFRESH_WIDGET) {
            updateAllWidgets(context)
        }
    }

    companion object {
        const val PREFS_NAME = "bmstu_widget_prefs"
        const val KEY_SCHEDULE_JSON = "widget_schedule_data"
        const val ACTION_REFRESH_WIDGET = "ru.bmstu.neo.REFRESH_WIDGET"

        fun updateAllWidgets(context: Context) {
            try {
                val appWidgetManager = AppWidgetManager.getInstance(context)
                val componentName = ComponentName(context, ScheduleWidgetProvider::class.java)
                val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)

                for (appWidgetId in appWidgetIds) {
                    updateAppWidget(context, appWidgetManager, appWidgetId)
                }
            } catch (e: Exception) {
                // Ignore
            }
        }

        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val views = RemoteViews(context.packageName, R.layout.schedule_widget)
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val rawJson = prefs.getString(KEY_SCHEDULE_JSON, null)

            // Setup PendingIntent to launch app when clicking anywhere on the widget
            val appIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                appIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            views.setOnClickPendingIntent(R.id.widget_empty_view, pendingIntent)
            views.setOnClickPendingIntent(R.id.widget_lessons_container, pendingIntent)

            if (rawJson != null) {
                try {
                    val json = JSONObject(rawJson)
                    val groupTitle = json.optString("groupTitle", "МГТУ")
                    val dayTitle = json.optString("dayTitle", "Расписание")
                    val weekParity = json.optString("weekParity", "")
                    val dynamicHeadline = computeDynamicStatus(json)
                    val lessons = json.optJSONArray("lessons") ?: JSONArray()
                    val hasLessons = lessons.length() > 0

                    views.setTextViewText(R.id.widget_group_title, groupTitle)
                    views.setTextViewText(R.id.widget_day_title, dayTitle)
                    views.setTextViewText(R.id.widget_week_parity, weekParity)
                    views.setTextViewText(R.id.widget_status_headline, dynamicHeadline)

                    if (!hasLessons) {
                        val isTomorrow = json.optBoolean("isTomorrow", false)
                        val emptyMsg = if (isTomorrow) {
                            "На завтра пар нет! Отдыхайте ✨"
                        } else {
                            "На сегодня пар нет! Отдыхайте 🎉"
                        }
                        views.setTextViewText(R.id.widget_empty_text, emptyMsg)
                        views.setViewVisibility(R.id.widget_empty_view, View.VISIBLE)
                        views.setViewVisibility(R.id.widget_lessons_container, View.GONE)
                    } else {
                        views.setViewVisibility(R.id.widget_empty_view, View.GONE)
                        views.setViewVisibility(R.id.widget_lessons_container, View.VISIBLE)

                        // Bind rows 1 to 4
                        bindLessonRow(
                            views,
                            rowLayoutId = R.id.row_1,
                            numId = R.id.row_1_num,
                            timeId = R.id.row_1_time,
                            typeId = R.id.row_1_type,
                            roomId = R.id.row_1_room,
                            titleId = R.id.row_1_title,
                            lesson = if (lessons.length() > 0) lessons.optJSONObject(0) else null,
                            pairIndex = 0
                        )

                        bindLessonRow(
                            views,
                            rowLayoutId = R.id.row_2,
                            numId = R.id.row_2_num,
                            timeId = R.id.row_2_time,
                            typeId = R.id.row_2_type,
                            roomId = R.id.row_2_room,
                            titleId = R.id.row_2_title,
                            lesson = if (lessons.length() > 1) lessons.optJSONObject(1) else null,
                            pairIndex = 1
                        )

                        bindLessonRow(
                            views,
                            rowLayoutId = R.id.row_3,
                            numId = R.id.row_3_num,
                            timeId = R.id.row_3_time,
                            typeId = R.id.row_3_type,
                            roomId = R.id.row_3_room,
                            titleId = R.id.row_3_title,
                            lesson = if (lessons.length() > 2) lessons.optJSONObject(2) else null,
                            pairIndex = 2
                        )

                        bindLessonRow(
                            views,
                            rowLayoutId = R.id.row_4,
                            numId = R.id.row_4_num,
                            timeId = R.id.row_4_time,
                            typeId = R.id.row_4_type,
                            roomId = R.id.row_4_room,
                            titleId = R.id.row_4_title,
                            lesson = if (lessons.length() > 3) lessons.optJSONObject(3) else null,
                            pairIndex = 3
                        )

                        // More indicator
                        if (lessons.length() > 4) {
                            val moreCount = lessons.length() - 4
                            views.setTextViewText(R.id.widget_row_more, "+ ещё $moreCount пар(ы) в приложении →")
                            views.setViewVisibility(R.id.widget_row_more, View.VISIBLE)
                        } else {
                            views.setViewVisibility(R.id.widget_row_more, View.GONE)
                        }

                        // Schedule exact AlarmManager updates when pair starts or ends
                        scheduleNextRefresh(context, json)
                    }
                } catch (e: Exception) {
                    views.setTextViewText(R.id.widget_status_headline, "Нажмите, чтобы открыть")
                    views.setViewVisibility(R.id.widget_empty_view, View.VISIBLE)
                    views.setViewVisibility(R.id.widget_lessons_container, View.GONE)
                }
            } else {
                // Fallback default state before first app sync
                views.setTextViewText(R.id.widget_group_title, "МГТУ")
                views.setTextViewText(R.id.widget_day_title, "Расписание пар")
                views.setTextViewText(R.id.widget_week_parity, "")
                views.setTextViewText(R.id.widget_status_headline, "Нажмите для перехода в приложение")
                views.setTextViewText(R.id.widget_empty_text, "Нажмите, чтобы открыть расписание")
                views.setViewVisibility(R.id.widget_empty_view, View.VISIBLE)
                views.setViewVisibility(R.id.widget_lessons_container, View.GONE)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
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

        private fun computeDynamicStatus(json: JSONObject): String {
            val lessons = json.optJSONArray("lessons") ?: return json.optString("statusHeadline", "")
            if (lessons.length() == 0) {
                val isTomorrow = json.optBoolean("isTomorrow", false)
                return if (isTomorrow) "На завтра пар нет" else "На сегодня пар нет"
            }

            val isTomorrow = json.optBoolean("isTomorrow", false)
            if (isTomorrow) {
                val firstLesson = lessons.optJSONObject(0)
                val startTime = firstLesson?.optString("startTime", "") ?: ""
                val firstTitle = firstLesson?.optString("disciplineTitle", "") ?: ""
                return if (startTime.isNotEmpty()) "Завтра: 1 пара в $startTime • $firstTitle" else "Расписание на завтра"
            }

            val cal = Calendar.getInstance()
            val currentMinutes = cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE)

            var currentLesson: JSONObject? = null
            var nextLesson: JSONObject? = null

            for (i in 0 until lessons.length()) {
                val l = lessons.optJSONObject(i) ?: continue
                val startTime = l.optString("startTime", "")
                val endTime = l.optString("endTime", "")
                val startMin = parseTimeToMinutes(startTime)
                val endMin = parseTimeToMinutes(endTime)

                if (startMin != null && endMin != null) {
                    if (currentMinutes in startMin..endMin) {
                        currentLesson = l
                        break
                    } else if (currentMinutes < startMin && nextLesson == null) {
                        nextLesson = l
                    }
                }
            }

            return when {
                currentLesson != null -> {
                    val title = currentLesson.optString("disciplineTitle", "")
                    val endTime = currentLesson.optString("endTime", "")
                    val endMin = parseTimeToMinutes(endTime)
                    val remaining = if (endMin != null) endMin - currentMinutes else 0
                    if (remaining > 0) "Идёт пара ($remaining мин до конца) • $title" else "Идёт пара (до $endTime) • $title"
                }
                nextLesson != null -> {
                    val startTime = nextLesson.optString("startTime", "")
                    val title = nextLesson.optString("disciplineTitle", "")
                    val startMin = parseTimeToMinutes(startTime)
                    val until = if (startMin != null) startMin - currentMinutes else 0
                    if (until > 0) "След. пара через $until мин ($startTime) • $title" else "След. пара в $startTime • $title"
                }
                else -> {
                    "Все пары на сегодня завершены 🎉"
                }
            }
        }

        private fun scheduleNextRefresh(context: Context, json: JSONObject) {
            try {
                val lessons = json.optJSONArray("lessons") ?: return
                val isTomorrow = json.optBoolean("isTomorrow", false)
                if (isTomorrow) return

                val cal = Calendar.getInstance()
                val currentMinutes = cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE)

                var nextTriggerMinutes: Int? = null

                for (i in 0 until lessons.length()) {
                    val l = lessons.optJSONObject(i) ?: continue
                    val startMin = parseTimeToMinutes(l.optString("startTime", ""))
                    val endMin = parseTimeToMinutes(l.optString("endTime", ""))

                    if (startMin != null && startMin > currentMinutes) {
                        if (nextTriggerMinutes == null || startMin < nextTriggerMinutes) {
                            nextTriggerMinutes = startMin
                        }
                    }
                    if (endMin != null && endMin > currentMinutes) {
                        if (nextTriggerMinutes == null || endMin < nextTriggerMinutes) {
                            nextTriggerMinutes = endMin
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
                    val intent = Intent(context, ScheduleWidgetProvider::class.java).apply {
                        action = ACTION_REFRESH_WIDGET
                    }
                    val pendingIntent = PendingIntent.getBroadcast(
                        context,
                        1001,
                        intent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    alarmManager?.set(AlarmManager.RTC, targetCal.timeInMillis, pendingIntent)
                }
            } catch (_: Exception) {}
        }

        private fun bindLessonRow(
            views: RemoteViews,
            rowLayoutId: Int,
            numId: Int,
            timeId: Int,
            typeId: Int,
            roomId: Int,
            titleId: Int,
            lesson: JSONObject?,
            pairIndex: Int
        ) {
            if (lesson != null) {
                views.setViewVisibility(rowLayoutId, View.VISIBLE)
                views.setTextViewText(numId, (pairIndex + 1).toString())
                views.setTextViewText(timeId, lesson.optString("time", ""))

                val type = lesson.optString("type", "")
                if (type.isNotEmpty()) {
                    views.setTextViewText(typeId, type)
                    views.setViewVisibility(typeId, View.VISIBLE)
                } else {
                    views.setViewVisibility(typeId, View.GONE)
                }

                val room = lesson.optString("room", "")
                views.setTextViewText(roomId, if (room.isNotEmpty()) "ауд. $room" else "")
                views.setTextViewText(titleId, lesson.optString("disciplineTitle", ""))
            } else {
                views.setViewVisibility(rowLayoutId, View.GONE)
            }
        }
    }
}
