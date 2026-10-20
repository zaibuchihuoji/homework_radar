package com.worknote.homework_radar

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal class SecureCredentialStore(private val context: Context) {
    companion object { private val executor = Executors.newSingleThreadExecutor() }
    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        if (call.method !in setOf("secureRead", "secureWrite", "secureDelete")) return false
        executor.execute {
            try {
                val key = call.argument<String>("key") ?: ""
                val value: Any? = when (call.method) {
                    "secureRead" -> secureRead(key)
                    "secureWrite" -> { secureWrite(key, call.argument<String>("value") ?: ""); true }
                    else -> { DurablePreferences.commit(securePrefs().edit().remove(key)); true }
                }
                Handler(Looper.getMainLooper()).post { result.success(value) }
            } catch (_: Exception) {
                Handler(Looper.getMainLooper()).post { result.error("secure", "Secure storage operation failed", null) }
            }
        }
        return true
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
        context.getSharedPreferences("hw_radar_secure", Context.MODE_PRIVATE)

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

}
