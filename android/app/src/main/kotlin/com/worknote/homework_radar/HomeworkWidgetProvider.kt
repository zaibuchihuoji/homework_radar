package com.worknote.homework_radar

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class HomeworkWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        WidgetConfiguration.observe(context)
        for (id in ids) WidgetRenderQueue.submit("homework:$id") { render(context, manager, id) }
    }
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager,
        id: Int, options: Bundle?) = onUpdate(context, manager, intArrayOf(id))

    private fun render(context: Context, manager: AppWidgetManager, id: Int) {
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val data = HomeworkWidgetData.parse(prefs.getString("homework_snapshot", null),
            prefs.getString("items_json", null))
        val size = WidgetDimensions.read(context, id)
        val layout = WidgetLayout.forSize(size.width, size.height, context.resources.configuration.fontScale)
        val style = StudyWidgetStyle(context, size)
        val template = when {
            layout.tiny -> R.layout.homework_widget_compact
            layout.narrow -> R.layout.homework_widget_narrow
            else -> R.layout.homework_widget
        }
        val views = RemoteViews(context.packageName, template)
        style.background(context, views, R.id.w_content, R.id.w_glass, size)
        if (layout.tiny) {
            val density = context.resources.displayMetrics.density
            val horizontal = (12 * density).toInt()
            val vertical = ((if (size.height < 100) 3 else 8) * density).toInt()
            views.setViewPadding(R.id.w_content, horizontal, vertical, horizontal, vertical)
        }
        style.badge(views, R.id.w_mark)
        val header = WidgetHeaderTypography.homework(context, size, style, data.items.size)
        header.apply(views, R.id.w_header, R.id.w_title, R.id.w_mark)
        views.setTextColor(R.id.w_title, style.ink)
        views.setTextColor(R.id.w_summary, style.secondary)
        views.setTextColor(R.id.w_empty, style.secondary)
        views.setTextColor(R.id.w_footer, style.secondary)
        views.setTextViewText(R.id.w_summary, style.label("今天待交 ${data.dueToday} 项 · 逾期 ${data.overdue} 项"))
        views.setViewVisibility(R.id.w_header, if (layout.showHeader) View.VISIBLE else View.GONE)
        views.setViewVisibility(R.id.w_summary, if (layout.showSummary) View.VISIBLE else View.GONE)
        views.setViewVisibility(R.id.w_footer, if (layout.showFooter) View.VISIBLE else View.GONE)
        val updated = if (data.updatedAt > 0) "本地快照 " + SimpleDateFormat("M/d HH:mm", Locale.CHINA)
            .format(Date(data.updatedAt)) else prefs.getString("updated", "") ?: ""
        views.setTextViewText(R.id.w_footer, style.label(if (updated.isEmpty()) "上下滑动查看更多" else updated))
        val empty = if (data.hasData) "暂无待办作业\n点此查看全部作业" else "先打开作业通\n添加或同步你的作业"
        // A 2x1 panel cannot fit a wrapped instruction below the empty title.
        // The same empty-view PendingIntent remains available at every size.
        val emptyText = if (layout.tiny) if (data.hasData) "暂无待办" else "打开作业通" else empty
        views.setTextViewText(R.id.w_empty, style.label(emptyText))
        if (data.items.isEmpty()) {
            val fit = WidgetRowTypography(context, size, layout, style, false, header.height).empty(emptyText)
            views.setTextViewTextSize(R.id.w_empty, android.util.TypedValue.COMPLEX_UNIT_PX, fit.pixels)
            views.setInt(R.id.w_empty, "setMaxLines", fit.lines)
        }
        views.setRemoteAdapter(R.id.w_list, Intent(context, HomeworkWidgetService::class.java)
            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
            .setData(Uri.parse("homework_radar://homework/$id")))
        views.setEmptyView(R.id.w_list, R.id.w_empty)
        views.setPendingIntentTemplate(R.id.w_list, WidgetLinks.template(context, id * 10 + 1))
        val open = WidgetLinks.open(context, id * 10 + 2, "homework")
        views.setOnClickPendingIntent(android.R.id.background, open)
        views.setOnClickPendingIntent(R.id.w_header, open)
        views.setOnClickPendingIntent(R.id.w_empty, open)
        manager.updateAppWidget(id, views)
        manager.notifyAppWidgetViewDataChanged(id, R.id.w_list)
    }
}
