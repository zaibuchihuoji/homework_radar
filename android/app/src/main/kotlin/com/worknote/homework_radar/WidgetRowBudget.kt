package com.worknote.homework_radar

/** Pixel budgets only; never filters or changes the underlying records. */
internal data class WidgetRowBudget(val title: Int, val detail: Int, val extra: Int) {
    companion object {
        fun fit(height: Int, title: Int, detail: Int, extra: Int, gap: Int,
            minimumTitle: Int, minimumDetail: Int): WidgetRowBudget {
            val core = (height - gap).coerceAtLeast(2)
            var d = detail
            var t = title
            if (t + d > core) {
                d = minOf(detail, maxOf(minimumDetail, (core * .4f).toInt()))
                    .coerceIn(1, maxOf(1, core - minimumTitle))
                t = minOf(title, core - d)
            }
            val e = if (extra > 0 && t + d + extra + gap <= core) extra else 0
            return WidgetRowBudget(t, d, e)
        }

        fun deadline(value: String): String = value.removeSuffix(" 截止")
    }
}
