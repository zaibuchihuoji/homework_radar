package com.worknote.homework_radar

import android.content.SharedPreferences
import java.lang.reflect.Proxy
import java.util.Calendar
import org.junit.Assert.assertEquals
import org.junit.Test

class TimetableWidgetDataTest {
    private fun prefs(json: String): SharedPreferences = Proxy.newProxyInstance(
        SharedPreferences::class.java.classLoader, arrayOf(SharedPreferences::class.java)) { _, method, _ ->
        if (method.name == "getString") json else null
    } as SharedPreferences

    @Test fun legacySnapshotsRemainReadable() {
        val old = TimetableWidgetData.read(prefs("""{"header":{"date":"旧日期","week":"第3周"},"items":[{"n":"旧课程","r":"A101"}]}"""))
        assertEquals("旧日期", old.date)
        assertEquals("旧课程", old.items.getJSONObject(0).getString("n"))
    }

    @Test fun anEmptyUnimportedWeekNeedsSetupInsteadOfClaimingNoClasses() {
        val today = TimetableWidgetData.read(prefs("""{"days":{"1":[],"2":[],"3":[],"4":[],"5":[],"6":[],"7":[]}}"""))
        assertEquals(false, today.hasSchedule)
        assertEquals(true, today.valid)
    }

    @Test fun corruptCachesAreNotTreatedAsAConfirmedFreeDay() {
        val today = TimetableWidgetData.read(prefs("not json"))
        assertEquals(false, today.valid)
    }

    @Test fun aDayOffWithCoursesElsewhereInTheWeekIsARealFreeDay() {
        val sunday = Calendar.getInstance().apply { clear(); set(2026, Calendar.OCTOBER, 18) }
        val today = TimetableWidgetData.read(prefs("""{"days":{"1":[{"n":"周一课程"}],"7":[]}}"""), sunday)
        assertEquals(true, today.hasSchedule)
        assertEquals(true, today.valid)
        assertEquals(0, today.items.length())
    }

    @Test fun midnightAndNewWeekUseTheNewDaysClassesWithoutOpeningTheApp() {
        val monday = Calendar.getInstance().apply {
            clear(); set(2026, Calendar.OCTOBER, 12)
        }
        val json = """{"start":${monday.timeInMillis},"days":{
            "7":[{"n":"周日课","w":[1]}],
            "1":[{"n":"第二周课","w":[2]},{"n":"第一周课","w":[1]}]}}"""
        val sunday = (monday.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, 6) }
        val before = TimetableWidgetData.read(prefs(json), sunday)
        assertEquals("周日课", before.items.getJSONObject(0).getString("n"))
        sunday.add(Calendar.DAY_OF_MONTH, 1)
        val after = TimetableWidgetData.read(prefs(json), sunday)
        assertEquals("第2周", after.week)
        assertEquals(1, after.items.length())
        assertEquals("第二周课", after.items.getJSONObject(0).getString("n"))
    }

    @Test fun futureSemesterNeverShowsTodaysClasses() {
        val now = Calendar.getInstance()
        val start = now.clone() as Calendar
        start.add(Calendar.DAY_OF_MONTH, 7)
        while (start.get(Calendar.DAY_OF_WEEK) != Calendar.MONDAY) start.add(Calendar.DAY_OF_MONTH, -1)
        start.set(Calendar.HOUR_OF_DAY, 0)
        start.set(Calendar.MINUTE, 0)
        start.set(Calendar.SECOND, 0)
        start.set(Calendar.MILLISECOND, 0)
        val days = (1..7).joinToString(",") { "\"$it\":[{\"n\":\"future class\",\"w\":[1]}]" }
        val json = "{\"start\":${start.timeInMillis},\"days\":{$days}}"
        val prefs = Proxy.newProxyInstance(SharedPreferences::class.java.classLoader,
            arrayOf(SharedPreferences::class.java)) { _, method, _ ->
            if (method.name == "getString") json else null
        } as SharedPreferences
        val today = TimetableWidgetData.read(prefs)
        assertEquals("未开学", today.week)
        assertEquals(0, today.items.length())
    }
}
