package com.worknote.homework_radar

import org.junit.Assert.*
import org.junit.Test

class UpdatePackagePolicyTest {
    private val good = UpdatePackagePolicy.Apk("com.worknote.homework_radar", "1.2.0", 6, setOf("trusted"))
    @Test fun onlyCompatibleForwardUpgradePasses() {
        assertNull(UpdatePackagePolicy.reject(good, "1.2.0", "com.worknote.homework_radar", 5, setOf("trusted")))
        for (candidate in listOf(good.copy(packageName = "other.app"), good.copy(versionCode = 5),
            good.copy(versionName = "9.0.0"), good.copy(signers = setOf("other")))) {
            assertNotNull(UpdatePackagePolicy.reject(candidate, "1.2.0", "com.worknote.homework_radar", 5, setOf("trusted")))
        }
    }
    @Test fun sourceMustBeOwnedHttpsReleaseAsset() {
        assertTrue(UpdatePackagePolicy.allowedUrl("https://github.com/zaibuchihuoji/homework_radar/releases/download/v1.2.0/app-arm64-v8a-release.apk"))
        for (url in listOf("http://github.com/zaibuchihuoji/homework_radar/releases/download/v1/a.apk",
            "https://github.com/other/repo/releases/download/v1/a.apk", "https://github.com.evil.example/a.apk",
            "https://user:pass@github.com/zaibuchihuoji/homework_radar/releases/download/v1/a.apk")) {
            assertFalse(UpdatePackagePolicy.allowedUrl(url))
        }
    }
    @Test fun truncatedAndCorruptedDownloadsFailIntegrity() {
        val file = kotlin.io.path.createTempFile().toFile()
        try {
            file.writeText("abc")
            val hash = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
            assertTrue(UpdatePackagePolicy.integrity(file, 3, hash))
            assertFalse(UpdatePackagePolicy.integrity(file, 4, hash))
            file.writeText("abd")
            assertFalse(UpdatePackagePolicy.integrity(file, 3, hash))
        } finally { file.delete() }
    }
}
