package com.worknote.homework_radar

import android.graphics.*

/** A bounded bitmap only for the panel. Text/list/click regions remain native. */
internal object WidgetThemePanel {
    private val cache = object : LinkedHashMap<String, Bitmap>(8, .75f, true) {
        override fun removeEldestEntry(e: MutableMap.MutableEntry<String, Bitmap>) = size > 8
    }

    @Synchronized fun render(theme: WidgetThemeData, size: WidgetDimensions, density: Float,
        transparent: Boolean, darkGlass: Boolean, material: Bitmap?, hostRadius: Float): Bitmap {
        val scale = minOf(density, 720f / maxOf(size.width, size.height))
        val width = (size.width * scale).toInt().coerceAtLeast(16)
        val height = (size.height * scale).toInt().coerceAtLeast(16)
        // Material comes from its own fingerprinted cache and may change in place on disk.
        val key = "$theme:$width:$height:$hostRadius:$transparent:$darkGlass:${material?.generationId}"
        cache[key]?.let { return it }
        val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        c.scale(width.toFloat() / size.width, height.toFloat() / size.height)
        val w = size.width.toFloat(); val h = size.height.toFloat()
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        val ink = if (transparent && darkGlass) Color.WHITE else theme.ink
        val accent = if (transparent && darkGlass) Color.WHITE else theme.accent
        val geometry = WidgetPanelGeometry.create(w, h, theme.radius, hostRadius)
        val bounds = RectF(geometry.edge, geometry.edge, w - geometry.edge, h - geometry.edge)
        val d = geometry.frameInset
        val path = Path()
        // Keep the face symmetric. Edge shadows and square outer strokes are
        // cut by launcher rounding; themed frames belong inside this silhouette.
        path.addRoundRect(bounds, geometry.radius, geometry.radius, Path.Direction.CW)
        c.save(); c.clipPath(path)
        if (transparent && material != null) {
            c.drawBitmap(material, null, RectF(0f, 0f, w, h), p)
        }
        // Transparent mode exposes the actual desktop (or the selected material).
        // Keep contrast in the adaptive text/rows, not a dark sheet over the panel.
        if (!transparent) {
            p.color = theme.surface
            c.drawRect(0f, 0f, w, h, p)
        }
        fun line(x1: Float, y1: Float, x2: Float, y2: Float, color: Int, stroke: Float = 1f) {
            p.shader = null; p.pathEffect = null; p.color = color; p.strokeWidth = stroke
            p.style = Paint.Style.STROKE; c.drawLine(x1,y1,x2,y2,p); p.style = Paint.Style.FILL
        }
        // At one-cell height the text needs the inner area. Keep theme accents
        // in the outer trim so rules/frames cannot cross the title or deadline.
        if (h < 100f) {
            if (theme.style == "pixel") {
                for (i in 0..2) { p.color=theme.focus; c.drawRect(w/2-8+i*6,h-3,w/2-5+i*6,h-1.5f,p) }
            } else if (theme.style != "clay") line(w/2-10,2f,w/2+10,2f,theme.focus,1.5f)
        } else when (theme.style) {
            "clean" -> line(w / 2 - 12, 4f, w / 2 + 12, 4f, theme.focus, 3f)
            "green" -> line(4f, geometry.radius, 4f, minOf(h - geometry.radius, geometry.radius + 25), theme.focus, 3f)
            "morandi" -> {
                p.color = (accent and 0xFFFFFF) or 0x12000000
                c.drawCircle(w - 20, 12f, 40f, p); c.drawCircle(w - 45, 5f, 28f, p)
            }
            "pixel" -> {
                // Square rows carry the frame. A second full panel frame sits
                // behind compact rows and looks broken where they cover it.
                for (i in 0..2) { p.color = theme.focus; c.drawRect(w/2-9+i*7, h-7, w/2-5+i*7, h-4,p) }
            }
            "amoled" -> {
                p.shader = LinearGradient(0f,0f,w,h,
                    intArrayOf((ink and 0xFFFFFF) or 0x0B000000, Color.TRANSPARENT),null,Shader.TileMode.CLAMP)
                c.drawRect(0f,0f,w,h,p); p.shader=null
                for(i in 0..3) line(geometry.radius+i*3,h-5f, minOf(w-geometry.radius, 52f)+i*4,h-5f, (ink and 0xFFFFFF) or 0x30000000)
            }
            "paper" -> {
                p.color=accent; p.style=Paint.Style.STROKE; p.strokeWidth=.7f
                p.pathEffect=DashPathEffect(floatArrayOf(3f,3f),0f)
                c.drawRoundRect(RectF(5f,5f,w-5,h-5),maxOf(0f,geometry.radius-5),maxOf(0f,geometry.radius-5),p)
                p.pathEffect=null; p.style=Paint.Style.FILL
            }
            "comic" -> {
                p.color=ink; p.style=Paint.Style.STROKE; p.strokeWidth=1.4f
                c.drawRoundRect(RectF(4f,4f,w-4,h-4),maxOf(0f,geometry.radius-4),maxOf(0f,geometry.radius-4),p)
                p.style=Paint.Style.FILL
            }
            "receipt" -> {
                val tear=Path(); tear.moveTo(d,h-d)
                var x=d
                while(x<w-d) { tear.lineTo(minOf(x+3,w-d),h-d-2);tear.lineTo(minOf(x+6,w-d),h-d);x+=6 }
                p.color=accent; p.style=Paint.Style.STROKE; p.strokeWidth=.7f;c.drawPath(tear,p);p.style=Paint.Style.FILL
                for(i in 0..14) if(i%3!=1) line(w/2-22+i*3,h-7,w/2-22+i*3,h-4,ink,if(i%4==0)2f else 1f)
            }
            "editorial" -> {
                line(d,d,w-d,d,ink,2f); line(d,d,minOf(w-d,d+35),d,theme.focus,2f)
                line(d,h-d,w-d,h-d,ink)
            }
            "terminal" -> {
                line(d,d,w-d,d,accent)
                line(d,h-d,w-d,h-d,accent)
                for(i in 0..2) { p.color=accent; c.drawRect(w/2-9+i*6,4f,w/2-6+i*6,7f,p) }
            }
            "journal" -> {
                var y=45f
                while(y<h-12) { line(10f,y,w-10,y,(accent and 0xFFFFFF) or 0x10000000);y+=23f }
                p.color=(theme.focus and 0xFFFFFF) or 0x55000000
                c.save();c.rotate(-4f,w/2,5f);c.drawRect(w/2-24,0f,w/2+24,7f,p);c.restore()
                for(i in 0..2) { p.color=(ink and 0xFFFFFF) or 0x50000000; c.drawCircle(5f,geometry.radius+i*12,1.4f,p) }
            }
        }
        c.restore()
        p.shader=null; p.pathEffect=null; p.style=Paint.Style.STROKE
        p.strokeWidth=.6f
        p.color=if(transparent) (ink and 0xFFFFFF) or 0x70000000
            else theme.border
        c.drawPath(path,p)
        cache[key]=bmp
        return bmp
    }
}
