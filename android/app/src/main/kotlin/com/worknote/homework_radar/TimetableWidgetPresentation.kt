package com.worknote.homework_radar

import org.json.JSONArray

internal object TimetableWidgetPresentation {
    data class Row(val name: String, val room: String, val start: String,
        val end: String, val badge: String, val focus: Boolean)
    data class Day(val rows: List<Row>, val hint: String)
    fun minutes(value: String): Int {
        val parts = value.split(":")
        val h = parts.getOrNull(0)?.trim()?.toIntOrNull() ?: return -1
        val m = parts.getOrNull(1)?.trim()?.toIntOrNull() ?: return -1
        return if (h in 0..23 && m in 0..59) h * 60 + m else -1
    }
    fun create(items: JSONArray, now: Int): Day {
        val rows = (0 until items.length()).mapNotNull { items.optJSONObject(it) }
        fun known(i: Int): Boolean {
            val s = minutes(rows[i].optString("s"))
            val e = minutes(rows[i].optString("e"))
            return s >= 0 && e > s
        }
        val current = rows.indices.firstOrNull { known(it) &&
            now >= minutes(rows[it].optString("s")) && now < minutes(rows[it].optString("e")) }
        val next = rows.indices.filter { known(it) && minutes(rows[it].optString("s")) > now }
            .minByOrNull { minutes(rows[it].optString("s")) }
        val focus = current ?: next
        val remaining = rows.indices.filter { it != focus }.sortedWith(compareBy<Int> {
            if (known(it) && minutes(rows[it].optString("e")) <= now) 1 else 0
        }.thenBy {
            minutes(rows[it].optString("s")).let { start -> if (start >= 0) start else Int.MAX_VALUE }
        })
        val order = listOfNotNull(focus) + remaining
        val output = order.map { i ->
            val o = rows[i]
            val badge = when {
                !known(i) -> "时间待确认"
                i == current -> "正在上课"
                i == next -> "下一节"
                minutes(o.optString("e")) <= now -> "已结束"
                else -> "待上课"
            }
            Row(o.optString("n", "未命名课程"), o.optString("r", ""),
                o.optString("s", ""), o.optString("e", ""), badge, i == focus)
        }
        return Day(output, when {
            current != null -> "正在上课"
            next != null -> "下一节"
            rows.isEmpty() -> "今天没有课"
            rows.indices.any { !known(it) } -> "时间待确认"
            else -> "今日课程已结束"
        })
    }
}
