package com.worknote.homework_radar

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.app.DownloadManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference
import java.util.concurrent.Executors

internal object UpdateBridge {
    const val OPEN_UPDATE = "com.worknote.homework_radar.OPEN_UPDATE"
    val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var activity = WeakReference<Activity>(null)
    private var channel: MethodChannel? = null
    private var pendingOpen = false
    private var awaitingPermission = false

    fun register(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        channel = MethodChannel(messenger, "homework_radar/updater").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "device" -> result.success(Build.SUPPORTED_ABIS.toList())
                    "consumeOpen" -> { val value = pendingOpen; pendingOpen = false; result.success(value) }
                    "install" -> install(app, result)
                    else -> io.execute {
                        try {
                            val download = AppUpdateDownload(app)
                            val value = when (call.method) {
                                "status" -> download.status()
                                "start" -> download.start(call.arguments as? Map<*, *> ?: emptyMap<String, Any>())
                                "retry" -> download.retry()
                                "cancel" -> download.cancel()
                                else -> null
                            }
                            main.post { if (value == null) result.notImplemented() else result.success(value) }
                        } catch (e: Exception) {
                            main.post { result.error("update", e.message ?: "更新操作失败，请重试", null) }
                        }
                    }
                }
            }
        }
    }

    fun attach(value: Activity) {
        activity = WeakReference(value)
        if (awaitingPermission) {
            awaitingPermission = false
            if (Build.VERSION.SDK_INT < 26 || value.packageManager.canRequestPackageInstalls()) install(value.applicationContext, null)
        }
    }
    fun detach(value: Activity) { if (activity.get() === value) activity.clear() }
    fun handleIntent(intent: Intent?) {
        if (intent?.action != OPEN_UPDATE) return
        // Consume the intent once so a rotation/history launch cannot reopen the dialog.
        intent.action = Intent.ACTION_MAIN
        pendingOpen = true
        channel?.invokeMethod("open", null)
    }

    private fun install(app: Context, result: MethodChannel.Result?) {
        val host = activity.get()
        if (host == null) { result?.error("update", "请回到 App 后安装", null); return }
        if (Build.VERSION.SDK_INT >= 26 && !host.packageManager.canRequestPackageInstalls()) {
            try {
                awaitingPermission = true
                host.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${app.packageName}")))
                result?.success("permission")
            } catch (_: Exception) {
                awaitingPermission = false
                result?.error("update", "请在系统设置中允许作业通安装应用", null)
            }
            return
        }
        io.execute {
            try {
                val file = AppUpdateDownload(app).installFile()
                main.post {
                    try {
                        val current = activity.get() ?: error("请回到 App 后安装")
                        val uri = FileProvider.getUriForFile(app, "${app.packageName}.updates.fileprovider", file)
                        current.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                        result?.success("installer")
                    } catch (e: Exception) { result?.error("update", e.message ?: "无法打开安装器", null) }
                }
            } catch (e: Exception) {
                main.post {
                    channel?.invokeMethod("refresh", null)
                    result?.error("update", e.message ?: "安装包校验失败", null)
                }
            }
        }
    }
}

class UpdateDownloadReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == DownloadManager.ACTION_NOTIFICATION_CLICKED) {
            val ids = intent.getLongArrayExtra(DownloadManager.EXTRA_NOTIFICATION_CLICK_DOWNLOAD_IDS) ?: return
            val download = AppUpdateDownload(context.applicationContext)
            if (ids.any { download.owns(it) }) {
                // DownloadProvider explicitly allows this user-initiated activity
                // start. Open progress only; installing always needs another tap.
                try {
                    context.startActivity(Intent(context, MainActivity::class.java)
                        .setAction(UpdateBridge.OPEN_UPDATE)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP))
                } catch (_: Exception) { /* Settings still exposes the same task. */ }
            }
            return
        }
        if (intent.action != DownloadManager.ACTION_DOWNLOAD_COMPLETE) return
        val id = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1)
        val pending = goAsync()
        UpdateBridge.io.execute {
            try {
                val download = AppUpdateDownload(context.applicationContext)
                if (download.owns(id)) download.status()
            } catch (_: Exception) {
                // The persisted task is recoverable when the user returns.
                // Never crash a cold process on a receiver/storage failure.
            } finally { pending.finish() }
        }
    }
}
