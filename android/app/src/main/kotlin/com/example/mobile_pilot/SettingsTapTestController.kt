package com.example.mobile_pilot

import android.accessibilityservice.AccessibilityService
import android.content.Context.MODE_PRIVATE
import android.os.Handler
import android.view.accessibility.AccessibilityEvent
import com.example.mobile_pilot.MobilePilotAccessibilityService.Companion.SETTINGS_TEST_PREFS
import com.example.mobile_pilot.MobilePilotAccessibilityService.TapResult

class SettingsTapTestController(
    private val service: AccessibilityService,
    private val mainHandler: Handler,
    private val uiTree: UiTreeController,
) {
    private var settingsTestTarget: String? = null
    private var settingsTestPackage: String? = null
    private var settingsTestPhase: String? = null
    private var settingsTestBeforeTree: String? = null
    private var settingsTestTimeout: Runnable? = null

    val isPending: Boolean get() = settingsTestTarget != null

    fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val target = settingsTestTarget ?: return
        if (event?.packageName?.toString() != settingsTestPackage) return
        if (settingsTestPhase == "tapping") return
        val settingsRoot = service.rootInActiveWindow
        val settingsIsForeground = try {
            settingsRoot?.packageName?.toString() == settingsTestPackage
        } finally {
            settingsRoot?.recycle()
        }
        if (!settingsIsForeground) return

        val currentTree = uiTree.readUiTree()
        val currentSignature = currentTree.toString()
        if (settingsTestPhase == "verifying") {
            if (currentSignature != settingsTestBeforeTree) {
                finishSettingsTapTest(
                    "verified",
                    "แตะ '$target' ใน Settings แล้วและ UI tree เปลี่ยน",
                )
            }
            return
        }
        if (settingsTestPhase != "waiting_for_target" || currentTree.isEmpty()) return

        settingsTestBeforeTree = currentSignature
        settingsTestPhase = "tapping"
        val tapResult = uiTree.tapElementByText(target)
        if (tapResult.success) {
            settingsTestPhase = "verifying"
            saveSettingsTapTestResult("running", tapResult.message)
            scheduleSettingsTestTimeout(
                5000,
                "dispatched_unverified",
                "Android รับคำสั่งแตะแล้ว แต่ UI tree ใน Settings ไม่เปลี่ยน",
            )
        } else if (tapResult.code == "TARGET_NOT_FOUND") {
            settingsTestPhase = "waiting_for_target"
        } else {
            finishSettingsTapTest(tapResult.code.lowercase(), tapResult.message)
        }
    }

    fun beginSettingsTapTest(target: String, settingsPackage: String): TapResult {
        val normalizedTarget = target.trim()
        if (normalizedTarget.isEmpty()) {
            return TapResult(false, "EMPTY_TARGET", "ใส่ข้อความเป้าหมายที่เห็นใน Settings ก่อน")
        }
        if (settingsTestTarget != null) {
            return TapResult(false, "TEST_IN_PROGRESS", "มีการทดสอบ Settings กำลังทำงานอยู่")
        }

        settingsTestTarget = normalizedTarget
        settingsTestPackage = settingsPackage
        settingsTestPhase = "waiting_for_target"
        settingsTestBeforeTree = null
        saveSettingsTapTestResult("waiting", "เปิด Settings แล้ว รอข้อความ '$normalizedTarget'")
        scheduleSettingsTestTimeout(
            20000,
            "target_not_found",
            "ไม่พบเป้าหมายใน Settings ภายในเวลาที่กำหนด",
        )
        return TapResult(true, "WAITING_FOR_SETTINGS", "กำลังรอหน้า Settings")
    }

    fun cancelSettingsTapTest(message: String) {
        finishSettingsTapTest("failed", message)
    }

    private fun scheduleSettingsTestTimeout(delayMillis: Long, status: String, message: String) {
        settingsTestTimeout?.let(mainHandler::removeCallbacks)
        val timeout = Runnable {
            if (settingsTestTarget != null) finishSettingsTapTest(status, message)
        }
        settingsTestTimeout = timeout
        mainHandler.postDelayed(timeout, delayMillis)
    }

    private fun finishSettingsTapTest(status: String, message: String) {
        val target = settingsTestTarget
        settingsTestTimeout?.let(mainHandler::removeCallbacks)
        settingsTestTimeout = null
        settingsTestTarget = null
        settingsTestPackage = null
        settingsTestPhase = null
        settingsTestBeforeTree = null
        saveSettingsTapTestResult(status, message, target)
    }

    private fun saveSettingsTapTestResult(
        status: String,
        message: String,
        target: String? = settingsTestTarget,
    ) {
        service.getSharedPreferences(SETTINGS_TEST_PREFS, MODE_PRIVATE)
            .edit()
            .putString("status", status)
            .putString("message", message)
            .putString("target", target)
            .apply()
    }

    fun cancelPending() {
        if (settingsTestTarget != null) {
            finishSettingsTapTest("cancelled", "ยกเลิกการทดสอบแตะ Settings แล้ว")
        }
    }

    fun dispose() {
        settingsTestTimeout?.let(mainHandler::removeCallbacks)
    }
}
