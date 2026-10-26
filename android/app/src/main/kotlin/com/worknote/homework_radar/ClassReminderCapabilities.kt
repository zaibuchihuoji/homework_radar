package com.worknote.homework_radar

import android.app.NotificationManager
import android.content.Context
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/** Read-only system capabilities. A device brand is never proof of app access.
 * vivo scene query is documented at dev.vivo.com.cn/documentCenter/doc/896.
 * No vendor push registration or user data transmission is performed here.
 */
internal object ClassReminderCapabilities {
    fun register(context: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, "homework_radar/class_reminders").setMethodCallHandler { call, result ->
            if (call.method != "capability") result.notImplemented()
            else {
                val brand = Build.MANUFACTURER.lowercase(Locale.ROOT)
                val name = when {
                    brand.contains("vivo") || brand.contains("iqoo") -> "vivo 原子岛"
                    brand.contains("oppo") || brand.contains("oneplus") || brand.contains("realme") -> "OPPO 流体云"
                    brand.contains("xiaomi") || brand.contains("redmi") -> "小米 超级岛"
                    else -> "系统提醒卡片"
                }
                // A successful scene query does not certify a released adapter
                // or an approved classroom scenario. UI keeps this distinction.
                var sceneEnabled: Boolean? = null
                if (brand.contains("vivo") || brand.contains("iqoo")) {
                    sceneEnabled = try {
                        val method = NotificationManager::class.java.getDeclaredMethod(
                            "getSceneStatus", String::class.java, String::class.java)
                        method.isAccessible = true
                        method.invoke(context.getSystemService(Context.NOTIFICATION_SERVICE), context.packageName, "METTING") as? Boolean
                    } catch (_: Exception) { null }
                }
                result.success(mapOf("name" to name, "sceneEnabled" to sceneEnabled,
                    "adapterActive" to false, "requiresVendorAccess" to true))
            }
        }
    }
}
