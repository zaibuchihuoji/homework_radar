package com.worknote.homework_radar

import java.io.File
import java.net.URI
import java.security.MessageDigest

internal object UpdatePackagePolicy {
    data class Apk(val packageName: String, val versionName: String, val versionCode: Long, val signers: Set<String>)

    fun allowedUrl(url: String): Boolean = try {
        val uri = URI(url)
        uri.scheme == "https" && uri.host == "github.com" &&
            uri.rawUserInfo == null && uri.rawFragment == null && uri.rawQuery == null &&
            uri.port in setOf(-1, 443) &&
            Regex("/zaibuchihuoji/homework_radar/releases/download/v?[0-9]+\\.[0-9]+\\.[0-9]+/app-(?:(?:arm64-v8a|armeabi-v7a|x86_64)-)?release\\.apk").matches(uri.rawPath)
    } catch (_: Exception) { false }

    fun reject(candidate: Apk, expectedVersion: String, currentPackage: String, currentCode: Long, currentSigners: Set<String>): String? = when {
        candidate.packageName != currentPackage -> "安装包不属于作业通"
        candidate.versionName != expectedVersion -> "安装包版本与更新信息不一致"
        candidate.versionCode <= currentCode -> "该版本已安装或版本过旧，请重新检查更新"
        currentSigners.isEmpty() || candidate.signers != currentSigners -> "安装包签名不一致，已阻止安装"
        else -> null
    }

    fun integrity(file: File, expectedSize: Long, sha256: String?): Boolean {
        if (!file.isFile || file.length() <= 0 || (expectedSize > 0 && file.length() != expectedSize)) return false
        if (sha256 == null) return true
        if (!Regex("[a-fA-F0-9]{64}").matches(sha256)) return false
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(65536)
            while (true) { val count = input.read(buffer); if (count < 0) break; digest.update(buffer, 0, count) }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }.equals(sha256, ignoreCase = true)
    }
}
