package com.worknote.homework_radar

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** One engine for the UI and jobs: no competing preference caches/transactions. */
internal object SyncRuntimeHost {
    private var runtime: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var ready = false
    private var inForeground = false
    var hasUi = false
    private val pending = mutableListOf<() -> Unit>()
    private val scheduling = Executors.newSingleThreadExecutor()

    fun engine(context: Context): FlutterEngine {
        check(Looper.myLooper() == Looper.getMainLooper())
        runtime?.let { return it }
        val app = context.applicationContext
        val engine = FlutterEngine(app)
        runtime = engine
        UpdateBridge.register(app, engine.dartExecutor.binaryMessenger)
        ClassReminderCapabilities.register(app, engine.dartExecutor.binaryMessenger)
        restorePlatformBridge(app)
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "homework_radar/background_sync").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "ready" -> {
                        ready = true
                        result.success(inForeground)
                        val queued = pending.toList()
                        pending.clear()
                        queued.forEach { it() }
                    }
                    "configure" -> {
                        try {
                            val operations = SyncScheduler.configure(app,
                                call.argument<Boolean>("enabled") == true,
                                call.argument<Int>("minutes") ?: 30,
                                call.argument<Number>("retryAt")?.toLong(),
                                call.argument<Boolean>("scheduleLocalReminders") != false)
                            // A returned enqueue Operation is not yet durable.
                            // Report database/scheduler failures back to Dart.
                            scheduling.execute {
                                try {
                                    operations.forEach { it.result.get(30, TimeUnit.SECONDS) }
                                    Handler(Looper.getMainLooper()).post { result.success(true) }
                                } catch (_: Exception) {
                                    Handler(Looper.getMainLooper()).post {
                                        result.error("schedule", "无法保存后台同步任务，请稍后重试", null)
                                    }
                                }
                            }
                        } catch (_: Exception) {
                            result.error("schedule", "无法安排后台同步，请稍后重试", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        return engine
    }

    fun restorePlatformBridge(context: Context) {
        val engine = runtime ?: return
        val secure = SecureCredentialStore(context.applicationContext)
        MethodChannel(engine.dartExecutor.binaryMessenger, "homework_radar/platform").setMethodCallHandler { call, result ->
            if (!secure.handle(call, result)) {
                if (call.method == "splashDone") {
                    hasUi = true
                    result.success(true)
                } else result.notImplemented()
            }
        }
    }

    fun foreground(value: Boolean) {
        inForeground = value
        if (ready) channel?.invokeMethod("foreground", value)
    }

    fun run(context: Context, reason: String, stopped: () -> Boolean, done: (Boolean) -> Unit) {
        Handler(Looper.getMainLooper()).post {
            try {
                engine(context)
                val dispatch: () -> Unit = {
                    if (stopped()) done(false)
                    else channel!!.invokeMethod("run", reason, object : MethodChannel.Result {
                        override fun success(result: Any?) = done(result == true)
                        override fun error(code: String, message: String?, details: Any?) = done(false)
                        override fun notImplemented() = done(false)
                    })
                }
                if (ready) dispatch() else pending.add(dispatch)
            } catch (_: Exception) { done(false) }
        }
    }
}
