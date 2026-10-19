package com.worknote.homework_radar

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import java.io.File

/// 液态玻璃小组件的底材选择与加工。
///
/// 默认材质由 WidgetThemePanel 保持透明，仅绘制主题细节。
/// 不合成任何"壁纸色渐变"——API 33+ 三方应用拿不到壁纸位图，合成色和
/// 组件背后的真实像素永远对不上，一眼就是假玻璃。半透像素让真实壁纸
/// 透出来，材料均匀所以永远成立。
///
/// 用户选图（glass_bg_path）：真实素材可以诚实加工——cover 裁剪 → 低通模糊 →
/// 边缘透镜位移 → 白纱，得到 iOS 26 风格的"预折"玻璃底位图。
/// 位图按（素材指纹 + 尺寸）缓存，30 分钟一次的系统重绘不会重复计算。
object GlassWallpaperRenderer {
    private const val TAG = "GlassWallpaper"
    private const val WORK_MAX = 720      // 管线工作分辨率上限（玻璃是低频材质，够用）
    private const val BAND_FRAC = 0.16f   // 折射边缘带占短边比例
    private const val OVERSCAN = 1.4f     // overscan 幅度 = band × 1.4

    /// LRU 缓存（素材指纹+尺寸 → 玻璃位图）。
    /// 单槽缓存在两个小组件默认尺寸不同的前提下互相踢出，每轮系统重绘
    /// 两个组件各做一遍全量解码+渲染；LRU(4) 让两个组件的底图常驻。
    private val cache = object : LinkedHashMap<String, Bitmap>(4, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Bitmap>): Boolean {
            if (size <= 4) return false
            eldest.value.recycle() // 被挤出的位图显式回收，别全靠 GC 堆峰值叠加
            return true
        }
    }
    private val cacheLock = Any()
    private val colorCache = object : LinkedHashMap<String, Int>(12, .75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Int>) = size > 12
    }

    private fun imageFile(context: Context): File? {
        val path = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            .getString("glass_bg_path", null)?.takeIf { it.isNotEmpty() } ?: return null
        return File(path).takeIf { it.exists() }
    }

    fun backdropColor(context: Context, width: Int, height: Int): Int? {
        val file = imageFile(context) ?: return null
        val key = "${file.absolutePath}:${file.lastModified()}:${file.length()}:$width:$height"
        return synchronized(colorCache) {
            colorCache[key]?.let { return@synchronized it }
            // Sampling owns its small bitmaps. It must not evict/recycle the
            // panel renderer's shared materials while another widget uses them.
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(file.absolutePath, bounds)
            var sample = 1
            while (maxOf(bounds.outWidth, bounds.outHeight) / sample > 128) sample *= 2
            val source = BitmapFactory.decodeFile(file.absolutePath,
                BitmapFactory.Options().apply { inSampleSize = sample }) ?: return@synchronized null
            val bitmap = try { render(source, width, height) } finally { source.recycle() }
            val color = try {
                val pixels = IntArray(bitmap.width * bitmap.height)
                bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
                var red = 0L; var green = 0L; var blue = 0L
                for (pixel in pixels) {
                    red += pixel ushr 16 and 255; green += pixel ushr 8 and 255; blue += pixel and 255
                }
                0xFF000000.toInt() or ((red / pixels.size).toInt() shl 16) or
                    ((green / pixels.size).toInt() shl 8) or (blue / pixels.size).toInt()
            } finally { bitmap.recycle() }
            colorCache[key] = color
            color
        }
    }

    /// 取加工好的玻璃底位图；仅当用户选了素材图时返回，否则回退 drawable 玻璃
    fun glassBackdrop(context: Context, widthPx: Int, heightPx: Int): Bitmap? {
        if (widthPx < 16 || heightPx < 16) {
            android.util.Log.d(TAG, "glass skip: bad size ${widthPx}x$heightPx")
            return null
        }
        val imgFile = imageFile(context) ?: return null

        val key = "img:${imgFile.lastModified()}:${imgFile.length()}:$widthPx x $heightPx"
        synchronized(cacheLock) {
            cache[key]?.let { return it }
        }
        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(imgFile.absolutePath, opts)
        var sample = 1
        while (maxOf(opts.outWidth, opts.outHeight) / sample > WORK_MAX * 2) sample *= 2
        val decodeOpts = BitmapFactory.Options().apply { inSampleSize = sample }
        val src = BitmapFactory.decodeFile(imgFile.absolutePath, decodeOpts) ?: return null
        android.util.Log.d(TAG, "glass src=custom ${src.width}x${src.height}")
        val glass = render(src, widthPx, heightPx)
        src.recycle() // 源位图只用于本次加工，显式回收
        synchronized(cacheLock) {
            cache[key] = glass
        }
        return glass
    }

    private fun render(src: Bitmap, wPx: Int, hPx: Int): Bitmap {
        val scale = minOf(1f, WORK_MAX.toFloat() / maxOf(wPx, hPx))
        val w = (wPx * scale).toInt().coerceAtLeast(16)
        val h = (hPx * scale).toInt().coerceAtLeast(16)
        val band = (minOf(w, h) * BAND_FRAC).toInt().coerceIn(8, 128)
        val e = (band * OVERSCAN).toInt().coerceAtLeast(2)

        // ① cover + overscan
        val over = coverCrop(src, w + 2 * e, h + 2 * e)

        // ② 中心轻模糊
        val small = Bitmap.createScaledBitmap(
            over, (over.width / 7).coerceAtLeast(4), (over.height / 7).coerceAtLeast(4), true
        )
        val blurred = Bitmap.createScaledBitmap(small, over.width, over.height, true)
        small.recycle()
        over.recycle()

        // ③ 透镜位移 + 亮度累计
        val bw = blurred.width
        val bh = blurred.height
        val px = IntArray(bw * bh)
        blurred.getPixels(px, 0, bw, 0, 0, bw, bh)
        blurred.recycle()

        val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val glass = IntArray(w * h)
        var lumSum = 0L
        for (y in 0 until h) {
            val ky = edgeK(y, h, band)
            val sy = y + e - e * ky
            for (x in 0 until w) {
                val sx = x + e - e * edgeK(x, w, band)
                val c = sampleBilinear(px, bw, bh, sx, sy)
                glass[y * w + x] = c
                lumSum += (299 * (c ushr 16 and 0xFF) +
                        587 * (c ushr 8 and 0xFF) + 114 * (c and 0xFF)).toLong()
            }
        }
        // ④ 素材越暗 → 白纱越厚：0.06 ~ 0.14，玻璃在暗壁纸上保持"奶白体"辨识度。
        // avgLum 归一到 0~1（Y 权重和为 1000，先除 1000 再除 255）——
        // 此前少了 /255，正常亮度素材的 (1-avgLum) 是大负数，veil 变负、
        // keep>10，除近白像素外整图被钳成黑底白噪点
        val avgLum = lumSum / (w.toLong() * h) / 1000f / 255f
        val veil = (0.06f + 0.08f * (1f - avgLum)).coerceIn(0.06f, 0.14f)
        val keep = 1f - veil
        for (i in glass.indices) {
            val c = glass[i]
            val r = ((c ushr 16 and 0xFF) * keep + 255 * veil).toInt().coerceIn(0, 255)
            val g = ((c ushr 8 and 0xFF) * keep + 255 * veil).toInt().coerceIn(0, 255)
            val b = ((c and 0xFF) * keep + 255 * veil).toInt().coerceIn(0, 255)
            glass[i] = -0x1000000 or (r shl 16) or (g shl 8) or b
        }
        out.setPixels(glass, 0, w, 0, 0, w, h)
        return out
    }

    /// 边缘折射系数：1.0 在边上（采样收到最外圈），带宽外为 0（不位移），平方缓出
    private fun edgeK(v: Int, size: Int, band: Int): Float {
        val d = minOf(v, size - 1 - v)
        if (d >= band) return 0f
        val t = 1f - d.toFloat() / band
        return t * t
    }

    private fun sampleBilinear(px: IntArray, w: Int, h: Int, fx: Float, fy: Float): Int {
        val x = fx.coerceIn(0f, w - 1f)
        val y = fy.coerceIn(0f, h - 1f)
        val x0 = x.toInt().coerceAtMost(w - 2)
        val y0 = y.toInt().coerceAtMost(h - 2)
        val tx = x - x0
        val ty = y - y0
        val c00 = px[y0 * w + x0]
        val c10 = px[y0 * w + x0 + 1]
        val c01 = px[(y0 + 1) * w + x0]
        val c11 = px[(y0 + 1) * w + x0 + 1]
        val r = lerp(
            lerp(c00 ushr 16 and 0xFF, c10 ushr 16 and 0xFF, tx),
            lerp(c01 ushr 16 and 0xFF, c11 ushr 16 and 0xFF, tx), ty
        )
        val g = lerp(
            lerp(c00 ushr 8 and 0xFF, c10 ushr 8 and 0xFF, tx),
            lerp(c01 ushr 8 and 0xFF, c11 ushr 8 and 0xFF, tx), ty
        )
        val b = lerp(
            lerp(c00 and 0xFF, c10 and 0xFF, tx),
            lerp(c01 and 0xFF, c11 and 0xFF, tx), ty
        )
        return -0x1000000 or (r shl 16) or (g shl 8) or b
    }

    private fun lerp(a: Int, b: Int, t: Float) = (a + (b - a) * t).toInt()

    /// cover 裁剪：等比铺满目标尺寸后居中裁掉出界部分
    private fun coverCrop(src: Bitmap, targetW: Int, targetH: Int): Bitmap {
        val s = maxOf(targetW.toFloat() / src.width, targetH.toFloat() / src.height)
        val matrix = Matrix()
        matrix.postScale(s, s)
        matrix.postTranslate((targetW - src.width * s) / 2f, (targetH - src.height * s) / 2f)
        val out = Bitmap.createBitmap(targetW, targetH, Bitmap.Config.ARGB_8888)
        Canvas(out).drawBitmap(
            src, matrix, Paint(Paint.FILTER_BITMAP_FLAG or Paint.DITHER_FLAG)
        )
        return out
    }
}
