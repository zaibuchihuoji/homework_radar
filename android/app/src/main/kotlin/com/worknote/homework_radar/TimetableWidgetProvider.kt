package com.worknote.homework_radar

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/// 今日课表小组件：头部（日期+周次）+ 可滚动课程列表。
/// Dart 侧写入整周数据（tt_json，见 TimetableWidgetData），
/// 头部日期、「今天取哪天」与周次标签由每次重绘按当前时间判定——
/// 系统 30 分钟重绘一次，跨天/跨周时不用打开 App 也能换到正确的一天/一周。
class TimetableWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        for (id in appWidgetIds) render(context, manager, id)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context, manager: AppWidgetManager,
        appWidgetId: Int, newOptions: Bundle?
    ) {
        render(context, manager, appWidgetId)
    }

    companion object {
        /// 渲染移出主线程（同 HomeworkWidgetProvider），按 widgetId 合并请求
        private val EXECUTOR = Executors.newSingleThreadExecutor()
        private val queued = ConcurrentHashMap<Int, Boolean>()

        fun render(context: Context, manager: AppWidgetManager, appWidgetId: Int) {
            if (queued.putIfAbsent(appWidgetId, true) != null) return
            EXECUTOR.execute {
                queued.remove(appWidgetId)
                try {
                    renderNow(context, manager, appWidgetId)
                } catch (_: Exception) {
                }
            }
        }

        fun renderNow(context: Context, manager: AppWidgetManager, appWidgetId: Int) {
            val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            val transparent = prefs.getBoolean("widget_transparent", false)
            // v3 按「今天/本周」取列表并自拼日期头与周次（跨天跨周自愈）；
            // v2/v1 旧格式原样兼容
            val today = TimetableWidgetData.read(prefs)
            val date = today.date
            val week = today.week

            val views = RemoteViews(context.packageName, R.layout.timetable_widget).apply {
                // 个性化：透明模式 = 液态玻璃。
                // 默认（未选图）：纯半透玻璃 drawable（深/浅随壁纸明暗），真实壁纸透出来；
                // 选图模式：用户素材加工成的玻璃底位图 + rim 描边；
                // 白卡模式维持原样
                if (!transparent) {
                    setViewVisibility(R.id.tt_glass, View.GONE)
                    setInt(R.id.tt_content, "setBackgroundResource", R.drawable.widget_bg)
                } else {
                    val wallDark = WidgetGlass.wallpaperDark(context)
                    val opts = manager.getAppWidgetOptions(appWidgetId)
                    val dm = context.resources.displayMetrics
                    var minW = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
                    var maxH = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT)
                    if (maxH == 0) maxH = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
                    // 刚放置时 options 可能还没到位，退回整屏尺寸先渲染一版
                    if (minW < 16) minW = (dm.widthPixels / dm.density).toInt()
                    if (maxH < 16) maxH = (dm.heightPixels / dm.density).toInt()
                    // 横屏时 MIN_WIDTH/MAX_HEIGHT 语义互换，按方向还原宽高
                    val landscape =
                        context.resources.configuration.orientation ==
                            android.content.res.Configuration.ORIENTATION_LANDSCAPE
                    val wDp = if (landscape) maxOf(minW, maxH) else minW
                    val hDp = if (landscape) minOf(minW, maxH) else maxH
                    val glass = GlassWallpaperRenderer.glassBackdrop(
                        context, (wDp * dm.density).toInt(), (hDp * dm.density).toInt()
                    )
                    if (glass == null) {
                        // 无素材图：半透玻璃面板，壁纸真实透出（永不穿帮）
                        setViewVisibility(R.id.tt_glass, View.GONE)
                        setInt(
                            R.id.tt_content, "setBackgroundResource",
                            if (wallDark) R.drawable.widget_glass_dark else R.drawable.widget_glass_light
                        )
                    } else {
                        setViewVisibility(R.id.tt_glass, View.VISIBLE)
                        setImageViewBitmap(R.id.tt_glass, glass)
                        setInt(R.id.tt_content, "setBackgroundResource", R.drawable.widget_bg_rim)
                    }
                    // 头部文字深浅与玻璃底判定同源：选图时按素材亮度，
                    // 未选图 backdropDark 内部回退壁纸判定
                    val textDark = WidgetGlass.backdropDark(context)
                    setTextColor(
                        R.id.tt_date,
                        Color.parseColor(if (textDark) "#6EE7B7" else "#0F6B54")
                    )
                    setTextColor(
                        R.id.tt_week,
                        Color.parseColor(if (textDark) "#B3BCC9" else "#9CA3AF")
                    )
                    setInt(R.id.tt_header, "setBackgroundResource", android.R.color.transparent)
                }
                if (!transparent) {
                    // 白卡模式：标题品牌绿、副标题灰（布局默认）
                    setTextColor(R.id.tt_date, Color.parseColor("#0F6B54"))
                    setTextColor(R.id.tt_week, Color.parseColor("#9CA3AF"))
                }
                setTextViewText(R.id.tt_date, date.ifEmpty { "课表" })
                setTextViewText(R.id.tt_week, week)
                setRemoteAdapter(
                    R.id.tt_list,
                    Intent(context, TimetableWidgetService::class.java)
                        .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                        // 多实例工厂按 Intent 缓存：不带唯一 data 会共用
                        // 第一个实例的尺寸档
                        .setData(Uri.parse("homework_radar://timetable/$appWidgetId"))
                )
                setEmptyView(R.id.tt_list, R.id.tt_empty)
                val intent = Intent(context, MainActivity::class.java)
                val pi = PendingIntent.getActivity(
                    context, 1, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                setPendingIntentTemplate(R.id.tt_list, pi)
                setOnClickPendingIntent(android.R.id.background, pi)
            }
            manager.updateAppWidget(appWidgetId, views)
            // 触发列表工厂重新读数据（重算进行中/已过状态）
            manager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.tt_list)
        }
    }
}
