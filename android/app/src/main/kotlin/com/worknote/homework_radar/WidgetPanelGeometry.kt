package com.worknote.homework_radar

import kotlin.math.ceil
import kotlin.math.sqrt

/** Shared silhouette: launchers round the widget even when its theme is square. */
internal data class WidgetPanelGeometry(val edge: Float, val radius: Float, val frameInset: Float) {
    companion object {
        fun create(width: Float, height: Float, themeRadius: Float, hostRadius: Float): WidgetPanelGeometry {
            val edge = .5f
            val radius = maxOf(themeRadius, hostRadius).coerceIn(0f, (minOf(width, height) - 1f) / 2f)
            // A square inner frame's corners (and stroke) must clear the outer arc.
            val inset = ceil(edge + radius * (1f - 1f / sqrt(2f)) + 1.5f)
            return WidgetPanelGeometry(edge, radius, inset)
        }
    }
}
