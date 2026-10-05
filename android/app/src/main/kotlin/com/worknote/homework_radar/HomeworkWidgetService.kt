package com.worknote.homework_radar

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.util.TypedValue
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import org.json.JSONArray

/// 小组件滚动列表的数据工厂：读取 Dart 侧写入的 items_json，
/// 待办在前（按截止升序）、无截止随后、已提交/完成的灰色补位。
/// 窄卡（宽 <190dp）隐藏右侧日期；矮卡（高 <105dp）用紧凑小字号。
/// 倒计时文案与紧急度颜色按「现在」实时重算（条目带 due 里程碑 d 时）：
/// 此前是同步时刻的字符串快照，作业截止后组件仍显示「3天」红色倒计时。
class HomeworkWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        Factory(applicationContext, intent)

    class Factory(private val ctx: Context, private val intent: Intent) : RemoteViewsFactory {
        private var items: JSONArray = JSONArray()
        private var narrow = false
        private var compact = false
        private var transparent = false
        // 深色壁纸 + 透明模式 → 浅色字（在 onDataSetChanged 里算一次，避免逐行取色）
        private var wallDark = false
        private val appWidgetId: Int
            get() = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, -1)

        override fun onCreate() {}

        override fun onDataSetChanged() {
            val prefs =
                ctx.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            transparent = prefs.getBoolean("widget_transparent", false)
            // 文字明暗优先按选图底图亮度判（底材与壁纸明暗可能相反），
            // 没选图由 backdropDark 内部回退壁纸判定
            wallDark = transparent && WidgetGlass.backdropDark(ctx)
            items = try {
                JSONArray(prefs.getString("items_json", "[]"))
            } catch (_: Exception) {
                JSONArray()
            }
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

        /** 与 Dart 侧 shortCountdown 同口径：48h 内倒计时、更远按天 */
        private fun countdown(dueMs: Long, nowMs: Long): String {
            val diffMin = (dueMs - nowMs) / 60000L
            // 截止已过、下次同步还没跑的窗口里 diffMin 为负：显示「已截止」
            // 而不是「-12分钟」红字（横幅有已截止分支，列表行同样要有）
            if (diffMin < 0) return "已截止"
            if (diffMin < 60) return "${diffMin}分钟"
            if (diffMin < 24 * 60) {
                val h = diffMin / 60
                val m = diffMin % 60
                val s = (dueMs - nowMs) / 1000 % 60
                return "${h}小时${m}分${s}秒"
            }
            if (diffMin < 48 * 60) return "${diffMin / 60}小时"
            return "${diffMin / (24 * 60)}天"
        }

        /** 0=一天内(红) 1=三天内(琥珀) 2=更远(绿) */
        private fun urgency(dueMs: Long, nowMs: Long): Int {
            val hours = (dueMs - nowMs) / 3600000.0
            return when {
                hours <= 24 -> 0
                hours <= 72 -> 1
                else -> 2
            }
        }

        override fun getViewAt(position: Int): RemoteViews {
            val rv = RemoteViews(ctx.packageName, R.layout.widget_item)
            // 个性化：透明模式下行走半透明白，压在壁纸上仍可读
            rv.setInt(
                R.id.hw_row, "setBackgroundResource",
                if (transparent) R.drawable.widget_row_bg_t else R.drawable.widget_row_bg
            )
            try {
                val o = items.getJSONObject(position)
                val dueMs = if (o.has("d")) o.optLong("d", -1L) else -1L
                val nowMs = System.currentTimeMillis()
                val u = if (dueMs > 0) urgency(dueMs, nowMs) else o.optInt("u", 2)
                val count = if (dueMs > 0) countdown(dueMs, nowMs) else o.optString("count", "")
                val color = when (u) {
                    0 -> if (wallDark) Color.parseColor("#FCA5A5") else Color.parseColor("#DC2626")
                    1 -> if (wallDark) Color.parseColor("#FCD34D") else Color.parseColor("#D97706")
                    3 -> Color.parseColor("#9CA3AF")
                    else -> if (wallDark) Color.parseColor("#6EE7B7") else Color.parseColor("#0F6B54")
                }
                rv.setTextViewText(R.id.w_count, count)
                rv.setTextViewText(R.id.w_item, o.optString("title", ""))
                rv.setTextViewText(R.id.w_due, if (narrow) "" else o.optString("due", ""))
                rv.setTextColor(R.id.w_count, color)
                // 深色壁纸换浅色字；浅色壁纸沿用布局默认深字
                rv.setTextColor(
                    R.id.w_item,
                    Color.parseColor(if (wallDark) "#F4F6F8" else "#1F2937")
                )
                rv.setTextColor(
                    R.id.w_due,
                    Color.parseColor(if (wallDark) "#B3BCC9" else "#9CA3AF")
                )
                // 紧凑档小字号，一屏多塞几行
                if (compact) {
                    rv.setTextViewTextSize(R.id.w_count, TypedValue.COMPLEX_UNIT_SP, 10f)
                    rv.setTextViewTextSize(R.id.w_item, TypedValue.COMPLEX_UNIT_SP, 11f)
                    rv.setTextViewTextSize(R.id.w_due, TypedValue.COMPLEX_UNIT_SP, 9f)
                } else {
                    rv.setTextViewTextSize(R.id.w_count, TypedValue.COMPLEX_UNIT_SP, 12f)
                    rv.setTextViewTextSize(R.id.w_item, TypedValue.COMPLEX_UNIT_SP, 13f)
                    rv.setTextViewTextSize(R.id.w_due, TypedValue.COMPLEX_UNIT_SP, 10f)
                }
                // 挂 fill-in intent：模板 PendingIntent 只有点行时才有响应，
                // 没有它「点条目打开应用」的注释永远不成立
                rv.setOnClickFillInIntent(R.id.hw_row, Intent())
            } catch (_: Exception) {
            }
            return rv
        }

        /** 系统用默认裸 TextView 占位会与玻璃行底割裂，给同布局的空行 */
        override fun getLoadingView(): RemoteViews =
            RemoteViews(ctx.packageName, R.layout.widget_item)

        override fun getViewTypeCount(): Int = 1

        /** 列表每次变更全量重读，位置即 id；假 stable id 会让宿主以错锚点复用行 */
        override fun getItemId(position: Int): Long = position.toLong()
        override fun hasStableIds(): Boolean = false
    }
}
