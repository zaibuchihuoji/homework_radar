package com.worknote.homework_radar

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService

class HomeworkWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory = Factory(applicationContext, intent)
    class Factory(private val ctx: Context, private val intent: Intent) : RemoteViewsFactory {
        private var data = HomeworkWidgetData.parse(null, null)
        private var layout = WidgetLayout.forSize(260, 160, 1f)
        private var style = StudyWidgetStyle(ctx)
        private var typography = WidgetRowTypography(ctx, WidgetDimensions(260,160), layout, style, false)
        override fun onCreate() { WidgetConfiguration.observe(ctx) }
        override fun onDestroy() {}
        override fun onDataSetChanged() {
            val prefs = ctx.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            data = HomeworkWidgetData.parse(prefs.getString("homework_snapshot", null), prefs.getString("items_json", null))
            val size = WidgetDimensions.read(ctx, intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, -1))
            layout = WidgetLayout.forSize(size.width, size.height, ctx.resources.configuration.fontScale)
            style = StudyWidgetStyle(ctx, size)
            typography = WidgetRowTypography(ctx, size, layout, style, false,
                WidgetHeaderTypography.homework(ctx, size, style, data.items.size).height)
        }
        override fun getCount() = data.items.size
        override fun getViewAt(position: Int): RemoteViews {
            val rv = RemoteViews(ctx.packageName, R.layout.widget_item)
            val row = data.items.getOrNull(position) ?: return rv
            val showBadge = !layout.narrow && !layout.tiny
            val colors = if (typography.compact) style.textColors else style.rowColors
            val deadline = if (layout.narrow || layout.tiny) WidgetRowBudget.deadline(row.deadline) else row.deadline
            val fit = typography.row(row.title, deadline, row.course,
                if (showBadge) style.theme.count(row.count) else "")
            rv.setViewPadding(R.id.hw_row, fit.padding, fit.padding, fit.padding, fit.padding)
            rv.setInt(R.id.hw_row, "setMinimumHeight", typography.minimumHeight)
            style.badge(rv, R.id.w_count)
            if (typography.compact) rv.setInt(R.id.hw_row, "setBackgroundColor", android.graphics.Color.TRANSPARENT)
            else rv.setInt(R.id.hw_row, "setBackgroundResource", style.rowBackground)
            rv.setTextViewText(R.id.w_item, style.label(row.title, foreground = colors.ink))
            rv.setTextColor(R.id.w_item, colors.ink)
            rv.setInt(R.id.w_item, "setMaxLines", fit.title.lines)
            rv.setTextViewTextSize(R.id.w_item, TypedValue.COMPLEX_UNIT_PX, fit.title.pixels)
            rv.setTextViewText(R.id.w_count, style.label(style.theme.count(row.count), ambient = false))
            rv.setViewVisibility(R.id.w_count, if (showBadge) View.VISIBLE else View.GONE)
            rv.setTextColor(R.id.w_count, style.accentInk)
            val dueColor = if (row.overdue) colors.danger else colors.secondary
            rv.setTextViewText(R.id.w_due, style.label(deadline, foreground = dueColor))
            rv.setTextViewTextSize(R.id.w_due, TypedValue.COMPLEX_UNIT_PX, fit.detail.pixels)
            rv.setInt(R.id.w_due, "setMaxLines", fit.detail.lines)
            rv.setTextColor(R.id.w_due, dueColor)
            rv.setViewVisibility(R.id.w_due, View.VISIBLE)
            rv.setViewVisibility(R.id.w_meta, View.GONE)
            rv.setTextViewText(R.id.w_course, style.label(row.course, foreground = colors.secondary))
            rv.setViewVisibility(R.id.w_course, if (fit.extra == null) View.GONE else View.VISIBLE)
            fit.extra?.let {
                rv.setTextViewTextSize(R.id.w_course, TypedValue.COMPLEX_UNIT_PX, it.pixels)
                rv.setInt(R.id.w_course, "setMaxLines", it.lines)
            }
            rv.setTextColor(R.id.w_course, colors.secondary)
            rv.setContentDescription(R.id.hw_row, listOf(row.title, row.course, row.count, row.deadline).joinToString("，"))
            rv.setOnClickFillInIntent(R.id.hw_row, WidgetLinks.row("homework", row.id))
            return rv
        }
        override fun getLoadingView() = RemoteViews(ctx.packageName, R.layout.widget_item)
        override fun getViewTypeCount() = 1
        override fun getItemId(position: Int) = position.toLong()
        override fun hasStableIds() = false
    }
}
