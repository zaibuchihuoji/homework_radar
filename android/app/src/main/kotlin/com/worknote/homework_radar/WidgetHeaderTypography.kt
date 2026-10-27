package com.worknote.homework_radar

import android.content.Context
import android.graphics.Paint
import android.graphics.Typeface
import android.os.Build
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.util.TypedValue
import android.widget.RemoteViews
import kotlin.math.ceil
import kotlin.math.max

/** Measures the same native header for its RemoteViews and the list below it. */
internal class WidgetHeaderTypography private constructor(
    private val context: Context, size: WidgetDimensions, style: StudyWidgetStyle,
    title: String, mark: String,
) {
    private val metrics = context.resources.displayMetrics
    private fun dp(value: Float) = (value * metrics.density).toInt()
    private fun sp(value: Int) = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, value.toFloat(), metrics)
    private val titleText = style.label(title, heading = true)
    private val markText = style.label(mark, ambient = false)
    private val gap = dp(6f)
    private val padding = dp(4f)
    private val contentWidth = dp((size.width - 24).toFloat()).coerceAtLeast(1)
    private fun measure(value: CharSequence, pixels: Float, width: Int): StaticLayout {
        val paint = TextPaint(TextPaint.ANTI_ALIAS_FLAG).apply {
            textSize = pixels
            typeface = Typeface.create("sans-serif", Typeface.BOLD)
            textLocales = context.resources.configuration.locales
        }
        val builder = StaticLayout.Builder.obtain(value, 0, value.length, paint, width.coerceAtLeast(1))
            .setIncludePad(false).setBreakStrategy(Layout.BREAK_STRATEGY_BALANCED)
            .setHyphenationFrequency(Layout.HYPHENATION_FREQUENCY_NONE)
        if (Build.VERSION.SDK_INT >= 28) builder.setUseLineSpacingFromFallbacks(true)
        if (Build.VERSION.SDK_INT >= 35) builder.setMinimumFontMetrics(Paint.FontMetrics().apply {
            paint.getFontMetricsForLocale(this)
        })
        return builder.build()
    }
    private fun markWidth(pixels: Float): Int {
        val text = measure(markText, pixels, Int.MAX_VALUE / 4)
        return ceil(text.getLineWidth(0)).toInt() + 2 * padding
    }
    private val markPixels = (10 downTo 8).firstOrNull { markWidth(sp(it)) <= contentWidth * .55f }
        .let { sp(it ?: 8) }
    private val titleWidth = (contentWidth - markWidth(markPixels) - gap - 1).coerceAtLeast(1)
    // Wrapped headings are compact labels, rather than a two-line masthead:
    // at a large system font the latter would take space from the deadline.
    private val titlePixels = if (measure(titleText, sp(15), titleWidth).lineCount == 1) sp(15)
        else (13 downTo 12).firstOrNull {
            measure(titleText, sp(it), titleWidth).lineCount <= 2
        }.let { sp(it ?: 12) }
    val height = max(measure(titleText, titlePixels, titleWidth).height,
        measure(markText, markPixels, Int.MAX_VALUE / 4).height + 2 * padding)

    fun apply(views: RemoteViews, headerId: Int, titleId: Int, markId: Int) {
        views.setTextViewText(titleId, titleText)
        views.setTextViewText(markId, markText)
        views.setTextViewTextSize(titleId, TypedValue.COMPLEX_UNIT_PX, titlePixels)
        views.setTextViewTextSize(markId, TypedValue.COMPLEX_UNIT_PX, markPixels)
        views.setInt(titleId, "setMaxLines", 2)
        views.setInt(markId, "setMaxLines", 1)
        views.setViewPadding(markId, padding, padding, padding, padding)
        views.setInt(headerId, "setMinimumHeight", height)
    }

    companion object {
        fun homework(context: Context, size: WidgetDimensions, style: StudyWidgetStyle, count: Int) =
            WidgetHeaderTypography(context, size, style, style.theme.homeworkTitle, style.theme.count("$count 项"))

        fun timetable(context: Context, size: WidgetDimensions, style: StudyWidgetStyle,
            layout: WidgetLayout, hint: String, week: String) = WidgetHeaderTypography(context, size, style,
                if (layout.narrow && hint == "下一节") "下一节课" else style.theme.timetableTitle,
                style.theme.count(week.ifEmpty { "TODAY" }))
    }
}
