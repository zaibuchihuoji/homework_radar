package com.worknote.homework_radar

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/// 桌面小组件：内容随尺寸自适应，列表区可滚动。
/// Dart 侧写入：
///   items_json — 最多 20 条（待办在前按截止升序；无截止随后；
///                不足时已提交/完成的灰色补位。count/title/due/urgency：
///                0红 1琥珀 2绿 3灰；待办条目另带 due 里程碑 d 供原生重算）
///   stats      — banner（text/u：今天0/明天1/最近2；d=最近截止里程碑，
///                重绘时按当前时间重算相对文案）+ courses（前4门待办分布）
///
/// 结构：玻璃底 + 头部 + 横幅 + 可滚动列表 + 课程分布。
///   固定元素按高度依次登场（保证列表至少一行）：
///   <80dp → 纯列表；≥80dp +头部；≥130dp +横幅；≥170dp +课程分布。
///   窄卡（宽<190dp）藏副标题/时间/日期。最小可缩到 2×1。
class HomeworkWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        for (id in appWidgetIds) render(context, manager, id)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context, manager: AppWidgetManager,
        appWidgetId: Int, newOptions: Bundle?
    ) {
        // 拖拽缩放时实时换档
        render(context, manager, appWidgetId)
    }

    companion object {
        /// 渲染移出主线程：玻璃底管线含磁盘解码 + 逐像素加工，跑在广播
        /// 主线程上会拖垮 Flutter/桌面帧率。按 widgetId 合并请求，拖拽缩放
        /// 连续回调时同一组件只保留一次排队。
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
            val views = RemoteViews(context.packageName, R.layout.homework_widget).apply {
                // 个性化：透明模式 = 液态玻璃（壁纸折射位图 + rim 描边）；
                // 拿不到壁纸（动态壁纸等）回退渐变玻璃；白卡模式维持原样
                applyGlass(context, this, prefs, manager, appWidgetId, transparent)
                setTextViewText(R.id.w_updated, prefs.getString("updated", ""))
                // 透明模式的文字明暗判定：底材可能是用户选图（亮度与壁纸无关），
                // 优先按底图亮度判，没选图回退壁纸判定；boolean 短路保证白卡
                // 模式不做任何判定
                val wallDark = transparent && WidgetGlass.backdropDark(context)
                if (wallDark) {
                    // 深色底上布局默认的深绿标题/灰副标题不可读，换浅色
                    setTextColor(R.id.w_title, Color.parseColor("#6EE7B7"))
                    setTextColor(R.id.w_subtitle, Color.parseColor("#B3BCC9"))
                    setTextColor(R.id.w_updated, Color.parseColor("#B3BCC9"))
                }

                // ---- 横幅 + 课程分布数据 ----
                var bannerText = ""
                var bannerU = 2
                var bannerDueMs = -1L
                var courseChars: List<String> = emptyList()
                var courseNums: List<Int> = emptyList()
                try {
                    val stats = JSONObject(prefs.getString("stats", "{}"))
                    stats.optJSONObject("banner")?.let {
                        bannerText = it.optString("text", "")
                        bannerU = it.optInt("u", 2)
                        // 截止里程碑：横幅文本是同步瞬间拼的快照，组件 30 分钟
                        // 重绘只回放文本的话，截止后仍显示「未来X小时」
                        if (it.has("d")) bannerDueMs = it.optLong("d", -1L)
                    }
                    val cArr = stats.optJSONArray("courses")
                    if (cArr != null) {
                        for (i in 0 until minOf(cArr.length(), 4)) {
                            courseChars += cArr.getJSONObject(i).optString("c", "")
                            courseNums += cArr.getJSONObject(i).optInt("n", 0)
                        }
                    }
                } catch (_: Exception) {}

                // ---- 有数据时统计行数（决定空态/横幅） ----
                var rowCount = try {
                    JSONArray(prefs.getString("items_json", "[]")).length()
                } catch (_: Exception) {
                    0
                }

                // ---- 按当前尺寸决定可见部件 ----
                // 注意：竖屏下组件的真实高度在 MAX_HEIGHT 里，MIN_HEIGHT 是横屏时的矮高度
                val opts = manager.getAppWidgetOptions(appWidgetId)
                var minW = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
                var maxH = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT)
                if (maxH == 0) maxH = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
                if (minW == 0) minW = Int.MAX_VALUE
                if (maxH == 0) maxH = Int.MAX_VALUE
                val narrow = minW < 190
                // 固定元素（头部30+横幅40+课程25+边距24 ≈ 120dp）按高度依次登场，
                // 保证列表任何时候都至少有一行的空间
                val showHeader = maxH >= 80
                val showBanner = maxH >= 130 && rowCount > 0 && bannerText.isNotEmpty()
                val showCourses = maxH >= 170 && rowCount > 0 && courseChars.isNotEmpty()

                setViewVisibility(R.id.w_header, if (showHeader) View.VISIBLE else View.GONE)
                // 窄卡或小卡：副标题和更新时间都挤不下，藏掉只留标题
                val hideHeaderMeta = narrow || maxH < 130
                setViewVisibility(R.id.w_subtitle, if (showHeader && !hideHeaderMeta) View.VISIBLE else View.GONE)
                setViewVisibility(R.id.w_updated, if (showHeader && !hideHeaderMeta) View.VISIBLE else View.GONE)
                setViewVisibility(
                    R.id.w_banner,
                    if (showBanner) View.VISIBLE else View.GONE
                )
                if (rowCount > 0 && bannerText.isNotEmpty()) {
                    // 横幅文字按当前时间重算：已截止的不能继续显示「未来X小时」；
                    // 无里程碑 d（旧版本数据）回退快照文本
                    setTextViewText(R.id.w_bannertext, bannerTextNow(bannerText, bannerDueMs))
                    // 透明模式用半透玻璃药丸，和玻璃面板一个语言；白卡模式维持实底。
                    // 深底（深壁纸/深色选图）换深玻璃变体 + 浅字：半透浅玻璃变体
                    // 上的深字（#B91C1C 等）对比度不够
                    setInt(
                        R.id.w_banner, "setBackgroundResource",
                        when (bannerU) {
                            0 -> when {
                                wallDark -> R.drawable.widget_banner_red_dark_t
                                transparent -> R.drawable.widget_banner_red_t
                                else -> R.drawable.widget_banner_red
                            }
                            1 -> when {
                                wallDark -> R.drawable.widget_banner_amber_dark_t
                                transparent -> R.drawable.widget_banner_amber_t
                                else -> R.drawable.widget_banner_amber
                            }
                            else -> when {
                                wallDark -> R.drawable.widget_banner_green_dark_t
                                transparent -> R.drawable.widget_banner_green_t
                                else -> R.drawable.widget_banner_green
                            }
                        }
                    )
                    setTextColor(
                        R.id.w_bannertext,
                        when (bannerU) {
                            0 -> if (wallDark) Color.parseColor("#FCA5A5") else Color.parseColor("#B91C1C")
                            1 -> if (wallDark) Color.parseColor("#FDE68A") else Color.parseColor("#B45309")
                            else -> if (wallDark) Color.parseColor("#D1FAE5") else Color.parseColor("#0F6B54")
                        }
                    )
                }

                // ---- 课程待办分布（页脚） ----
                setViewVisibility(R.id.w_courses, if (showCourses) View.VISIBLE else View.GONE)
                if (showCourses) {
                    for (i in 0 until 4) {
                        val tv = courseId(i)
                        if (i < courseChars.size && courseNums[i] > 0) {
                            setViewVisibility(tv, View.VISIBLE)
                            // 深底换深玻璃药丸 + 浅字（同横幅），浅底维持实底深字
                            setInt(
                                tv, "setBackgroundResource",
                                when {
                                    wallDark -> R.drawable.widget_chip_bg_dark_t
                                    transparent -> R.drawable.widget_chip_bg_t
                                    else -> R.drawable.widget_chip_bg
                                }
                            )
                            if (wallDark) setTextColor(tv, Color.parseColor("#D1FAE5"))
                            setTextViewText(tv, "${courseChars[i]} ${courseNums[i]} 件")
                        } else {
                            // 没有数据的标签位整个藏掉，避免出现空药丸
                            setViewVisibility(tv, View.GONE)
                            setTextViewText(tv, "")
                        }
                    }
                } else {
                    // 小卡不显示课程条：显式清空并藏起，杜绝残留空药丸
                    for (i in 0 until 4) {
                        setTextViewText(courseId(i), "")
                        setViewVisibility(courseId(i), View.GONE)
                    }
                }

                // ---- 滚动列表：挂适配器，点条目打开应用 ----
                setRemoteAdapter(
                    R.id.w_list,
                    Intent(context, HomeworkWidgetService::class.java)
                        .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                        // RemoteViewsService 按 Intent（不含 extras）缓存工厂，
                        // 不带唯一 data 的话多实例会共享第一个实例的尺寸档
                        .setData(Uri.parse("homework_radar://homework/$appWidgetId"))
                )
                setEmptyView(R.id.w_list, R.id.w_empty)
                val intent = Intent(context, MainActivity::class.java)
                val pi = PendingIntent.getActivity(
                    context, 0, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                setPendingIntentTemplate(R.id.w_list, pi)
                // 根布局点击也打开应用（列表外区域）
                setOnClickPendingIntent(android.R.id.background, pi)
            }
            manager.updateAppWidget(appWidgetId, views)
            // 触发列表工厂重新读数据
            manager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.w_list)
        }

        /** 玻璃底：透明模式 = 液态玻璃；白卡模式隐藏。 */
        private fun applyGlass(
            context: Context, views: RemoteViews, prefs: SharedPreferences,
            manager: AppWidgetManager, appWidgetId: Int, transparent: Boolean
        ) {
            if (!transparent) {
                views.setViewVisibility(R.id.w_glass, View.GONE)
                views.setInt(R.id.w_content, "setBackgroundResource", R.drawable.widget_bg)
                return
            }
            val wallDark = WidgetGlass.wallpaperDark(context)
            val opts = manager.getAppWidgetOptions(appWidgetId)
            val dm = context.resources.displayMetrics
            var minW = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
            var maxH = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT)
            if (maxH == 0) maxH = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
            // 刚放置时 options 可能还没到位，退回整屏尺寸先渲染一版
            if (minW < 16) minW = (dm.widthPixels / dm.density).toInt()
            if (maxH < 16) maxH = (dm.heightPixels / dm.density).toInt()
            // 横屏时 MIN_WIDTH/MAX_HEIGHT 语义互换（MIN_WIDTH 变矮边），
            // 按方向还原宽高，否则玻璃位图按颠倒的尺寸渲染
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
                views.setViewVisibility(R.id.w_glass, View.GONE)
                views.setInt(
                    R.id.w_content, "setBackgroundResource",
                    if (wallDark) R.drawable.widget_glass_dark else R.drawable.widget_glass_light
                )
                return
            }
            views.setViewVisibility(R.id.w_glass, View.VISIBLE)
            views.setImageViewBitmap(R.id.w_glass, glass)
            views.setInt(R.id.w_content, "setBackgroundResource", R.drawable.widget_bg_rim)
        }

        /**
         * 横幅相对文案按当前时间重算。快照文本是同步瞬间拼的，截止后继续
         * 显示「未来X小时」会误导；口径与 HomeworkWidgetService 的行级倒计时
         * （countdown）一致：分钟 / 小时分秒 / 小时 / 天。
         */
        private fun bannerTextNow(snapshot: String, dueMs: Long): String {
            if (dueMs <= 0) return snapshot // 无里程碑 d（旧数据）→ 回退快照
            val nowMs = System.currentTimeMillis()
            // 标题固定在「 · 」之后（前缀段「今天截止 N 件」等不含分隔符，
            // 题目自身含「 · 」也不受影响）
            val title = snapshot.substringAfter(" · ", "")
            if (dueMs <= nowMs) {
                // 已截止：换经过时长，别再显示误导性的未来倒计时
                val min = (nowMs - dueMs) / 60000L
                val elapsed = if (min < 60) "${min}分钟" else "${min / 60}小时"
                return if (title.isEmpty()) "已截止$elapsed" else "已截止$elapsed · $title"
            }
            if (!snapshot.startsWith("最近 ")) return snapshot // 「今天/明天截止」未过期仍成立，沿用
            // 未来且是相对倒计时格式：按现在重算「最近X」
            val diffMin = (dueMs - nowMs) / 60000L
            val cd = when {
                diffMin < 60 -> "${diffMin}分钟"
                diffMin < 24 * 60 -> {
                    val h = diffMin / 60
                    val m = diffMin % 60
                    val s = (dueMs - nowMs) / 1000 % 60
                    "${h}小时${m}分${s}秒"
                }
                diffMin < 48 * 60 -> "${diffMin / 60}小时"
                else -> "${diffMin / (24 * 60)}天"
            }
            return if (title.isEmpty()) "最近 $cd" else "最近 $cd · $title"
        }

        private fun courseId(i: Int) =
            listOf(R.id.w_cc0, R.id.w_cc1, R.id.w_cc2, R.id.w_cc3)[i]
    }
}
