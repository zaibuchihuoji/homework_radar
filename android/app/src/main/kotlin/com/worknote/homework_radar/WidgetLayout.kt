package com.worknote.homework_radar

/** Breakpoints remove decoration before rows fit their title and deadline. */
internal data class WidgetLayout(val narrow: Boolean, val tiny: Boolean,
    val showHeader: Boolean, val showSummary: Boolean, val showFooter: Boolean) {
    companion object {
        fun forSize(width: Int, height: Int, fontScale: Float): WidgetLayout {
            val usable = height / fontScale.coerceAtLeast(1f)
            return WidgetLayout(width / fontScale.coerceAtLeast(1f) < 230,
                usable < 100, usable >= 100, usable >= 175, usable >= 200)
        }
    }
}
