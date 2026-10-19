package com.worknote.homework_radar

import kotlin.math.pow
import kotlin.math.roundToInt

/** Color math only. Business records and widget line budgets are untouched. */
internal object WidgetContrast {
    data class Palette(val ink: Int, val secondary: Int, val danger: Int, val lightText: Boolean)
    private const val BLACK = -0x1000000
    private const val WHITE = -0x1

    fun luminance(color: Int): Double {
        fun linear(shift: Int): Double {
            val channel = (color ushr shift and 255) / 255.0
            return if (channel <= .04045) channel / 12.92 else ((channel + .055) / 1.055).pow(2.4)
        }
        return .2126 * linear(16) + .7152 * linear(8) + .0722 * linear(0)
    }

    fun ratio(text: Int, background: Int): Double {
        val a = luminance(text); val b = luminance(background)
        return (maxOf(a, b) + .05) / (minOf(a, b) + .05)
    }

    fun composite(tint: Int, background: Int): Int {
        val alpha = tint ushr 24
        var result = BLACK
        for (shift in listOf(16, 8, 0)) {
            val a = tint ushr shift and 255; val b = background ushr shift and 255
            result = result or (((a * alpha + b * (255 - alpha) + 127) / 255) shl shift)
        }
        return result
    }

    private fun blend(from: Int, to: Int, amount: Double): Int {
        var color = BLACK
        for (shift in listOf(16, 8, 0)) {
            val a = from ushr shift and 255; val b = to ushr shift and 255
            color = color or ((a + (b - a) * amount).roundToInt() shl shift)
        }
        return color
    }

    private fun readable(color: Int, background: Int, light: Boolean): Int {
        fun fits(candidate: Int) = ratio(candidate, background) >= 4.5
        if (fits(color)) return color
        val target = if (light) WHITE else BLACK
        var low = 0.0; var high = 1.0
        repeat(20) {
            val mid = (low + high) / 2
            if (fits(blend(color, target, mid))) high = mid else low = mid
        }
        return blend(color, target, high)
    }

    fun palette(background: Int): Palette {
        val light = ratio(WHITE, background) >= ratio(BLACK, background)
        return Palette(
            readable(if (light) 0xFFFFFDF5.toInt() else 0xFF151B2B.toInt(), background, light),
            readable(if (light) 0xFFDDD8C9.toInt() else 0xFF53565B.toInt(), background, light),
            readable(if (light) 0xFFFFB4A8.toInt() else 0xFFAF3324.toInt(), background, light), light)
    }
}
