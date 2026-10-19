package com.worknote.homework_radar

import android.appwidget.AppWidgetManager
import android.app.WallpaperManager
import android.content.ComponentCallbacks
import android.content.ComponentName
import android.content.Context
import android.content.res.Configuration
import android.os.Build
import android.os.Handler
import android.os.Looper

/** A launcher reinflates text after font changes without necessarily sending
 * new size options. Re-evaluate our breakpoints too, using application context. */
internal object WidgetConfiguration {
    private var registered = false

    @Synchronized fun observe(context: Context) {
        if (registered) return
        val app = context.applicationContext
        registered = true
        app.registerComponentCallbacks(object : ComponentCallbacks {
            override fun onConfigurationChanged(configuration: Configuration) = refresh(app)
            override fun onLowMemory() {}
        })
        if (Build.VERSION.SDK_INT >= 27) {
            try {
                WallpaperManager.getInstance(app).addOnColorsChangedListener({ _, which ->
                    if (which and WallpaperManager.FLAG_SYSTEM != 0) refresh(app)
                }, Handler(Looper.getMainLooper()))
            } catch (_: RuntimeException) {
                // Some launchers deny color events. Existing configuration,
                // periodic and App-resume refreshes still work without a crash.
            }
        }
        // A process restarted to supply list rows can inherit old RemoteViews
        // from the launcher. Refresh their templates once with current config.
        refresh(app)
    }

    private fun refresh(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        HomeworkWidgetProvider().onUpdate(context, manager,
            manager.getAppWidgetIds(ComponentName(context, HomeworkWidgetProvider::class.java)))
        TimetableWidgetProvider().onUpdate(context, manager,
            manager.getAppWidgetIds(ComponentName(context, TimetableWidgetProvider::class.java)))
    }
}
