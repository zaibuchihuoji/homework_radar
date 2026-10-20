package com.worknote.homework_radar

import android.app.DownloadManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import androidx.core.app.NotificationCompat
import java.io.File
import java.security.MessageDigest

/** System-owned transfer, with state/cache separate from all user data. Call on UpdateBridge.io. */
internal class AppUpdateDownload(private val context: Context) {
    private val prefs = context.getSharedPreferences("app_update_download", Context.MODE_PRIVATE)
    private val manager = context.getSystemService(DownloadManager::class.java)
    private val notifications = context.getSystemService(NotificationManager::class.java)
    private val cache get() = File(context.filesDir, "updates").apply { mkdirs() }
    private val verified get() = File(cache, "update.apk")
    private val staging get() = File(context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), "app-update.apk")
    private val id get() = prefs.getLong("id", -1)

    fun owns(downloadId: Long) = downloadId != -1L && downloadId == id

    fun start(args: Map<*, *>): Map<String, Any?> {
        val url = args["url"] as? String ?: ""
        val version = args["version"] as? String ?: ""
        val size = (args["size"] as? Number)?.toLong() ?: 0
        val hash = args["sha256"] as? String
        require(UpdatePackagePolicy.allowedUrl(url)) { "更新下载地址无效，请重新检查更新" }
        require(Regex("[0-9]+\\.[0-9]+\\.[0-9]+").matches(version) && size >= 0 &&
            (hash == null || Regex("[a-fA-F0-9]{64}").matches(hash))) { "更新信息不完整，请重新检查更新" }
        val existing = status()
        if (existing["phase"] in setOf("queued", "downloading", "paused", "ready")) return existing
        cancel()
        check(prefs.edit().putString("url", url).putString("version", version)
            .putLong("size", size).putString("sha256", hash).commit()) { "无法保存下载任务" }
        return enqueue()
    }

    private fun enqueue(): Map<String, Any?> {
        staging.delete()
        val request = DownloadManager.Request(Uri.parse(prefs.getString("url", "")))
            .setTitle("作业通 ${prefs.getString("version", "")} 更新")
            .setDescription("正在下载安装包，可在后台继续")
            .setMimeType("application/vnd.android.package-archive")
            .setAllowedOverMetered(true).setAllowedOverRoaming(false)
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
            .setDestinationInExternalFilesDir(context, Environment.DIRECTORY_DOWNLOADS, "app-update.apk")
        val downloadId = manager.enqueue(request)
        if (!prefs.edit().putLong("id", downloadId).remove("error").remove("terminal")
                .remove("readyCode").commit()) {
            manager.remove(downloadId)
            error("无法保存下载任务，请重试")
        }
        return status()
    }

    fun retry(): Map<String, Any?> {
        val current = status()
        if (current["phase"] != "failed") return current
        check(prefs.getBoolean("retryable", true)) { "安装包校验失败，请重新检查更新" }
        val url = prefs.getString("url", "") ?: ""
        require(UpdatePackagePolicy.allowedUrl(url)) { "请重新检查更新" }
        if (id != -1L) manager.remove(id)
        return enqueue()
    }

    fun cancel(): Map<String, Any?> {
        if (id != -1L) manager.remove(id)
        staging.delete()
        cache.listFiles()?.forEach { it.delete() }
        check(prefs.edit().clear().commit()) { "无法清理下载任务" }
        notifications.cancel(NOTIFICATION_ID)
        return mapOf("phase" to "idle")
    }

    fun status(): Map<String, Any?> {
        if (!prefs.contains("url")) return mapOf("phase" to "idle")
        val result = mutableMapOf<String, Any?>("version" to prefs.getString("version", ""),
            "bytes" to 0L, "total" to prefs.getLong("size", 0), "source" to "GitHub")
        if (prefs.contains("readyCode")) {
            if (code(installed()) >= prefs.getLong("readyCode", 0)) return cancel()
            if (!verified.isFile) fail("安装包已被清理，请重新下载", true)
            else return result.apply { put("phase", "ready"); put("bytes", verified.length()); put("total", verified.length()) }
        }
        if (prefs.getBoolean("terminal", false)) return result.apply {
            put("phase", "failed"); put("error", prefs.getString("error", "下载失败，请重试"))
            put("retryable", prefs.getBoolean("retryable", true))
        }
        manager.query(DownloadManager.Query().setFilterById(id))?.use { cursor ->
            if (cursor.moveToFirst()) {
                fun long(name: String) = cursor.getLong(cursor.getColumnIndexOrThrow(name))
                result["bytes"] = long(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)
                val total = long(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)
                if (total > 0) result["total"] = total
                when (long(DownloadManager.COLUMN_STATUS).toInt()) {
                    DownloadManager.STATUS_PENDING -> result["phase"] = "queued"
                    DownloadManager.STATUS_RUNNING -> result["phase"] = "downloading"
                    DownloadManager.STATUS_PAUSED -> {
                        result["phase"] = "paused"
                        result["error"] = "等待网络恢复或系统继续下载"
                    }
                    DownloadManager.STATUS_SUCCESSFUL -> {
                        try {
                            val partial = File(cache, "update.partial")
                            staging.inputStream().use { input -> partial.outputStream().use { input.copyTo(it) } }
                            val metadata = validate(partial)
                            check(partial.renameTo(verified)) { "无法保存已下载的安装包" }
                            check(prefs.edit().putLong("readyCode", metadata.versionCode).commit()) { "无法保存下载状态" }
                            staging.delete()
                            notifyResult(true)
                            return result.apply { put("phase", "ready"); put("bytes", verified.length()); put("total", verified.length()) }
                        } catch (e: Exception) {
                            fail(e.message ?: "安装包校验失败，请重新检查更新", false)
                            notifyResult(false)
                        }
                    }
                    else -> {
                        val reason = long(DownloadManager.COLUMN_REASON).toInt()
                        fail(when (reason) {
                            DownloadManager.ERROR_INSUFFICIENT_SPACE -> "存储空间不足，清理后重试"
                            DownloadManager.ERROR_HTTP_DATA_ERROR, DownloadManager.ERROR_CANNOT_RESUME -> "下载中断，请重试"
                            else -> "下载失败，请检查网络后重试"
                        }, true)
                    }
                }
                if (result.containsKey("phase")) return result
            } else fail("下载任务已被系统清理，请重试", true)
        } ?: fail("无法读取下载任务，请重试", true)
        return result.apply {
            put("phase", "failed"); put("error", prefs.getString("error", "下载失败，请重试"))
            put("retryable", prefs.getBoolean("retryable", true))
        }
    }

    private fun fail(message: String, retryable: Boolean) {
        verified.delete()
        File(cache, "update.partial").delete()
        check(prefs.edit().remove("readyCode").putBoolean("terminal", true)
            .putBoolean("retryable", retryable).putString("error", message).commit())
    }

    @Suppress("DEPRECATION")
    private fun installed(): PackageInfo = context.packageManager.getPackageInfo(context.packageName,
        if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES)

    @Suppress("DEPRECATION")
    private fun code(info: PackageInfo): Long = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()

    @Suppress("DEPRECATION")
    private fun signers(info: PackageInfo): Set<String> =
        (if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures)
            ?.map { signature -> MessageDigest.getInstance("SHA-256").digest(signature.toByteArray())
                .joinToString("") { "%02x".format(it) } }?.toSet() ?: emptySet()

    private fun validate(file: File): UpdatePackagePolicy.Apk {
        check(UpdatePackagePolicy.integrity(file, prefs.getLong("size", 0), prefs.getString("sha256", null))) {
            "安装包不完整或校验不符，请重新检查更新"
        }
        @Suppress("DEPRECATION")
        val archive = context.packageManager.getPackageArchiveInfo(file.path,
            if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES)
            ?: error("安装包无法识别，请重新检查更新")
        val candidate = UpdatePackagePolicy.Apk(archive.packageName, archive.versionName ?: "", code(archive), signers(archive))
        UpdatePackagePolicy.reject(candidate, prefs.getString("version", "") ?: "", context.packageName,
            code(installed()), signers(installed()))?.let { error(it) }
        return candidate
    }

    fun installFile(): File {
        check(status()["phase"] == "ready") { "安装包尚未准备好" }
        try { validate(verified) } catch (e: Exception) {
            fail(e.message ?: "安装包校验失败", false)
            throw e
        }
        return verified
    }

    private fun notifyResult(ready: Boolean) {
        if (Build.VERSION.SDK_INT >= 26) notifications.createNotificationChannel(
            NotificationChannel("app_updates", "应用更新", NotificationManager.IMPORTANCE_DEFAULT))
        val pending = PendingIntent.getActivity(context, 20261020,
            Intent(context, MainActivity::class.java).setAction(UpdateBridge.OPEN_UPDATE)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        try {
            notifications.notify(NOTIFICATION_ID, NotificationCompat.Builder(context, "app_updates")
                .setSmallIcon(R.drawable.ic_update_download).setContentTitle(if (ready) "作业通更新已下载" else "作业通更新未完成")
                .setContentText(if (ready) "点击查看并安装 ${prefs.getString("version", "")}" else "点击查看原因并重试")
                .setContentIntent(pending).setAutoCancel(true).build())
        } catch (_: SecurityException) { /* Notification permission never gates downloads. */ }
    }

    companion object { private const val NOTIFICATION_ID = -20261020 }
}
