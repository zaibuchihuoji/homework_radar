package com.worknote.homework_radar

import java.util.Calendar
import java.time.LocalDate

/** Calendar dates, rather than elapsed 24-hour durations, keep DST and pre-semester weeks correct. */
internal object TimetableWeek {
    fun number(startMs: Long, today: Calendar): Int {
        val start = (today.clone() as Calendar).apply { timeInMillis = startMs }
        fun day(c: Calendar) = LocalDate.of(c.get(Calendar.YEAR),
            c.get(Calendar.MONTH) + 1, c.get(Calendar.DAY_OF_MONTH))
        val a = day(start).let { it.minusDays((it.dayOfWeek.value - 1).toLong()) }
        val b = day(today).let { it.minusDays((it.dayOfWeek.value - 1).toLong()) }
        return Math.floorDiv(b.toEpochDay() - a.toEpochDay(), 7L).toInt() + 1
    }
}
