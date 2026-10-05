package com.worknote.homework_radar

import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

/**
 * 今日课表小组件的 tt_json 读取。
 *
 * v3 格式：{week:"第N周", start:开学周一epochMs, days:{"1".."7":[{s,e,n,r,w:[周次]},...]}}
 * —— 日期头、「今天取哪天」、周次标签与课程周次过滤都在每次重绘时按当前时间算：
 *    App 超过一周没打开，系统 30 分钟一次的重绘也能换到正确的一天/一周
 *    （v2 只自愈跨天，周次标签与单双周课程会一直停在推送时刻的那一周）。
 * v2 格式：{week:"第N周", days:{...}}（条目无 w）—— 跨天自愈，周次沿用快照。
 * v1 格式（升级后首次推送前）：{header:{date,week}, items:[...]} —— 原样兼容。
 */
internal object TimetableWidgetData {
    /** Calendar.DAY_OF_WEEK(1=周日..7=周六) → App 的 weekday(1=周一..7=周日) */
    private fun appWeekday(cal: java.util.Calendar): Int {
        val dow = cal.get(java.util.Calendar.DAY_OF_WEEK)
        return if (dow == java.util.Calendar.SUNDAY) 7 else dow - 1
    }

    fun read(prefs: SharedPreferences): Today {
        // 单个 Calendar 实例同时供星期与日期串使用：两次独立 getInstance 在
        // 跨午夜瞬间可能取自相邻两天，拼出自相矛盾的「X月Y日 周Z」
        val cal = java.util.Calendar.getInstance()
        val appDow = appWeekday(cal)
        val dateStr = run {
            val month = cal.get(java.util.Calendar.MONTH) + 1
            val day = cal.get(java.util.Calendar.DAY_OF_MONTH)
            "${month}月${day}日 周${"一二三四五六日"[appDow - 1]}"
        }
        val root = try {
            JSONObject(prefs.getString("tt_json", "{}") ?: "{}")
        } catch (_: Exception) {
            JSONObject()
        }
        val days = root.optJSONObject("days")
        if (days != null) {
            // 按当前日期重算周次（start 缺失 = 未校准 = 不过滤，全周课程照旧）
            var week = 0
            val startMs = root.optLong("start", 0L)
            if (startMs > 0L) {
                val dayStart = cal.clone() as java.util.Calendar
                dayStart.set(java.util.Calendar.HOUR_OF_DAY, 0)
                dayStart.set(java.util.Calendar.MINUTE, 0)
                dayStart.set(java.util.Calendar.SECOND, 0)
                dayStart.set(java.util.Calendar.MILLISECOND, 0)
                val daysFromStart =
                    (dayStart.timeInMillis - startMs) / (24L * 60 * 60 * 1000)
                week = (daysFromStart / 7).toInt() + 1
            }
            val weekLabel = when {
                startMs <= 0L -> root.optString("week", "")
                week < 1 -> "未开学"
                else -> "第${week}周"
            }
            return Today(dateStr, weekLabel, filterByWeek(days.optJSONArray("$appDow") ?: JSONArray(), week))
        }
        val header = root.optJSONObject("header")
        return Today(
            header?.optString("date", "") ?: "",
            header?.optString("week", "") ?: "",
            root.optJSONArray("items") ?: JSONArray(),
        )
    }

    /** v3：按重算的周次过滤课程；week<=0（未开学/未校准）不过滤 */
    private fun filterByWeek(items: JSONArray, week: Int): JSONArray {
        if (week < 1) return items
        val out = JSONArray()
        for (i in 0 until items.length()) {
            val o = items.optJSONObject(i) ?: continue
            val weeks = o.optJSONArray("w") ?: continue // v2 条目无 w：不过滤
            for (k in 0 until weeks.length()) {
                if (weeks.optInt(k, -1) == week) {
                    out.put(o)
                    break
                }
            }
        }
        return out
    }

    class Today(val date: String, val week: String, val items: JSONArray)
}
