package com.worknote.homework_radar

import android.content.Context
import android.graphics.Typeface
import android.graphics.Paint
import android.os.Build
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.text.TextUtils
import android.util.TypedValue
import kotlin.math.ceil
import kotlin.math.floor

/** Measures the real theme font at the host's font scale before creating rows.
 * RemoteViews still draws native TextViews; only presentation sizes are chosen. */
internal class WidgetRowTypography(private val context: Context, private val size: WidgetDimensions,
    private val layout: WidgetLayout, private val style: StudyWidgetStyle, private val timetable: Boolean,
    headerHeight: Int? = null) {
    val compact = size.height < 100
    val padding = dp(if (compact) 2f else if (timetable) 7f else 4f)
    val gap = dp(if (compact) 1f else 3f)
    private val metrics = context.resources.displayMetrics
    private fun sp(value: Float) = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, value, metrics)
    private fun dp(value: Float) = (value * context.resources.displayMetrics.density).toInt()
    private val width = dp(size.width - 24f) - 2 * padding
    private val viewport: Int
    val minimumHeight get() = if (compact) viewport else 0

    init {
        val outer = if (compact) 3f else if (layout.tiny) 8f else 12f
        var h = dp(size.height - 2 * outer)
        if (layout.showHeader) h -= (headerHeight ?: maxOf(
            measure("作业课表", Int.MAX_VALUE / 4, sp(15f), true).height,
            measure("第2周", Int.MAX_VALUE / 4, sp(10f), true).height + dp(8f))) + dp(6f)
        val summary = if (timetable) layout.showHeader && !layout.narrow else layout.showSummary
        if (summary) h -= measure("今天待交", width, sp(12f), false, 1).height + dp(7f)
        if (layout.showFooter) h -= measure("本地快照", width, sp(11f), false, 1).height + dp(5f)
        viewport = (h - dp(1f)).coerceAtLeast(dp(20f))
    }

    data class TextFit(val pixels: Float, val lines: Int)
    data class Row(val title: TextFit, val detail: TextFit, val extra: TextFit?, val padding: Int)

    private fun measure(value: String, width: Int, pixels: Float, bold: Boolean,
        lines: Int = Int.MAX_VALUE): StaticLayout {
        val paint = TextPaint(TextPaint.ANTI_ALIAS_FLAG).apply {
            textSize = pixels
            // The native view starts with sans-serif, then TypefaceSpan applies
            // the theme. Its locale minimum metrics use that original paint.
            typeface = Typeface.create("sans-serif", if (bold) Typeface.BOLD else Typeface.NORMAL)
            textLocales = context.resources.configuration.locales
        }
        val builder = StaticLayout.Builder.obtain(style.label(value), 0, value.length, paint, width.coerceAtLeast(1))
            .setIncludePad(false).setBreakStrategy(if (bold) Layout.BREAK_STRATEGY_BALANCED else Layout.BREAK_STRATEGY_HIGH_QUALITY)
            .setHyphenationFrequency(Layout.HYPHENATION_FREQUENCY_NONE)
            .setMaxLines(lines).setEllipsize(TextUtils.TruncateAt.END)
        if (Build.VERSION.SDK_INT >= 28) builder.setUseLineSpacingFromFallbacks(true)
        if (Build.VERSION.SDK_INT >= 35) builder.setMinimumFontMetrics(Paint.FontMetrics().apply {
            paint.getFontMetricsForLocale(this)
        })
        return builder.build()
    }

    private fun fitted(value: String, width: Int, height: Int, wanted: Float,
        minPixels: Float, bold: Boolean, maxLines: Int): TextFit {
        val minLine = measure("作业Ag", width, minPixels, bold, 1).height.coerceAtLeast(1)
        val lines = minOf(maxLines, (height / minLine).coerceAtLeast(1))
        fun fits(pixels: Float): Boolean {
            val text = measure(value, width, pixels, bold)
            return text.height <= height && text.lineCount <= lines
        }
        var low = minOf(minPixels, wanted)
        var high = wanted
        if (fits(high)) return TextFit(high, lines)
        repeat(12) { val mid = (low + high) / 2; if (fits(mid)) low = mid else high = mid }
        return TextFit(floor(low * 10) / 10, lines)
    }

    fun empty(value: String): TextFit = fitted(value, width, viewport - 1,
        sp(14f), dp(10f).toFloat(), false, if (compact) 1 else 6)

    fun row(title: String, detail: String, extra: String, badge: String, titleSp: Float = 14f): Row {
        val badgeWidth = if (badge.isEmpty()) 0 else {
            val paint = TextPaint().apply { textSize = sp(11f); typeface = Typeface.create(this@WidgetRowTypography.style.theme.font, Typeface.NORMAL) }
            ceil(paint.measureText(badge)).toInt() + dp(if (timetable) 6f else 10f)
        }
        val titleWidth = (width - badgeWidth).coerceAtLeast(1)
        val maxTitleLines = if (compact) 2 else 6
        val titleMin = dp(10f).toFloat()
        val detailMin = dp(if (compact) 8f else 9f).toFloat()
        val t = measure(title, titleWidth, sp(titleSp), true, maxTitleLines).height + 2
        val d = if (compact) dp(16f) else measure(detail, width, sp(12f), false).height + 2
        val e = if (compact || extra.isEmpty()) 0 else measure(extra, width, sp(12f), false, 2).height + 2
        val minimumTitle = measure("作业Ag", titleWidth, titleMin, true, 1).height + 2
        val minimumDetail = measure(detail, width, detailMin, false).height + 2
        val content = (viewport - 2 * padding).coerceAtLeast(2)
        val budget = WidgetRowBudget.fit(content, t, d, e, gap, minimumTitle, minimumDetail)
        return Row(fitted(title, titleWidth, budget.title - 1, sp(titleSp), titleMin, true, maxTitleLines),
            fitted(detail, width, budget.detail - 1, sp(12f), detailMin, false, if (compact) 1 else 6),
            if (budget.extra > 0) fitted(extra, width, budget.extra - 1, sp(12f), dp(10f).toFloat(), false, 2) else null,
            padding)
    }
}
