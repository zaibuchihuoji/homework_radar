package com.worknote.homework_radar

import kotlin.math.hypot
import org.junit.Assert.*
import org.junit.Test

class WidgetPanelGeometryTest {
    @Test fun themedPanelsFitTheLauncherSilhouetteAtEverySupportedSize() {
        for ((width, height) in listOf(124f to 67f, 124f to 151f, 192f to 151f,
            260f to 318f, 600f to 100f)) {
            for (hostRadius in listOf(0f, 16f, 28f, 40f)) {
                for (themeRadius in listOf(0f, 2f, 8f, 10f, 18f, 22f, 28f)) {
                    val g = WidgetPanelGeometry.create(width, height, themeRadius, hostRadius)
                    assertTrue(g.radius >= minOf(hostRadius, (minOf(width, height) - 1f) / 2f))
                    assertTrue(g.radius <= (minOf(width, height) - 1f) / 2f)
                    // Even a square themed frame (including its 1dp stroke) must
                    // stay inside the rounded panel at all four corners.
                    val cornerDistance = hypot(
                        maxOf(0f, g.edge + g.radius - (g.frameInset - .5f)),
                        maxOf(0f, g.edge + g.radius - (g.frameInset - .5f)))
                    assertTrue("$width x $height / $hostRadius / $themeRadius", cornerDistance <= g.radius + .01f)
                    assertTrue(g.frameInset < minOf(width, height) / 2f)
                }
            }
        }
    }

    @Test fun squareThemesKeepTheirFrameInsideHostCorners() {
        val g = WidgetPanelGeometry.create(124f, 151f, 0f, 28f)
        assertEquals(.5f, g.edge, 0f)
        assertEquals(28f, g.radius, 0f)
        assertTrue(g.frameInset >= 10f)
    }
}
