package com.worknote.homework_radar

import java.util.Calendar
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Test

class TimetableWeekTest {
    private fun date(day: Int): Calendar = Calendar.getInstance(TimeZone.getTimeZone("Asia/Shanghai")).apply {
        clear()
        set(2026, Calendar.SEPTEMBER, day)
    }

    @Test fun preSemesterHasNoActiveWeek() {
        // First Monday is September 7: every day of the previous week is week 0.
        for (d in 1..6) assertEquals(0, TimetableWeek.number(date(7).timeInMillis, date(d)))
    }

    @Test fun mondayBoundaryAndFollowingWeek() {
        assertEquals(1, TimetableWeek.number(date(7).timeInMillis, date(7)))
        assertEquals(1, TimetableWeek.number(date(7).timeInMillis, date(13)))
        assertEquals(2, TimetableWeek.number(date(7).timeInMillis, date(14)))
    }

    @Test fun springDaylightSavingDoesNotDelayTheNextWeek() {
        val start = Calendar.getInstance(TimeZone.getTimeZone("America/New_York")).apply {
            clear(); set(2026, Calendar.MARCH, 2)
        }
        val next = (start.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, 7) }
        assertEquals(2, TimetableWeek.number(start.timeInMillis, next))
    }
}
