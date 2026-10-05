package com.worknote.homework_radar

import android.content.Context
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
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
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
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
        securePrefs().edit()
            .putString(key, Base64.encodeToString(iv + enc, Base64.DEFAULT))
            .apply()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "homework_radar/platform")
            .setMethodCallHandler { call, result ->
                when (call.method) {
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
                        try {
                            result.success(secureRead(call.argument<String>("key") ?: ""))
                        } catch (e: Exception) {
                            result.error("secure", e.message, null)
                        }
                    }
                    "secureWrite" -> {
                        try {
                            secureWrite(
                                call.argument<String>("key") ?: "",
                                call.argument<String>("value") ?: "",
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("secure", e.message, null)
                        }
                    }
                                        // Dart 定妆页已上屏，可以撤系统启动屏了
                    "splashDone" -> {
                        splashReady = true
                        result.success(true)
                    }
                    "secureDelete" -> {
                        securePrefs().edit()
                            .remove(call.argument<String>("key") ?: "").apply()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
