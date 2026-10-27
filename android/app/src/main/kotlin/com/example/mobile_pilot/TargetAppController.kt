package com.example.mobile_pilot

import android.accessibilityservice.AccessibilityService
import android.os.Handler
import android.os.SystemClock

/** Waits for a stable foreground root; window events alone are not proof of readiness. */
class TargetAppController(private val handler: Handler) {
    private var generation = 0

    fun cancelWaiting() { generation++ }
    fun awaitReady(
        target: String,
        service: () -> AccessibilityService?,
        callback: (Boolean) -> Unit,
    ) {
        val requestGeneration = generation
        val deadline = SystemClock.elapsedRealtime() + 10_000
        var matchingSince: Long? = null
        val check = object : Runnable {
            override fun run() {
                if (requestGeneration != generation) {
                    callback(false)
                    return
                }
                val currentService = service()
                val root = currentService?.rootInActiveWindow
                val matches = try {
                    target.isNotBlank() && target != currentService?.packageName &&
                        root?.packageName?.toString() == target
                } finally {
                    root?.recycle()
                }
                val now = SystemClock.elapsedRealtime()
                if (matches) {
                    val since = matchingSince ?: now.also { matchingSince = it }
                    if (now - since >= 500) {
                        callback(true)
                        return
                    }
                } else {
                    matchingSince = null
                }
                if (now >= deadline || currentService == null) {
                    callback(false)
                } else {
                    handler.postDelayed(this, 100)
                }
            }
        }
        check.run()
    }
}
