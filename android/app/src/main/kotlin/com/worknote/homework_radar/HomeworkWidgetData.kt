package com.worknote.homework_radar

import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/** Read-only presentation of the new atomic snapshot or a pre-upgrade cache. */
internal object HomeworkWidgetData {
    data class Row(val id: String, val title: String, val course: String,
        val dueMs: Long, val count: String, val deadline: String, val overdue: Boolean)
    data class Snapshot(val items: List<Row>, val updatedAt: Long, val overdue: Int,
        val dueToday: Int, val hasData: Boolean)

    fun parse(snapshot: String?, legacy: String?, now: Long = System.currentTimeMillis()): Snapshot {
        val root = (try { JSONObject(snapshot ?: "") } catch (_: Exception) { null })
            ?.takeIf { it.optJSONArray("items") != null }
        val rows = root?.optJSONArray("items")
            ?: try { JSONArray(legacy ?: "[]") } catch (_: Exception) { JSONArray() }
        val today = Calendar.getInstance().apply { timeInMillis = now }
        // Apply the app's semester rule even to a cache written by an older
        // version, or across rollover while Flutter is not running. Read only.
        val month = today.get(Calendar.MONTH)
        val year = today.get(Calendar.YEAR)
        val semesterStart = Calendar.getInstance().apply {
            clear()
            when {
                month >= Calendar.AUGUST -> set(year, Calendar.AUGUST, 1)
                month == Calendar.JANUARY -> set(year - 1, Calendar.AUGUST, 1)
                else -> set(year, Calendar.FEBRUARY, 1)
            }
        }
        val start = semesterStart.timeInMillis
        val end = (semesterStart.clone() as Calendar).apply { add(Calendar.MONTH, 6) }.timeInMillis
        fun sameDay(ms: Long): Boolean {
            val date = Calendar.getInstance().apply { timeInMillis = ms }
            return date.get(Calendar.YEAR) == today.get(Calendar.YEAR) &&
                date.get(Calendar.DAY_OF_YEAR) == today.get(Calendar.DAY_OF_YEAR)
        }
        val items = (0 until rows.length()).mapNotNull { index ->
            val row = rows.optJSONObject(index) ?: return@mapNotNull null
            val status = row.optString("status", "")
            if (status == "done" || status == "submitted" ||
                (status.isEmpty() && row.optInt("u", 2) == 3)) return@mapNotNull null
            val due = row.optLong("d", -1L)
            if (due > 0 && (due < start || due >= end)) return@mapNotNull null
            val past = due > 0 && due <= now
            val minutes = (due - now) / 60000L
            val count = when {
                past -> "已逾期"
                due <= 0 -> if (root != null) "未设截止"
                    else row.optString("count", "未设截止").replace(Regex("\\d+秒"), "")
                minutes < 60 -> "不足1小时"
                minutes < 24 * 60 -> "剩余${minutes / 60}小时"
                else -> "剩余${minutes / (24 * 60)}天"
            }
            val deadline = if (due > 0) {
                val date = Calendar.getInstance().apply { timeInMillis = due }
                val pattern = when {
                    sameDay(due) -> "今天 HH:mm"
                    date.get(Calendar.YEAR) != today.get(Calendar.YEAR) -> "yyyy/M/d HH:mm"
                    else -> "M/d HH:mm"
                }
                SimpleDateFormat(pattern, Locale.CHINA).format(java.util.Date(due)) + " 截止"
            } else row.optString("due", "").ifEmpty { "截止时间未设" }
            Row(row.optString("id", ""), row.optString("title", "未命名作业"),
                row.optString("course", ""), due, count, deadline, past)
        }.sortedWith(compareBy<Row> {
            when {
                it.dueMs > now && sameDay(it.dueMs) -> 0
                it.overdue -> 1
                it.dueMs > 0 -> 2
                else -> 3
            }
        }.thenBy { if (it.overdue) -it.dueMs else if (it.dueMs > 0) it.dueMs else Long.MAX_VALUE })
        return Snapshot(items, root?.optLong("updatedAt", 0L) ?: 0L,
            items.count { it.overdue }, items.count { it.dueMs > now && sameDay(it.dueMs) },
            root?.has("items") == true || legacy != null)
    }
}
