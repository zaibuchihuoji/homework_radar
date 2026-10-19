package com.worknote.homework_radar

import org.junit.Assert.*
import org.junit.Test

class WidgetRowBudgetTest {
    @Test fun compactViewportKeepsTheDeadlineAndBoundsTheTitle() {
        val fit = WidgetRowBudget.fit(112, 128, 32, 0, 2, 28, 26)
        assertEquals(78, fit.title)
        assertEquals(32, fit.detail)
        assertEquals(0, fit.extra)
        assertTrue(fit.title + fit.detail + 2 <= 112)
    }

    @Test fun largeFontsDoNotPushTheDeadlineOutsideTheViewport() {
        val fit = WidgetRowBudget.fit(240, 160, 140, 50, 6, 28, 26)
        assertTrue(fit.detail >= 26)
        assertTrue(fit.title >= 28)
        assertEquals(0, fit.extra)
        assertTrue(fit.title + fit.detail + 6 <= 240)
    }

    @Test fun enoughSpacePreservesNaturalTextSizesAndCourseInformation() {
        val fit = WidgetRowBudget.fit(240, 80, 36, 34, 6, 28, 26)
        assertEquals(80, fit.title)
        assertEquals(36, fit.detail)
        assertEquals(34, fit.extra)
    }

    @Test fun allSupportedSmallHeightsKeepCriticalTextInsideTheBody() {
        for (height in listOf(28, 40, 56, 112, 240, 500)) {
            val fit = WidgetRowBudget.fit(height, 160, 80, 34, 2, 14, 13)
            assertTrue(fit.title > 0)
            assertTrue(fit.detail > 0)
            assertTrue(fit.title + fit.detail + fit.extra + 2 + (if (fit.extra>0) 2 else 0) <= height)
        }
    }

    @Test fun compactDeadlinesKeepYearDateAndMinuteWithoutRedundantSuffix() {
        assertEquals("2027/12/20 16:16", WidgetRowBudget.deadline("2027/12/20 16:16 截止"))
        assertEquals("今天 09:05", WidgetRowBudget.deadline("今天 09:05 截止"))
        assertEquals("截止时间未设", WidgetRowBudget.deadline("截止时间未设"))
        assertEquals("时间待确认", WidgetRowBudget.deadline("时间待确认"))
    }
}
