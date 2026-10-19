package com.worknote.homework_radar

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import java.util.Calendar

class TimetableWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        WidgetConfiguration.observe(context)
        for (id in ids) WidgetRenderQueue.submit("timetable:$id") { render(context, manager, id) }
    }
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager,
        id: Int, options: Bundle?) = onUpdate(context, manager, intArrayOf(id))

    private fun render(context: Context, manager: AppWidgetManager, id: Int) {
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val today = TimetableWidgetData.read(prefs)
        val now = Calendar.getInstance()
        val day = TimetableWidgetPresentation.create(today.items,
            now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE))
        val size = WidgetDimensions.read(context, id)
        val layout = WidgetLayout.forSize(size.width, size.height, context.resources.configuration.fontScale)
        val style = StudyWidgetStyle(context, size)
        val template = when {
            layout.tiny -> R.layout.timetable_widget_compact
            layout.narrow -> R.layout.timetable_widget_narrow
            else -> R.layout.timetable_widget
        }
        val views = RemoteViews(context.packageName, template)
        style.background(context, views, R.id.tt_content, R.id.tt_glass, size)
        if (layout.tiny) {
            val density = context.resources.displayMetrics.density
            val horizontal = (12 * density).toInt()
            val vertical = ((if (size.height < 100) 3 else 8) * density).toInt()
            views.setViewPadding(R.id.tt_content, horizontal, vertical, horizontal, vertical)
        }
        style.badge(views, R.id.tt_mark)
        val header = WidgetHeaderTypography.timetable(context, size, style, layout, day.hint, today.week)
        header.apply(views, R.id.tt_header, R.id.tt_title, R.id.tt_mark)
        views.setTextColor(R.id.tt_title, style.ink)
        views.setTextColor(R.id.tt_summary, style.secondary)
        views.setTextColor(R.id.tt_empty, style.secondary)
        views.setTextColor(R.id.tt_footer, style.secondary)
        views.setTextViewText(R.id.tt_summary, style.label(today.date + " · " + day.hint))
        views.setViewVisibility(R.id.tt_header, if (layout.showHeader) View.VISIBLE else View.GONE)
        views.setViewVisibility(R.id.tt_summary, if (layout.showHeader && !layout.narrow) View.VISIBLE else View.GONE)
        views.setViewVisibility(R.id.tt_footer, if (layout.showFooter) View.VISIBLE else View.GONE)
        views.setTextViewText(R.id.tt_footer, style.label("今日 ${day.rows.size} 节 · 上下滑动查看"))
        val empty = when {
            !prefs.contains("tt_json") || (today.valid && !today.hasSchedule) -> "先添加课表\n点此导入或添加课程"
            !today.valid -> "课表暂不可用\n点此查看应用内课表"
            today.week == "未开学" -> "学期尚未开始\n点此查看课表"
            else -> "今天没有课\n留一点时间给自己"
        }
        val emptyText = if (layout.tiny) empty.substringBefore('\n') else empty
        views.setTextViewText(R.id.tt_empty, style.label(emptyText))
        if (day.rows.isEmpty()) {
            val fit = WidgetRowTypography(context, size, layout, style, true, header.height).empty(emptyText)
            views.setTextViewTextSize(R.id.tt_empty, android.util.TypedValue.COMPLEX_UNIT_PX, fit.pixels)
            views.setInt(R.id.tt_empty, "setMaxLines", fit.lines)
        }
        views.setRemoteAdapter(R.id.tt_list, Intent(context, TimetableWidgetService::class.java)
            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
            .setData(Uri.parse("homework_radar://timetable/$id")))
        views.setEmptyView(R.id.tt_list, R.id.tt_empty)
        views.setPendingIntentTemplate(R.id.tt_list, WidgetLinks.template(context, id * 10 + 1))
        val open = WidgetLinks.open(context, id * 10 + 2, "timetable")
        views.setOnClickPendingIntent(android.R.id.background, open)
        views.setOnClickPendingIntent(R.id.tt_header, open)
        views.setOnClickPendingIntent(R.id.tt_empty, open)
        manager.updateAppWidget(id, views)
        manager.notifyAppWidgetViewDataChanged(id, R.id.tt_list)
    }
}
