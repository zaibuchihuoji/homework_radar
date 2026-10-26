package com.worknote.homework_radar

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequest
import androidx.work.WorkManager
import androidx.work.workDataOf

/** Rebuild alarms from local course data, independently of network sync. */
class ReminderRecoveryReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in setOf(
            "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED",
            Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED,
        )) return
        val request = OneTimeWorkRequest.Builder(BackgroundSyncWorker::class.java)
            .setInputData(workDataOf("reason" to "reminders")).build()
        WorkManager.getInstance(context).enqueueUniqueWork(
            "homework-reminder-recovery", ExistingWorkPolicy.REPLACE, request,
        )
    }
}
