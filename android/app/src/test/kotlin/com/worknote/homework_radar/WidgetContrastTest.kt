package com.worknote.homework_radar

import org.junit.Assert.*
import org.junit.Test

class WidgetContrastTest {
    @Test fun transparentRowTintIsIncludedInTextContrast() {
        for (gray in 0..255) {
            val wallpaper = 0xFF000000.toInt() or (gray shl 16) or (gray shl 8) or gray
            for (tint in listOf(0x16FFFFFF, 0x99FFFCF5, 0)) {
                val surface = WidgetContrast.composite(tint.toInt(), wallpaper)
                val palette = WidgetContrast.palette(surface)
                for (text in listOf(palette.ink, palette.secondary, palette.danger))
                    assertTrue(WidgetContrast.ratio(text, surface) >= 4.5)
            }
        }
        assertEquals(0xFFFFFFFF.toInt(), WidgetContrast.composite(0xFFFFFFFF.toInt(), 0xFF000000.toInt()))
    }
    @Test fun everyGrayKeepsTitlesMetadataAndOverdueReadable() {
        for (gray in 0..255) {
            val background = 0xFF000000.toInt() or (gray shl 16) or (gray shl 8) or gray
            val palette = WidgetContrast.palette(background)
            for (text in listOf(palette.ink, palette.secondary, palette.danger)) {
                assertTrue("gray=$gray text=${text.toUInt()}", WidgetContrast.ratio(text, background) >= 4.5)
            }
        }
    }

    @Test fun saturatedWallpaperColorsAlsoKeepTextContrast() {
        for (color in listOf(0xFFFFE044, 0xFF3074FF, 0xFF00AA88, 0xFFEE2277, 0xFF805030)) {
            val palette = WidgetContrast.palette(color.toInt())
            assertTrue(WidgetContrast.ratio(palette.ink, color.toInt()) >= 4.5)
            assertTrue(WidgetContrast.ratio(palette.secondary, color.toInt()) >= 4.5)
            assertTrue(WidgetContrast.ratio(palette.danger, color.toInt()) >= 4.5)
        }
    }

    @Test fun whiteAndBlackUseOppositeTextAndOverdueStaysRed() {
        val dark = WidgetContrast.palette(0xFF111111.toInt())
        val light = WidgetContrast.palette(0xFFF8F8F8.toInt())
        assertTrue(dark.lightText)
        assertFalse(light.lightText)
        for (p in listOf(dark, light, WidgetContrast.palette(0xFF808080.toInt()))) {
            assertTrue((p.danger ushr 16 and 255) > (p.danger ushr 8 and 255))
        }
    }
}
