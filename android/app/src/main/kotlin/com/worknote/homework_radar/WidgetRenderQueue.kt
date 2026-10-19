package com.worknote.homework_radar

import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/** Share a background queue for bitmap rendering and coalesce resize requests. */
internal object WidgetRenderQueue {
    private val executor = Executors.newSingleThreadExecutor()
    private val queued = ConcurrentHashMap<String, Boolean>()
    fun submit(key: String, render: () -> Unit) {
        if (queued.putIfAbsent(key, true) != null) return
        executor.execute {
            queued.remove(key)
            try { render() } catch (e: Exception) {
                android.util.Log.w("StudyWidget", "Widget redraw failed", e)
            }
        }
    }
}
