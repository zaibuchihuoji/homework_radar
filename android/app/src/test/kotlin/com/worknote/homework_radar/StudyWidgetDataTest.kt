package com.worknote.homework_radar

import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test

class StudyWidgetDataTest {
    private val now = 1792317600000L

    private fun date(y: Int, m: Int, d: Int, hour: Int = 0, minute: Int = 0): Long =
        java.util.Calendar.getInstance().apply { clear(); set(y, m - 1, d, hour, minute) }.timeInMillis

    @Test fun oldVersionSnapshotsAndLegacyCachesUseTheSameSemesterAsTheApp() {
        val rows = JSONArray().put(org.json.JSONObject().put("id", "old").put("title", "练习5实验报告").put("d", date(2025,5,17,22,30)))
            .put(org.json.JSONObject().put("id", "current").put("d", date(2026,10,21,20,56)))
            .put(org.json.JSONObject().put("id", "overdue").put("d", date(2026,10,19)))
            .put(org.json.JSONObject().put("id", "undated"))
            .put(org.json.JSONObject().put("id", "next").put("d", date(2027,2,1)))
        val snapshot = org.json.JSONObject().put("version",2).put("items",rows).put("updatedAt",123L).toString()
        for (data in listOf(HomeworkWidgetData.parse(snapshot, null, date(2026,10,20)),
            HomeworkWidgetData.parse(null, rows.toString(), date(2026,10,20)))) {
            assertEquals(setOf("current","overdue","undated"), data.items.map { it.id }.toSet())
            assertEquals(1, data.overdue)
        }
        assertEquals(5, rows.length())
    }

    @Test fun cachedRowsRollOverAtLocalSemesterBoundariesWithoutFlutterRewrite() {
        val rows = JSONArray()
        for ((id, due) in listOf("autumn" to date(2026,8,1), "january" to date(2027,1,31,23,59),
            "spring" to date(2027,2,1), "july" to date(2027,7,31,23,59), "next" to date(2027,8,1))) {
            rows.put(org.json.JSONObject().put("id",id).put("d",due))
        }
        rows.put(org.json.JSONObject().put("id","undated"))
        fun ids(at: Long) = HomeworkWidgetData.parse(null, rows.toString(), at).items.map { it.id }.toSet()
        assertEquals(setOf("autumn","january","undated"), ids(date(2027,1,20)))
        assertEquals(setOf("spring","july","undated"), ids(date(2027,2,1)))
        assertEquals(setOf("next","undated"), ids(date(2027,8,1)))
    }

