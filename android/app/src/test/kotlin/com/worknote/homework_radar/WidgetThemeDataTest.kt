package com.worknote.homework_radar

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class WidgetThemeDataTest {
    private fun snapshot(style: String, mode: String = "system") = JSONObject().apply {
        put("version", 1); put("style", style); put("mode", mode)
        for ((key, ink) in listOf("light" to 0xFF151B2BL, "dark" to 0xFFFFF9E9L)) {
            put(key, JSONObject().apply {
                put("surface", 0xFFFFFBF0L); put("card", 0xFFFFFFFFL)
                put("border", 0xFFEAE4D3L); put("ink", ink)
                put("secondary", 0xFF686254L); put("accent", 0xFF65521CL)
                put("focus", 0xFFFFE044L); put("onFocus", 0xFF151B2BL)
            })
        }
    }
    @Test fun everyStyleKeepsItsDistinctDecoration() {
        val names = listOf("clean", "green", "morandi", "pixel", "amoled", "paper",
            "comic", "receipt", "editorial", "terminal", "journal", "clay")
        val themes = names.map { WidgetThemeData.read(snapshot(it).toString(), false) }
        assertEquals(names, themes.map { it.style })
        assertEquals(names.size, themes.map { it.decoration }.toSet().size)
        assertEquals("monospace", themes.first { it.style == "terminal" }.font)
        assertEquals("serif", themes.first { it.style == "paper" }.font)
        assertEquals(0f, themes.first { it.style == "pixel" }.radius)
        assertEquals("sans-serif", themes.first { it.style == "clay" }.font)
        assertEquals("serif", themes.first { it.style == "clay" }.headingFont)
    }
    @Test fun systemModeWorksWithoutDartAndUnsupportedDarkMatchesApp() {
        for (name in listOf("clean", "green")) {
            assertFalse(WidgetThemeData.read(snapshot(name, "light").toString(), true).dark)
            assertTrue(WidgetThemeData.read(snapshot(name, "dark").toString(), false).dark)
            assertTrue(WidgetThemeData.read(snapshot(name).toString(), true).dark)
            assertFalse(WidgetThemeData.read(snapshot(name).toString(), false).dark)
        }
        assertFalse(WidgetThemeData.read(snapshot("terminal", "dark").toString(), true).dark)
    }
    @Test fun invalidOrPreUpgradeThemeFallsBackSafely() {
        val fallback = WidgetThemeData.read(null, false)
        for (bad in listOf("", "bad json", "{}", snapshot("future-style").toString(),
            snapshot("paper").put("version", 50).toString(),
            snapshot("paper").put("light", JSONObject()).toString())) {
            assertEquals(fallback, WidgetThemeData.read(bad, false))
        }
        assertEquals("clean", fallback.style)
        assertEquals(0xFFFFE044.toInt(), fallback.focus)
    }
    @Test fun exactColorsChooseTheEffectivePalette() {
        assertEquals(0xFFFFF9E9.toInt(), WidgetThemeData.read(snapshot("clean", "dark").toString(), false).ink)
        assertEquals(0xFF151B2B.toInt(), WidgetThemeData.read(snapshot("clean", "light").toString(), true).ink)
    }
    @Test fun brightGlassNeverUsesADarkRowBehindDarkText() {
        val dark = WidgetThemeData.read(snapshot("clean", "dark").toString(), false)
        assertEquals("widget_clean_row", dark.rowResource(true, false))
        assertEquals("widget_clean_glass_dark", dark.rowResource(true, true))
        assertEquals("widget_clean_dark_row", dark.rowResource(false, false))
    }
}
