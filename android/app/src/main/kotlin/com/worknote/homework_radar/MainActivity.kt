package com.worknote.homework_radar

import android.content.Context
import android.content.Intent
import android.content.ActivityNotFoundException
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.view.ViewGroup
import android.view.ViewTreeObserver
import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import es.antonborri.home_widget.HomeWidgetLaunchIntent

class MainActivity : FlutterActivity() {
    companion object {
        private val secureExecutor = Executors.newSingleThreadExecutor()
    }

    override fun onNewIntent(intent: Intent) {
        // Android can recreate a killed activity from the task's old MAIN intent
        // and deliver the widget click before Dart subscribes. Keep that newest
        // intent available to initiallyLaunchedFromHomeWidget as well.
        setIntent(intent)
        super.onNewIntent(intent)
    }

    override fun shouldHandleDeeplinking(): Boolean =
        intent?.action != HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION &&
            super.shouldHandleDeeplinking()

    private fun secureCall(result: MethodChannel.Result, operation: () -> Any?) {
        secureExecutor.execute {
            try {
                val value = operation()
                runOnUiThread { result.success(value) }
            } catch (_: Exception) {
                runOnUiThread { result.error("secure", "Secure storage operation failed", null) }
            }
        }
    }
    // 首帧已可上屏（Dart 定妆页画好，或 4s 兜底）；通道回调与绘制线程都会碰
    @Volatile
    private var splashReady = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 压住系统启动屏到 Flutter 首帧真正上屏再放行：A12+ 在首帧一出现时
        // 就撤启动屏，若窗口还没从启动尺寸过渡到全屏，画面会被劈成两截。
        // 只压这一下，无任何额外等待。仅冷启动拦截（recreate 不拦）。
        if (Build.VERSION.SDK_INT >= 31 && savedInstanceState == null) {
            val content = findViewById<ViewGroup>(android.R.id.content)
            content.viewTreeObserver.addOnPreDrawListener(
                object : ViewTreeObserver.OnPreDrawListener {
                    override fun onPreDraw(): Boolean {
                        if (!splashReady) return false
                        content.viewTreeObserver.removeOnPreDrawListener(this)
                        return true
                    }
                },
            )
            // 兜底：Dart 侧异常没发信号时强制放行，不能把启动屏挂死
            Handler(Looper.getMainLooper()).postDelayed({ splashReady = true }, 4000)
        }
    }

    // 凭据加密：AES-256-GCM 密钥存 AndroidKeyStore，密文存独立 prefs
    private fun secretKey(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey("hw_radar_master", null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(
            KeyGenParameterSpec.Builder(
                "hw_radar_master",
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build(),
        )
        return gen.generateKey()
    }

    private fun securePrefs() =
        getSharedPreferences("hw_radar_secure", Context.MODE_PRIVATE)

    private fun secureRead(key: String): String? {
        val raw = securePrefs().getString(key, null) ?: return null
        val data = Base64.decode(raw, Base64.DEFAULT)
        val iv = data.copyOfRange(0, 12)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, iv))
        return String(cipher.doFinal(data.copyOfRange(12, data.size)), Charsets.UTF_8)
    }

    private fun secureWrite(key: String, value: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val iv = cipher.iv
        val enc = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        DurablePreferences.commit(securePrefs().edit()
            .putString(key, Base64.encodeToString(iv + enc, Base64.DEFAULT)))
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "homework_radar/platform")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openNotificationSettings" -> {
                        val channel = call.argument<String>("channelId")
                        if (channel != null && channel !in setOf("homework_due", "class_reminder")) {
                            result.error("channel", "Unknown reminder channel", null)
                        } else {
                            result.success(openNotificationSettings(channel))
                        }
                    }
                    // CookieManager.getCookie 能返回包括 HttpOnly 在内的全部 Cookie
                    "getCookie" -> {
                        val url = call.argument<String>("url") ?: ""
                        result.success(CookieManager.getInstance().getCookie(url))
                    }
                    "clearCookies" -> {
                        CookieManager.getInstance().apply {
                            removeAllCookies(null)
                            flush()
                        }
                        result.success(true)
                    }
                    "clearDomainCookies" -> {
                        val origins = call.argument<List<String>>("origins") ?: emptyList()
                        clearDomainCookies(origins) { result.success(true) }
                    }
                    // 按域回装单条 Cookie：退出任一平台时把其它平台的
                    // 会话备份装回，避免"全清"连坐销毁别的平台登录态
                    "setCookie" -> {
                        val url = call.argument<String>("url") ?: ""
                        val cookie = call.argument<String>("cookie") ?: ""
                        CookieManager.getInstance().apply {
                            setCookie(url, cookie)
                            flush()
                        }
                        result.success(true)
                    }
                    "secureRead" -> {
                        secureCall(result) { secureRead(call.argument<String>("key") ?: "") }
                    }
                    "secureWrite" -> {
                        secureCall(result) {
                            secureWrite(
                                call.argument<String>("key") ?: "",
                                call.argument<String>("value") ?: "",
                            )
                            true
                        }
                    }
                                        // Dart 定妆页已上屏，可以撤系统启动屏了
                    "splashDone" -> {
                        splashReady = true
                        result.success(true)
                    }
                    "secureDelete" -> {
                        secureCall(result) {
                            DurablePreferences.commit(securePrefs().edit()
                                .remove(call.argument<String>("key") ?: ""))
                            true
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun openNotificationSettings(channel: String?): Boolean {
        val intents = mutableListOf<Intent>()
        if (Build.VERSION.SDK_INT >= 26) {
            if (channel != null) intents.add(Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                .putExtra(Settings.EXTRA_CHANNEL_ID, channel))
            intents.add(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
        }
        intents.add(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.parse("package:$packageName")))
        for (destination in intents) {
            try {
                startActivity(destination)
                return true
            } catch (_: ActivityNotFoundException) {
                // Some vendor ROMs omit the channel-level screen.
            } catch (_: SecurityException) {
                // Fall back to the app's notification/details screen.
            }
        }
        return false
    }

    /** Android exposes Cookie headers only. Expire visible names in the selected
     * domain/path scopes; never clear or recreate another platform's cookies. */
    private fun clearDomainCookies(origins: List<String>, done: () -> Unit) {
        val manager = CookieManager.getInstance()
        val removals = linkedSetOf<Pair<String, String>>()
        for (origin in origins) {
            val uri = Uri.parse(origin)
            val host = uri.host ?: continue
            if (uri.scheme != "http" && uri.scheme != "https") continue
            val paths = linkedSetOf("/", "/login", "/sso/", "/jwglxt/", "/zftal-xgxt-web/")
            var path = uri.path ?: "/"
            while (path.length > 1) {
                paths.add(path)
                path = path.substringBeforeLast('/', "")
            }
            val domains = mutableListOf<String>()
            var domain = host
            while (domain.contains('.')) {
                domains.add(domain)
                domain = domain.substringAfter('.')
            }
            for (probePath in paths) {
                val probe = "${uri.scheme}://$host$probePath"
                val names = (manager.getCookie(probe) ?: "").split(';')
                    .map { it.substringBefore('=').trim() }.filter { it.isNotEmpty() }
                for (name in names) {
                    val secure = if (uri.scheme == "https") "; Secure" else ""
                    val expired = "$name=; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=$probePath$secure"
                    removals.add(probe to expired)
                    for (scope in domains) removals.add(probe to "$expired; Domain=$scope")
                }
            }
        }
        // Wait for each native write; reporting success before callbacks races
        // the next login request. Unknown cookie paths remain an API limitation.
        val queue = removals.iterator()
        fun next() {
            if (!queue.hasNext()) { manager.flush(); done(); return }
            val (url, cookie) = queue.next()
            manager.setCookie(url, cookie) { next() }
        }
        next()
    }
}
