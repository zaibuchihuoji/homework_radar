package com.worknote.homework_radar

import android.app.WallpaperManager
import android.content.Context
import android.os.Build

/// 透明小组件的壁纸明暗判定。
/// Public wallpaper colors estimate the backdrop; text-only halos protect
/// mixed photos where one global color cannot describe every glyph location.
/// getWallpaperColors 只拿统计色，不需要读壁纸位图的权限；
/// 拿不到（动态壁纸/低版本）时按深色处理——会用透明模式的桌面大多铺深色壁纸。
object WidgetGlass {
    fun wallpaperDark(context: Context): Boolean {
        return WidgetContrast.palette(wallpaperColor(context)).lightText
    }

    fun wallpaperColor(context: Context): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O_MR1) return 0xFF20242B.toInt()
        return try {
            val colors = WallpaperManager.getInstance(context)
                .getWallpaperColors(WallpaperManager.FLAG_SYSTEM)
            colors?.primaryColor?.toArgb() ?: 0xFF20242B.toInt()
        } catch (_: Exception) {
            0xFF20242B.toInt()
        }
    }

    /** Sample the processed material rather than the raw photo, because the
     * glass pipeline changes brightness. No readable photo: use public colors. */
    internal fun backdropColor(context: Context, size: WidgetDimensions? = null): Int {
        return try {
            val width = size?.width ?: 64; val height = size?.height ?: 64
            val scale = 64f / maxOf(width, height)
            GlassWallpaperRenderer.backdropColor(context,
                (width * scale).toInt().coerceAtLeast(16),
                (height * scale).toInt().coerceAtLeast(16)) ?: wallpaperColor(context)
        } catch (_: Exception) {
            wallpaperColor(context)
        }
    }
}
