package com.worknote.homework_radar

import android.content.SharedPreferences
import java.io.IOException
import java.lang.reflect.Proxy
import org.junit.Assert.assertThrows
import org.junit.Test

class DurablePreferencesTest {
    private fun editor(success: Boolean) = Proxy.newProxyInstance(
        SharedPreferences.Editor::class.java.classLoader,
        arrayOf(SharedPreferences.Editor::class.java)
    ) { _, method, _ ->
        when (method.name) {
            "commit" -> success
            else -> throw AssertionError("Expected a durable commit, got ${method.name}")
        }
    } as SharedPreferences.Editor

    @Test fun failedDiskCommitIsReportedToTheCaller() {
        assertThrows(IOException::class.java) { DurablePreferences.commit(editor(false)) }
    }

    @Test fun successfulDiskCommitCompletesNormally() {
        DurablePreferences.commit(editor(true))
    }
}
