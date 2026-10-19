package com.worknote.homework_radar

import org.json.JSONObject

/** Only presentation values cross this boundary. No homework or course writes. */
internal data class WidgetThemeData(
    val style: String = "clean", val dark: Boolean = false,
    val surface: Int = 0xFFFFFBF0.toInt(), val card: Int = 0xFFFFFFFF.toInt(),
    val border: Int = 0xFFEAE4D3.toInt(), val ink: Int = 0xFF151B2B.toInt(),
    val secondary: Int = 0xFF686254.toInt(), val accent: Int = 0xFF65521C.toInt(),
    val focus: Int = 0xFFFFE044.toInt(), val onFocus: Int = 0xFF151B2B.toInt(),
) {
    val decoration get() = style
    val font get() = when (style) {
        "pixel", "receipt", "terminal" -> "monospace"
        "paper", "amoled", "journal" -> "serif"
        else -> "sans-serif"
    }
    val radius get() = when (style) {
        "pixel", "receipt", "editorial" -> 0f
        "terminal" -> 2f
        "paper" -> 10f
        "journal" -> 8f
        "morandi" -> 28f
        "comic" -> 18f
        else -> 22f
    }
    val homeworkTitle get() = when (style) {
        "pixel" -> "作业任务"; "terminal" -> "> 作业"; "paper" -> "待办 · 作业"
        "receipt" -> "作业清单"; "editorial" -> "作业 / 01"; "journal" -> "作业手记"
        "amoled" -> "课业"; else -> "最近作业"
    }
    val timetableTitle get() = when (style) {
        "pixel" -> "课程任务"; "terminal" -> "> 课表"; "paper" -> "今日 · 课程"
        "receipt" -> "课程清单"; "editorial" -> "课表 / 02"; "journal" -> "今日安排"
        "amoled" -> "今日课程"; else -> "今日课表"
    }
    fun count(text: String) = if (style == "terminal") "[$text]" else text
    fun rowResource(transparent: Boolean, darkGlass: Boolean): String =
        if (transparent) "widget_${style}_" + if (darkGlass) "glass_dark" else "row"
        else "widget_${style}${if (dark) "_dark" else ""}_row"

    companion object {
        private val names = setOf("clean", "green", "morandi", "pixel", "amoled", "paper",
            "comic", "receipt", "editorial", "terminal", "journal")
        fun read(json: String?, systemDark: Boolean): WidgetThemeData = try {
            val root = JSONObject(json ?: "")
            require(root.getInt("version") == 1)
            val style = root.getString("style").also { require(it in names) }
            val mode = root.getString("mode").also { require(it in setOf("light", "dark", "system")) }
            val dark = style in setOf("clean", "green") && (mode == "dark" || mode == "system" && systemDark)
            val p = root.getJSONObject(if (dark) "dark" else "light")
            fun color(key: String): Int {
                val raw = p.get(key)
                require(raw is Number)
                val n = raw.toLong()
                require(n in 0..0xFFFFFFFFL)
                return n.toInt()
            }
            WidgetThemeData(style, dark, color("surface"), color("card"), color("border"),
                color("ink"), color("secondary"), color("accent"), color("focus"), color("onFocus"))
        } catch (_: Exception) { WidgetThemeData() }
    }
}
