package com.worknote.homework_radar

import android.content.Context
import androidx.work.*
import java.util.concurrent.TimeUnit

internal object SyncScheduler {
    private const val PERIODIC = "homework-platform-sync"
    private const val RETRY = "homework-platform-sync-retry"
    fun configure(context: Context, enabled: Boolean, minutes: Int, retryAt: Long?): List<Operation> {
        require(minutes in setOf(15, 30, 60, 120))
        val manager = WorkManager.getInstance(context)
        val prefs = context.getSharedPreferences("sync_scheduler", Context.MODE_PRIVATE)
        val operations = mutableListOf<Operation>()
        if (!enabled) {
            operations.add(manager.cancelUniqueWork(PERIODIC))
            operations.add(manager.cancelUniqueWork(RETRY))
            DurablePreferences.commit(prefs.edit().clear())
            return operations
        }
        val constraints = Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()
        val periodic = PeriodicWorkRequest.Builder(BackgroundSyncWorker::class.java, minutes.toLong(), TimeUnit.MINUTES)
            .setConstraints(constraints)
            .setInitialDelay(minutes.toLong(), TimeUnit.MINUTES)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 5, TimeUnit.MINUTES)
            .addTag(PERIODIC).build()
        // KEEP preserves the existing next run across every foreground opening.
        // Replace only on an actual interval change (also works on WorkManager 2.7).
        val policy = if (prefs.getInt("minutes", 0) == minutes) ExistingPeriodicWorkPolicy.KEEP else ExistingPeriodicWorkPolicy.REPLACE
        operations.add(manager.enqueueUniquePeriodicWork(PERIODIC, policy, periodic))
        if (retryAt == null) {
            operations.add(manager.cancelUniqueWork(RETRY))
        } else {
            val retry = OneTimeWorkRequest.Builder(BackgroundSyncWorker::class.java)
                .setInputData(workDataOf("reason" to "retry"))
                .setConstraints(constraints)
                .setInitialDelay((retryAt - System.currentTimeMillis()).coerceAtLeast(0), TimeUnit.MILLISECONDS)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 5, TimeUnit.MINUTES)
                .addTag(RETRY).build()
            val same = prefs.getLong("retryAt", -1) == retryAt
            operations.add(manager.enqueueUniqueWork(RETRY, if (same) ExistingWorkPolicy.KEEP else ExistingWorkPolicy.REPLACE, retry))
        }
        DurablePreferences.commit(prefs.edit().putInt("minutes", minutes).apply {
            if (retryAt == null) remove("retryAt") else putLong("retryAt", retryAt)
        })
        return operations
    }
}
