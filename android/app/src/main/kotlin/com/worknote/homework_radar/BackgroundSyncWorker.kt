package com.worknote.homework_radar

import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** OS-owned persistent job. Never starts an Activity or a permission prompt. */
class BackgroundSyncWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val finished = CountDownLatch(1)
        var success = false
        SyncRuntimeHost.run(applicationContext, inputData.getString("reason") ?: "periodic", { isStopped }) {
            success = it
            finished.countDown()
        }
        return try {
            if (finished.await(8, TimeUnit.MINUTES) && success) Result.success() else Result.retry()
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
            Result.retry()
        }
    }
}
