package com.worknote.homework_radar

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import org.json.JSONArray
import org.json.JSONObject

/// 今日课表列表的数据工厂：读 tt_json 的 items，每次重绘按当前时间
/// 给每行标状态——0 已过（灰）、1 进行中（绿底）、2 未到（常规）。
/// 文字配色与作业组件（HomeworkWidgetService）同一套：
/// 深色壁纸 + 透明模式 → 浅色字；浅色壁纸沿用布局默认深字。
class TimetableWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        Factory(applicationContext, intent)

    class Factory(private val ctx: Context, private val intent: Intent) : RemoteViewsFactory {
        private var items: JSONArray = JSONArray()
        private var transparent = false
        private var narrow = false
        private var compact = false
        // 深色壁纸 + 透明模式 → 浅色字（在 onDataSetChanged 里算一次，避免逐行取色）
        private var wallDark = false
        private val appWidgetId: Int
            get() = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, -1)

        override fun onCreate() {}

        override fun onDataSetChanged() {
            // v2 按今天取（跨天自愈）；v1 旧格式取 items，兼容见 TimetableWidgetData
            val prefs =
                ctx.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            transparent = prefs.getBoolean("widget_transparent", false)
            // 文字明暗优先按选图底图亮度判（底材与壁纸明暗可能相反），
            // 没选图由 backdropDark 内部回退壁纸判定
            wallDark = transparent && WidgetGlass.backdropDark(ctx)
            items = TimetableWidgetData.read(prefs).items
            // 尺寸档位与作业组件同一套：窄卡（<190dp）藏教室，矮卡（<105dp）小字号
            if (appWidgetId != -1) {
                val opts: Bundle =
                    AppWidgetManager.getInstance(ctx).getAppWidgetOptions(appWidgetId)
                val minW = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
                var maxH = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT)
                if (maxH == 0) maxH = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
                narrow = minW in 1 until 190
                compact = maxH in 1 until 105
            }
        }

        override fun onDestroy() {}

        override fun getCount(): Int = items.length()

        override fun getViewAt(position: Int): RemoteViews {
            val rv = RemoteViews(ctx.packageName, R.layout.timetable_widget_row)
            try {
                val o: JSONObject = items.getJSONObject(position)
                val cal = java.util.Calendar.getInstance()
                val now = cal.get(java.util.Calendar.HOUR_OF_DAY) * 60 +
                    cal.get(java.util.Calendar.MINUTE)
                fun minutes(hhmm: String): Int {
                    val parts = hhmm.split(":")
                    val h = parts.getOrNull(0)?.trim()?.toIntOrNull() ?: return -1
                    val m = parts.getOrNull(1)?.trim()?.toIntOrNull() ?: return -1
                    return h * 60 + m
                }
                val s = minutes(o.optString("s", ""))
                val e = minutes(o.optString("e", ""))
                val status = when {
                    s >= 0 && e >= 0 && now in s..e -> 1 // 进行中
                    e in 0 until now -> 0                // 已过
                    else -> 2                            // 未到
                }
                val room = o.optString("r", "")
                rv.setTextViewText(R.id.tt_time, o.optString("s", ""))
                rv.setTextViewText(R.id.tt_name, o.optString("n", ""))
                // 窄卡藏教室（同作业组件窄卡藏日期）
                rv.setTextViewText(R.id.tt_room, if (narrow) "" else room)
                rv.setViewVisibility(R.id.tt_room, if (room.isEmpty() || narrow) View.GONE else View.VISIBLE)
                // 行底个性化与作业组件同一套：透明模式走半透玻璃药丸
                val rowBg =
                    if (transparent && status != 1) R.drawable.widget_row_bg_t
                    else R.drawable.widget_row_bg
                when (status) {
                    1 -> {
                        // 进行中：绿玻璃底 + 浅字（深壁纸浅薄荷字，浅壁纸实底粉彩绿+深绿字）
                        rv.setInt(
                            R.id.tt_row, "setBackgroundResource",
                            if (wallDark) R.drawable.widget_row_bg_now_t
                            else R.drawable.widget_row_bg_now
                        )
                        rv.setTextColor(
                            R.id.tt_time,
                            Color.parseColor(if (wallDark) "#D1FAE5" else "#0F6B54")
                        )
                        rv.setTextColor(
                            R.id.tt_name,
                            Color.parseColor(if (wallDark) "#FFFFFF" else "#0F6B54")
                        )
                        rv.setTextColor(
                            R.id.tt_room,
                            Color.parseColor(if (wallDark) "#A7F3D0" else "#4C8A75")
                        )
                    }
                    else -> {
                        // 已过/未到：配色语义同作业组件列表——
                        // 主文字（课名）深浅随壁纸（= w_item 的 #F4F6F8/#1F2937），
                        // 次要信息（教室）随壁纸（= w_due 的 #B3BCC9/#9CA3AF），
                        // 时间列是强调色（= w_count：未到用绿 #6EE7B7/#0F6B54，
                        // 已过降灰 #9CA3AF）。已过不把课名压暗，只灰时间列，
                        // 与作业组件「已完成行标题保持正常」的处理一致。
                        rv.setInt(R.id.tt_row, "setBackgroundResource", rowBg)
                        val passed = status == 0
                        rv.setTextColor(
                            R.id.tt_time,
                            Color.parseColor(
                                when {
                                    passed && wallDark -> "#9CA3AF"
                                    passed -> "#B0B7C3"
                                    wallDark -> "#6EE7B7"
                                    else -> "#0F6B54"
                                }
                            )
                        )
                        rv.setTextColor(
                            R.id.tt_name,
                            Color.parseColor(if (wallDark) "#F4F6F8" else "#1F2937")
                        )
                        rv.setTextColor(
                            R.id.tt_room,
                            Color.parseColor(
                                if (passed) (if (wallDark) "#6B7280" else "#C3C9D4")
                                else (if (wallDark) "#B3BCC9" else "#9CA3AF")
                            )
                        )
                    }
                }
                // 紧凑档小字号，一屏多塞几行（同作业组件）
                if (compact) {
                    rv.setTextViewTextSize(R.id.tt_time, TypedValue.COMPLEX_UNIT_SP, 10f)
                    rv.setTextViewTextSize(R.id.tt_name, TypedValue.COMPLEX_UNIT_SP, 11f)
                    rv.setTextViewTextSize(R.id.tt_room, TypedValue.COMPLEX_UNIT_SP, 9f)
                } else {
                    rv.setTextViewTextSize(R.id.tt_time, TypedValue.COMPLEX_UNIT_SP, 12f)
                    rv.setTextViewTextSize(R.id.tt_name, TypedValue.COMPLEX_UNIT_SP, 13f)
                    rv.setTextViewTextSize(R.id.tt_room, TypedValue.COMPLEX_UNIT_SP, 10f)
                }
                // 点条目打开应用：模板 PendingIntent 需要 fill-in intent 才会触发
                rv.setOnClickFillInIntent(R.id.tt_row, Intent())
            } catch (_: Exception) {
            }
            return rv
        }

        /** 系统默认裸 TextView 占位与玻璃行底割裂，给同布局的空行 */
        override fun getLoadingView(): RemoteViews =
            RemoteViews(ctx.packageName, R.layout.timetable_widget_row)

        override fun getViewTypeCount(): Int = 1

        /** 列表每次变更全量重读，假 stable id 会造成错锚点复用 */
        override fun getItemId(position: Int): Long = position.toLong()
        override fun hasStableIds(): Boolean = false
    }
}
