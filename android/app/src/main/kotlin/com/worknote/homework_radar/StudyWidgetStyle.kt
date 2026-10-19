package com.worknote.homework_radar

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
import android.view.View
import android.widget.RemoteViews

internal data class WidgetDimensions(val width: Int, val height: Int) {
    companion object {
        fun read(context: Context, id: Int): WidgetDimensions {
            val o = AppWidgetManager.getInstance(context).getAppWidgetOptions(id)
            val landscape = context.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
            val width = o.getInt(if (landscape) AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH
                else AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
            val height = o.getInt(if (landscape) AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT
                else AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT)
            return WidgetDimensions(if (width > 0) width else 260, if (height > 0) height else 160)
        }
    }
}

internal class StudyWidgetStyle(private val context: Context, size: WidgetDimensions? = null) {
    private val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
    val theme = WidgetThemeData.read(prefs.getString("widget_theme", null),
        context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES)
    val transparent = prefs.getBoolean("widget_transparent", false)
    private val backdrop = if (transparent) WidgetGlass.backdropColor(context, size) else theme.surface
    private val contrast = if (transparent) WidgetContrast.palette(backdrop) else null
    val dark = contrast?.lightText ?: false
    val ink = contrast?.ink ?: theme.ink
    val secondary = contrast?.secondary ?: theme.secondary
    val danger = contrast?.danger ?: Color.parseColor(if (theme.dark) "#FFB4A8" else "#AF3324")
    val accentInk = theme.onFocus
    val focusInk = when(theme.style) {
        "clean", "green", "pixel" -> theme.onFocus
        "editorial", "terminal" -> theme.card
        else -> theme.ink
    }
    private val key = theme.style + if (theme.dark) "_dark" else ""
    private fun drawable(context: Context, kind: String) = context.resources.getIdentifier(
        "widget_${key}_$kind", "drawable", context.packageName)
    val focusBackground = drawable(context, "focus")
    val badgeBackground = drawable(context, "badge")
    val rowBackground = context.resources.getIdentifier(
        theme.rowResource(transparent, dark), "drawable", context.packageName)
    val textColors = WidgetContrast.Palette(ink, secondary, danger, dark)
    val rowColors by lazy {
        if (!transparent) textColors else {
            // The text is drawn over the theme's translucent row, rather than
            // directly on the wallpaper. Sample its actual center fill.
            val bitmap = android.graphics.Bitmap.createBitmap(64, 64, android.graphics.Bitmap.Config.ARGB_8888)
            val tint = try {
                val drawable = context.getDrawable(rowBackground)!!.mutate()
                drawable.setBounds(0, 0, 64, 64)
                drawable.draw(android.graphics.Canvas(bitmap))
                bitmap.getPixel(32, 32)
            } finally { bitmap.recycle() }
            WidgetContrast.palette(WidgetContrast.composite(tint, backdrop))
        }
    }

    // RemoteViews cannot invoke TextView.setTextAppearance. TypefaceSpan is a
    // parcelable text span supported by launchers, including collection rows.
    private val darkHalo by lazy { android.text.style.TextAppearanceSpan(context, R.style.WidgetTextHaloDark) }
    private val lightHalo by lazy { android.text.style.TextAppearanceSpan(context, R.style.WidgetTextHaloLight) }

    fun label(value: CharSequence, ambient: Boolean = true, foreground: Int = ink): CharSequence = android.text.SpannableString(value).apply {
        val family = when {
            theme.style == "editorial" -> "sans-serif-condensed"
            transparent && ambient && theme.font == "sans-serif" -> "sans-serif-medium"
            else -> theme.font
        }
        setSpan(android.text.style.TypefaceSpan(family), 0, length,
            android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        if (transparent && ambient && isNotEmpty()) {
            val lightGlyphs = WidgetContrast.luminance(foreground) > .3
            // A centered, narrow halo follows glyph edges without painting
            // rectangular word backgrounds over the wallpaper.
            if (android.os.Build.VERSION.SDK_INT >= 29) {
                setSpan(if (lightGlyphs) darkHalo else lightHalo,
                    0, length, android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
        }
    }

    fun badge(views: RemoteViews, id: Int) {
        views.setInt(id, "setBackgroundResource", badgeBackground)
        views.setTextColor(id, theme.onFocus)
    }

    fun background(context: Context, views: RemoteViews, content: Int, glass: Int, size: WidgetDimensions) {
        val density = context.resources.displayMetrics.density
        val material = if (transparent) GlassWallpaperRenderer.glassBackdrop(context,
            (size.width * density).toInt(), (size.height * density).toInt()) else null
        val hostRadius = if (android.os.Build.VERSION.SDK_INT >= 31)
            context.resources.getDimension(android.R.dimen.system_app_widget_background_radius) / density
            else 28f
        views.setImageViewBitmap(glass, WidgetThemePanel.render(theme, size, density, transparent, dark, material, hostRadius))
        views.setViewVisibility(glass, View.VISIBLE)
        views.setInt(content, "setBackgroundColor", Color.TRANSPARENT)
    }
}
