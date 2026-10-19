package com.worknote.homework_radar

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import org.json.JSONArray
import java.util.Calendar

class TimetableWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory = Factory(applicationContext, intent)
    class Factory(private val ctx: Context, private val intent: Intent) : RemoteViewsFactory {
        private var day = TimetableWidgetPresentation.create(JSONArray(), 0)
        private var layout = WidgetLayout.forSize(260, 160, 1f)
        private var style = StudyWidgetStyle(ctx)
        private var typography = WidgetRowTypography(ctx, WidgetDimensions(260,160), layout, style, true)
        override fun onCreate() { WidgetConfiguration.observe(ctx) }
        override fun onDestroy() {}
        override fun onDataSetChanged() {
            val prefs = ctx.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            val today = TimetableWidgetData.read(prefs)
            val now = Calendar.getInstance()
            day = TimetableWidgetPresentation.create(today.items,
                now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE))
            val size = WidgetDimensions.read(ctx, intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, -1))
            layout = WidgetLayout.forSize(size.width, size.height, ctx.resources.configuration.fontScale)
            style = StudyWidgetStyle(ctx, size)
            typography = WidgetRowTypography(ctx, size, layout, style, true,
                WidgetHeaderTypography.timetable(ctx, size, style, layout, day.hint, today.week).height)
        }
        override fun getCount() = day.rows.size
        override fun getViewAt(position: Int): RemoteViews {
            val rv = RemoteViews(ctx.packageName, R.layout.timetable_widget_row)
            val row = day.rows.getOrNull(position) ?: return rv
            val time = if (row.badge == "时间待确认") "时间待确认" else "${row.start} – ${row.end}"
            val room = row.room.ifEmpty { "教室待确认" }
            val titleSp = if (row.focus) 15f else 14f
            val fit = typography.row(row.name, time, room, if (layout.narrow) "" else row.badge, titleSp)
            rv.setViewPadding(R.id.tt_row, fit.padding, fit.padding, fit.padding, fit.padding)
            rv.setInt(R.id.tt_row, "setBackgroundResource", if (row.focus) style.focusBackground else style.rowBackground)
            val ink = if (row.focus) style.focusInk else style.rowColors.ink
            val secondary = if (row.focus) style.focusInk else style.rowColors.secondary
            rv.setTextViewText(R.id.tt_name, style.label(row.name, ambient = !row.focus, foreground = ink))
            rv.setInt(R.id.tt_name, "setMaxLines", fit.title.lines)
            rv.setTextColor(R.id.tt_name, ink)
            rv.setTextViewTextSize(R.id.tt_name, TypedValue.COMPLEX_UNIT_PX, fit.title.pixels)
            rv.setTextViewText(R.id.tt_status, style.label(row.badge, ambient = !row.focus, foreground = secondary))
            rv.setViewVisibility(R.id.tt_status, if (layout.narrow) View.GONE else View.VISIBLE)
            rv.setTextColor(R.id.tt_status, secondary)
            rv.setTextViewText(R.id.tt_time, style.label(time, ambient = !row.focus, foreground = secondary))
            rv.setTextViewTextSize(R.id.tt_time, TypedValue.COMPLEX_UNIT_PX, fit.detail.pixels)
            rv.setInt(R.id.tt_time, "setMaxLines", fit.detail.lines)
            rv.setTextColor(R.id.tt_time, secondary)
            rv.setTextViewText(R.id.tt_room, style.label(room, ambient = !row.focus, foreground = secondary))
            rv.setViewVisibility(R.id.tt_room, if (fit.extra == null) View.GONE else View.VISIBLE)
            fit.extra?.let {
                rv.setTextViewTextSize(R.id.tt_room, TypedValue.COMPLEX_UNIT_PX, it.pixels)
                rv.setInt(R.id.tt_room, "setMaxLines", it.lines)
            }
            rv.setTextColor(R.id.tt_room, secondary)
            rv.setContentDescription(R.id.tt_row,
                listOf(row.name, row.badge, row.start, row.end, row.room.ifEmpty { "教室待确认" }).joinToString("，"))
            rv.setOnClickFillInIntent(R.id.tt_row, WidgetLinks.row("timetable"))
            return rv
        }
        override fun getLoadingView() = RemoteViews(ctx.packageName, R.layout.timetable_widget_row)
        override fun getViewTypeCount() = 1
        override fun getItemId(position: Int) = position.toLong()
        override fun hasStableIds() = false
    }
}
