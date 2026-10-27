package com.example.mobile_pilot

import android.os.Handler

/** A bounded execution lease. Stop revokes it before cancelling pending tools. */
class CommandSessionController(private val handler: Handler, private val onExpired: () -> Unit) {
    private var activeId: String? = null
    private var target: String? = null
    private var expiry: Runnable? = null
    val isRunning: Boolean get() = activeId != null

    fun begin(id: String, packageName: String): Boolean {
        if (isRunning || id.isBlank() || id.length > 100 || packageName.isBlank()) return false
        activeId = id
        target = packageName
        val timeout = Runnable {
            if (activeId == id) {
                cancel()
                onExpired()
            }
        }
        expiry = timeout
        handler.postDelayed(timeout, 120_000)
        return true
    }

    fun allows(id: String, packageName: String?): Boolean =
        activeId == id && (packageName == null || target == packageName)

    fun finish(id: String): Boolean {
        if (activeId != id) return false
        cancel()
        return true
    }

    fun cancel() {
        activeId = null
        target = null
        expiry?.let(handler::removeCallbacks)
        expiry = null
    }
}
