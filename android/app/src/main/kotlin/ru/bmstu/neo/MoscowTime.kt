package ru.bmstu.neo

import java.util.Calendar
import java.util.TimeZone

/** BMSTU pairs follow Moscow time wherever the phone is; see lib/constants/moscow_time.dart. */
object MoscowTime {
    private val zone: TimeZone = TimeZone.getTimeZone("Europe/Moscow")

    /** A calendar on the Moscow clock: hours and minutes compare with lesson times. */
    fun calendar(): Calendar = Calendar.getInstance(zone)
}