    @Test fun pendingItemsAreNotLostToOldLimitOrMissingDeadline() {
        val rows = JSONArray()
        repeat(75) { rows.put(org.json.JSONObject().put("id", "$it").put("title", "task$it")
            .put("d", now + (it - 30) * 3600000L)) }
        rows.put(org.json.JSONObject().put("id", "undated").put("title", "unknown"))
        rows.put(org.json.JSONObject().put("id", "done").put("status", "done"))
        val data = HomeworkWidgetData.parse(null, rows.toString(), now)
        assertEquals(76, data.items.size)
        assertEquals(31, data.overdue)
        assertEquals("未设截止", data.items.last().count)
    }
    @Test fun legacySnapshotStillWorksAndDoesNotPretendToHaveAnId() {
        val data = HomeworkWidgetData.parse(null,
            """[{"title":"old task","count":"2天","due":"10/20 截止","u":2}]""", now)
        assertEquals("old task", data.items.single().title)
        assertEquals("", data.items.single().id)
        assertEquals("10/20 截止", data.items.single().deadline)
    }
    @Test fun versionedSnapshotIsAtomicAndExactIdsArePreserved() {
        val data = HomeworkWidgetData.parse(
            """{"version":2,"updatedAt":123,"items":[{"id":"a / & ? # 📚","course":"网络","title":"任务","d":$now}]}""",
            """[{"title":"stale"}]""", now)
        assertEquals(123L, data.updatedAt)
        assertEquals("a / & ? # 📚", data.items.single().id)
        assertEquals("网络", data.items.single().course)
        assertEquals("已逾期", data.items.single().count)
        assertEquals(1, data.overdue)
    }
    @Test fun oneMalformedRowDoesNotHideOtherAssignments() {
        val data = HomeworkWidgetData.parse("broken", """[null,3,{"title":"safe"}]""", now)
        assertEquals("safe", data.items.single().title)
    }
    @Test fun countdownIsShortAndContainsNoFrozenSeconds() {
        val data = HomeworkWidgetData.parse(null,
            """[{"title":"soon","d":${now + 5 * 3600000L + 300000}}]""", now)
        assertEquals("剩余5小时", data.items.single().count)
    }
    @Test fun smallerSizesGiveContentSpaceInsteadOfShrinkingFonts() {
        val tiny = WidgetLayout.forSize(140, 70, 1f)
        assertFalse(tiny.showHeader)
        assertFalse(tiny.showSummary)
        assertFalse(tiny.showFooter)
        val medium = WidgetLayout.forSize(260, 160, 1f)
        assertTrue(medium.showHeader)
        assertFalse(medium.showSummary)
        val large = WidgetLayout.forSize(320, 320, 1.6f)
        assertTrue(large.showSummary)
        assertTrue(large.showFooter)
    }
    @Test fun fontScaleRemovesDecorationBeforeCriticalContent() {
        assertTrue(WidgetLayout.forSize(320, 190, 1f).showSummary)
        assertFalse(WidgetLayout.forSize(320, 190, 1.6f).showSummary)
        assertTrue(WidgetLayout.forSize(150, 150, 1.6f).narrow)
    }
    @Test fun timetableFocusChangesAtTheExactEndOfClassAndKeepsEveryRoom() {
        val items = JSONArray("""[{"n":"早课","s":"8:00","e":"9:40","r":"A101"},
            {"n":"下节课","s":"10:00","e":"11:40","r":"实验楼302"}]""")
        val during = TimetableWidgetPresentation.create(items, 9 * 60)
        assertEquals("早课", during.rows.first().name)
        assertEquals("正在上课", during.rows.first().badge)
        val after = TimetableWidgetPresentation.create(items, 9 * 60 + 40)
        assertEquals("下节课", after.rows.first().name)
        assertEquals("下一节", after.rows.first().badge)
        assertEquals(setOf("A101", "实验楼302"), after.rows.map { it.room }.toSet())
        assertEquals(2, after.rows.size)
    }
    @Test fun unknownTimesStayVisibleAndDoNotProduceAFakeNextClass() {
        val data = TimetableWidgetPresentation.create(JSONArray("""[{"n":"晚课","r":"A201","s":"","e":""}]"""), 1200)
        assertEquals("时间待确认", data.rows.single().badge)
        assertEquals("A201", data.rows.single().room)
        assertEquals("时间待确认", data.hint)
    }
    @Test fun completedDaysDoNotEraseTheirCourses() {
        val data = TimetableWidgetPresentation.create(JSONArray("""[{"n":"早课","s":"8:00","e":"9:40"}]"""), 1200)
        assertEquals("今日课程已结束", data.hint)
        assertEquals("已结束", data.rows.single().badge)
        assertFalse(data.rows.single().focus)
    }
    @Test fun remainingUpcomingClassesPrecedeFinishedClassesAfterTheFocus() {
        val data = TimetableWidgetPresentation.create(JSONArray("""[
            {"n":"早课","s":"8:00","e":"9:40"},
            {"n":"下一节","s":"14:30","e":"16:10"},
            {"n":"晚课","s":"19:00","e":"20:40"}]"""), 600)
        assertEquals(listOf("下一节", "晚课", "早课"), data.rows.map { it.name })
    }
}
