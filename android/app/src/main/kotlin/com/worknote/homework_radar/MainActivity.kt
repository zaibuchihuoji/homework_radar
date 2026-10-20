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
import android.view.ViewGroup
import android.view.ViewTreeObserver
import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import es.antonborri.home_widget.HomeWidgetLaunchIntent

class MainActivity : FlutterActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine = SyncRuntimeHost.engine(context)
    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onResume() {
        super.onResume()
        UpdateBridge.attach(this)
        SyncRuntimeHost.foreground(true)
    }
    override fun onPause() {
        SyncRuntimeHost.foreground(false)
        UpdateBridge.detach(this)
        super.onPause()
    }
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        super.cleanUpFlutterEngine(flutterEngine)
        SyncRuntimeHost.restorePlatformBridge(this)
    }

    override fun onNewIntent(intent: Intent) {
        // Android can recreate a killed activity from the task's old MAIN intent
        // and deliver the widget click before Dart subscribes. Keep that newest
        // intent available to initiallyLaunchedFromHomeWidget as well.
        setIntent(intent)
        super.onNewIntent(intent)
        UpdateBridge.handleIntent(intent)
    }

    override fun shouldHandleDeeplinking(): Boolean =
        intent?.action != HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION &&
            super.shouldHandleDeeplinking()

    // 首帧已可上屏（Dart 定妆页画好，或 4s 兜底）；通道回调与绘制线程都会碰
    @Volatile
    private var splashReady = false

    override fun onCreate(savedInstanceState: Bundle?) {
        val retainedUi = SyncRuntimeHost.hasUi
        super.onCreate(savedInstanceState)
        UpdateBridge.handleIntent(intent)
        // A retained Dart navigator does not read initial intents a second time.
        // Deliver fresh clicks to the existing plugin listeners when Activity was
        // finished and recreated, without replaying history/configuration intents.
        if (retainedUi && savedInstanceState == null &&
            intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY == 0 &&
            intent.action in setOf(HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION, "SELECT_NOTIFICATION")) {
            flutterEngine?.activityControlSurface?.onNewIntent(intent)
        }
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // The application engine registered plugins once, before Dart started.
        val secure = SecureCredentialStore(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "homework_radar/platform")
            .setMethodCallHandler { call, result ->
                if (secure.handle(call, result)) return@setMethodCallHandler
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
                    "splashDone" -> {
                        SyncRuntimeHost.hasUi = true
                        splashReady = true
                        result.success(true)
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
