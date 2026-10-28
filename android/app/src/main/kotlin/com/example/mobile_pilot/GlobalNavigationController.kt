package com.example.mobile_pilot

import android.accessibilityservice.AccessibilityService

class GlobalNavigationController(private val service: AccessibilityService) {
    fun back(target: String): MobilePilotAccessibilityService.TapResult {
        val root = service.rootInActiveWindow ?: return MobilePilotAccessibilityService.TapResult(false, "TARGET_NOT_READY", "No active target window")
        val matches = try { root.packageName?.toString() == target && target != service.packageName } finally { root.recycle() }
        if (!matches) return MobilePilotAccessibilityService.TapResult(false, "TARGET_NOT_READY", "Target app is no longer foreground")
        val accepted = service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK)
        return MobilePilotAccessibilityService.TapResult(accepted, if (accepted) "BACK_DISPATCHED" else "BACK_REJECTED", "Back dispatch result; read UI to verify")
    }

    fun navigate(action: String): MobilePilotAccessibilityService.TapResult {
        val (id, label) = when (action) {
            "home" -> AccessibilityService.GLOBAL_ACTION_HOME to "หน้าหลัก"
            "recents" -> AccessibilityService.GLOBAL_ACTION_RECENTS to "แอปล่าสุด"
            else -> return MobilePilotAccessibilityService.TapResult(false, "INVALID_ARGUMENT", "ไม่รู้จักคำสั่งนำทาง")
        }
        val accepted = service.performGlobalAction(id)
        return MobilePilotAccessibilityService.TapResult(
            accepted,
            if (accepted) "NAVIGATION_DISPATCHED" else "NAVIGATION_REJECTED",
            if (accepted) "Android รับคำสั่ง $label แล้ว; โปรดตรวจหน้าจอ" else "Android ไม่รับคำสั่ง $label",
        )
    }
}
