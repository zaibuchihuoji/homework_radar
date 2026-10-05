package com.worknote.homework_radar

import android.app.WallpaperManager
import android.content.Context
import android.graphics.BitmapFactory
import android.os.Build

/// 透明小组件的壁纸明暗判定。
/// 玻璃材质本身没有底色，文字对比度全靠壁纸明暗：
/// 壁纸深 → 浅色字，壁纸浅 → 深色字（iOS 深浅玻璃自适应的平替）。
/// getWallpaperColors 只拿统计色，不需要读壁纸位图的权限；
/// 拿不到（动态壁纸/低版本）时按深色处理——会用透明模式的桌面大多铺深色壁纸。
object WidgetGlass {
    fun wallpaperDark(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O_MR1) return true
        return try {
            val colors = WallpaperManager.getInstance(context)
                .getWallpaperColors(WallpaperManager.FLAG_SYSTEM)
            // primaryColor 是 Color 对象；分量取 0~1 浮点，直接算 ITU-R 601 亮度
            val c = colors?.primaryColor ?: return true
            (0.299f * c.red() + 0.587f * c.green() + 0.114f * c.blue()) < 0.55f
        } catch (_: Exception) {
            true
        }
    }

    /**
     * 透明模式的底材明暗判定：优先看用户选图（glass_bg_path）的亮度。
     *
     * 为什么不只按壁纸判：选图模式的玻璃底材是用户素材，亮度与当前壁纸
     * 无关——近白素材压壁纸深色判定会给出浅色字，直接压在亮底上看不清。
     * 对素材做小尺寸采样解码求平均亮度，<0.5 判深；没选图 / 素材读不到 /
     * 解码失败一律回退壁纸判定，调用方无需区分两种底材。
     */
    fun backdropDark(context: Context): Boolean {
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val path = prefs.getString("glass_bg_path", null)?.takeIf { it.isNotEmpty() }
            ?: return wallpaperDark(context)
        return try {
            // 先只解边界求 inSampleSize，压到 ~64px 再真解码：只为求平均
            // 亮度，小图够准也省内存
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return wallpaperDark(context)
            var sample = 1
            while (maxOf(bounds.outWidth, bounds.outHeight) / sample > 64) sample *= 2
            val bmp = BitmapFactory.decodeFile(
                path, BitmapFactory.Options().apply { inSampleSize = sample }
            ) ?: return wallpaperDark(context)
            val px = IntArray(bmp.width * bmp.height)
            bmp.getPixels(px, 0, bmp.width, 0, 0, bmp.width, bmp.height)
            bmp.recycle()
            var lum = 0.0
            for (c in px) {
                lum += (0.299 * (c ushr 16 and 0xFF) +
                        0.587 * (c ushr 8 and 0xFF) + 0.114 * (c and 0xFF)) / 255.0
            }
            lum / px.size < 0.5
        } catch (_: Exception) {
            wallpaperDark(context)
        }
    }
}
