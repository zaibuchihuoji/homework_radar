package com.worknote.homework_radar

import android.content.SharedPreferences
import java.io.IOException

/** Run on the serialized secure-storage worker, never the UI thread. */
internal object DurablePreferences {
    fun commit(editor: SharedPreferences.Editor) {
        if (!editor.commit()) throw IOException("Secure storage disk commit failed")
    }
}
