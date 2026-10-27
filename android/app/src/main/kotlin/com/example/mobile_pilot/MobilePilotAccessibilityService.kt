package com.example.mobile_pilot

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Path
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.DisplayMetrics
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.inputmethod.InputMethodManager

class MobilePilotAccessibilityService : AccessibilityService() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val floatingControls = FloatingControlsController(
        this, mainHandler, ::performFloatingAction, ::cancelPendingCommands,
    )

    private val sessions = CommandSessionController(mainHandler, ::cancelPendingCommands)
    private val uiTree = UiTreeController(this)
    private val gestures = DeviceGestureController(this)
    private val settingsTest = SettingsTapTestController(this, mainHandler, uiTree)
    private val uiWait = WaitForUiController(this, mainHandler, ScrollGestureController(this, floatingControls))
    private val targetApps = TargetAppController(mainHandler)
    private val screenCapture = ScreenCaptureController(this, mainHandler, ::isLikelyTargetAppPackage)
    private val actionQueue = DeviceActionQueue(
        this, mainHandler, floatingControls, gestures,
    )

    override fun onServiceConnected() {
        super.onServiceConnected()
        activeService = this
        if (isFloatingControlsEnabled()) floatingControls.show()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        screenCapture.onAccessibilityEvent(event)
        actionQueue.onAccessibilityEvent(event)
        settingsTest.onAccessibilityEvent(event)
    }

    override fun onInterrupt() = Unit

    override fun onDestroy() {
        sessions.cancel()
        uiWait.cancel()
        targetApps.cancelWaiting()
        if (activeService === this) activeService = null
        floatingControls.remove()
        settingsTest.dispose()
        actionQueue.dispose()
        screenCapture.cancelExternalScreenCapture()
        super.onDestroy()
    }

    fun isFloatingControlsEnabled(): Boolean = getSharedPreferences(
        FLOATING_CONTROLS_PREFS,
        MODE_PRIVATE,
    ).getBoolean(FLOATING_CONTROLS_ENABLED_KEY, false)

    fun setFloatingControlsEnabled(enabled: Boolean): TapResult {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP_MR1) {
            return TapResult(false, "OVERLAY_UNSUPPORTED", "ปุ่มลอยต้องใช้ Android 5.1 ขึ้นไป")
        }
        getSharedPreferences(FLOATING_CONTROLS_PREFS, MODE_PRIVATE)
            .edit()
            .putBoolean(FLOATING_CONTROLS_ENABLED_KEY, enabled)
            .apply()

        if (!enabled) {
            floatingControls.remove()
            return TapResult(true, "FLOATING_DISABLED", "ปิดปุ่มลอยแล้ว")
        }

        return if (floatingControls.show()) {
            TapResult(true, "FLOATING_ENABLED", "เปิดปุ่มลอยแล้ว แตะ MP เพื่อเปิดแผงคำสั่ง")
        } else {
            getSharedPreferences(FLOATING_CONTROLS_PREFS, MODE_PRIVATE)
                .edit()
                .putBoolean(FLOATING_CONTROLS_ENABLED_KEY, false)
                .apply()
            TapResult(false, "FLOATING_FAILED", "Android เพิ่มปุ่มลอยไม่ได้")
        }
    }

    fun navigateGlobally(action: String): TapResult {
        if (action != "home" && action != "recents") {
            return TapResult(false, "INVALID_ARGUMENT", "ไม่รู้จักคำสั่งนำทาง")
        }
        cancelPendingCommands()
        val response = GlobalNavigationController(this).navigate(action)
        actionQueue.lastPointTapResult = response
        floatingControls.setStatus(response.message)
        return response
    }

    private fun performFloatingAction(action: String) {
        if (uiWait.isScrolling && action != "home" && action != "recents") {
            floatingControls.setStatus("หยุดเลื่อนค้นหาก่อนใช้คำสั่งอื่น")
            return
        }
        if (action == "home" || action == "recents") {
            navigateGlobally(action)
            return
        }
        val root = rootInActiveWindow
        val foregroundPackage = try {
            root?.packageName?.toString()
        } finally {
            root?.recycle()
        }
        if (foregroundPackage.isNullOrBlank() || foregroundPackage == packageName) {
            floatingControls.setStatus("เปิดแอปเป้าหมายก่อน")
            return
        }

        if (action == "back") {
            val accepted = performGlobalAction(GLOBAL_ACTION_BACK)
            actionQueue.lastPointTapResult = if (accepted) {
                TapResult(true, "BACK_DISPATCHED", "Android ส่งคำสั่งย้อนกลับจาก $foregroundPackage แล้ว")
            } else {
                TapResult(false, "BACK_REJECTED", "Android ไม่รับคำสั่งย้อนกลับ")
            }
            floatingControls.setStatus(actionQueue.lastPointTapResult?.message ?: "ย้อนกลับไม่สำเร็จ")
            return
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            floatingControls.setStatus("อุปกรณ์นี้ไม่รองรับ gesture เลื่อน")
            return
        }
        val display = getSystemService(DisplayManager::class.java).getDisplay(Display.DEFAULT_DISPLAY)
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        display?.getRealMetrics(metrics)
        if (display == null || metrics.widthPixels <= 0 || metrics.heightPixels <= 0) {
            floatingControls.setStatus("อ่านขนาดหน้าจอไม่ได้")
            return
        }
        val horizontal = action == "swipe_left" || action == "swipe_right"
        val startX: Float
        val endX: Float
        val startY: Float
        val endY: Float
        if (horizontal) {
            startX = if (action == "swipe_left") metrics.widthPixels * 0.80f else metrics.widthPixels * 0.20f
            endX = if (action == "swipe_left") metrics.widthPixels * 0.20f else metrics.widthPixels * 0.80f
            startY = floatingControls.horizontalSwipeY(metrics.heightPixels)
            endY = startY
        } else {
            startX = floatingControls.scrollGestureX(metrics.widthPixels)
            endX = startX
            startY = if (action == "scroll_up") metrics.heightPixels * 0.30f else metrics.heightPixels * 0.72f
            endY = if (action == "scroll_up") metrics.heightPixels * 0.72f else metrics.heightPixels * 0.30f
        }
        val path = Path().apply {
            moveTo(startX, startY)
            lineTo(endX, endY)
        }
        floatingControls.setStatus("ส่งคำสั่งเลื่อนไปยัง $foregroundPackage")
        val accepted = floatingControls.dispatchGestureAvoidingOverlay(
            GestureDescription.Builder()
                .addStroke(GestureDescription.StrokeDescription(path, 0, 400))
                .build(),
            onCompleted = {
                actionQueue.lastPointTapResult = TapResult(true, "GESTURE_COMPLETED", "Android ส่ง gesture ไปยัง $foregroundPackage แล้ว; โปรดตรวจผลบนหน้าจอ")
                floatingControls.setStatus("ส่ง gesture แล้ว")
            },
            onCancelled = {
                actionQueue.lastPointTapResult = TapResult(false, "GESTURE_CANCELLED", "Android ยกเลิก gesture")
                floatingControls.setStatus("Android ยกเลิก gesture")
            },
        )
        if (!accepted) {
            actionQueue.lastPointTapResult = TapResult(false, "SCROLL_GESTURE_REJECTED", "Android ไม่รับ gesture เลื่อน")
            floatingControls.setStatus("Android ไม่รับ gesture")
        }
    }

    fun cancelPendingCommands() {
        val hadSession = sessions.isRunning
        sessions.cancel()
        uiTree.invalidateSnapshot()
        targetApps.cancelWaiting()
        val hadPendingCommands = hadSession || uiWait.isWaiting || actionQueue.hasPendingActions || settingsTest.isPending || screenCapture.isArmed
        uiWait.cancel()
        actionQueue.cancelPendingActions()
        settingsTest.cancelPending()
        screenCapture.cancelExternalScreenCapture()
        actionQueue.lastPointTapResult = if (hadPendingCommands) {
            TapResult(false, "ACTION_CANCELLED", "ยกเลิกคิวแล้ว คำสั่งที่ส่งให้ Android ก่อนหน้านี้อาจยังทำงานอยู่")
        } else {
            TapResult(true, "NO_PENDING_ACTION", "ไม่มีคำสั่งที่รออยู่")
        }
        floatingControls.setStatus(actionQueue.lastPointTapResult?.message ?: "ยกเลิกแล้ว")
    }

    fun beginSettingsTapTest(target: String, settingsPackage: String): TapResult =
        settingsTest.beginSettingsTapTest(target, settingsPackage)

    fun cancelSettingsTapTest(message: String) = settingsTest.cancelSettingsTapTest(message)

    fun beginCommandSession(id: String, target: String): Boolean {
        if (target == packageName || actionQueue.hasPendingActions || uiWait.isWaiting || screenCapture.isArmed || settingsTest.isPending) return false
        return sessions.begin(id, target)
    }

    fun allowsCommandSession(id: String, target: String?): Boolean = sessions.allows(id, target)
    fun hasCommandSession(): Boolean = sessions.isRunning
    fun finishCommandSession(id: String): Boolean = sessions.finish(id)
    fun cancelCommandSession(id: String) {
        if (sessions.allows(id, null)) cancelPendingCommands()
    }

    fun waitForUi(id: String, target: String, selector: String, value: String, timeoutMs: Long,
                  condition: String, callback: (Map<String, Any?>) -> Unit) =
        uiWait.startCondition(id, target, selector, value, timeoutMs, condition, callback)

    val isScrollingForUi: Boolean get() = uiWait.isScrolling

    fun scrollUntilUi(id: String, target: String, selector: String, value: String, timeoutMs: Long,
                      direction: String, maxScrolls: Int, distance: String, callback: (Map<String, Any?>) -> Unit) {
        if (actionQueue.hasPendingActions || settingsTest.isPending || screenCapture.isArmed) {
            callback(mapOf("code" to "SEQUENCE_BUSY", "message" to "ยกเลิกคำสั่งอื่นที่รออยู่ก่อนเริ่มเลื่อนค้นหา"))
            return
        }
        uiTree.invalidateSnapshot()
        uiWait.startScrollWithDistance(id, target, selector, value, timeoutMs, direction, maxScrolls, distance, callback)
    }

    fun cancelUiWait(id: String) = uiWait.cancel(id)

    fun awaitTargetReady(target: String, callback: (Boolean) -> Unit) =
        targetApps.awaitReady(target, { activeService?.takeIf { it === this } }, callback)

    fun editElementById(screenId: String,nodeId: String,targetPackage: String,action: String,text: String): TapResult =
        uiTree.editElementById(screenId,nodeId,targetPackage,action,text)

    fun tapElementById(screenId: String, nodeId: String, targetPackage: String): TapResult =
        uiTree.tapElementById(screenId, nodeId, targetPackage)

    fun readUiTree(): List<Map<String, Any?>> = uiTree.readUiTree()

    fun readUiTreeForPackage(targetPackage: String?): List<Map<String, Any?>> = uiTree.readUiTreeForPackage(targetPackage)

    fun tapElementForPackage(target: String, targetPackage: String?): TapResult = uiTree.tapElementForPackage(target, targetPackage)

    fun tapElementWithGestureForPackage(target: String, targetPackage: String?, callback: (TapResult) -> Unit) =
        uiTree.tapElementWithGestureForPackage(target, targetPackage, callback)


    fun tapElementByText(target: String): TapResult = uiTree.tapElementByText(target)

    fun tapElementByTextWithGesture(target: String, callback: (TapResult) -> Unit) =
        uiTree.tapElementByTextWithGesture(target, callback)

    fun captureScreen(callback: (ScreenCaptureResult) -> Unit) = screenCapture.captureScreen(callback)

    fun armExternalScreenCapture(targetPackage: String? = null): TapResult = screenCapture.armExternalScreenCapture(targetPackage)

    fun cancelExternalScreenCapture() = screenCapture.cancelExternalScreenCapture()

    fun takeExternalScreenCapture(): ExternalScreenCapture? = screenCapture.takeExternalScreenCapture()

    fun queuePointTap(x: Double, y: Double, width: Int, height: Int, rotation: Int, targetPackage: String): TapResult =
        actionQueue.queuePointTap(x, y, width, height, rotation, targetPackage)

    fun cancelQueuedActions() = actionQueue.cancelPendingActions()

    fun queueDoubleTap(x: Double, y: Double, width: Int, height: Int, rotation: Int, targetPackage: String): TapResult =
        actionQueue.queueDoubleTap(x, y, width, height, rotation, targetPackage)

    fun queueLongPress(x: Double, y: Double, width: Int, height: Int, rotation: Int, targetPackage: String, durationMs: Long): TapResult =
        actionQueue.queueLongPress(x, y, width, height, rotation, targetPackage, durationMs)

    fun queueDrag(x: Double,y: Double,endX: Double,endY: Double,width: Int,height: Int,rotation: Int,
                  targetPackage: String,holdMs: Long,durationMs: Long): TapResult =
        actionQueue.queueDrag(x,y,endX,endY,width,height,rotation,targetPackage,holdMs,durationMs)

    fun queueSwipe(x: Double, y: Double, endX: Double, endY: Double, width: Int, height: Int,
                   rotation: Int, targetPackage: String, durationMs: Long): TapResult =
        actionQueue.queueSwipe(x, y, endX, endY, width, height, rotation, targetPackage, durationMs)

    fun queuePinch(x: Double, y: Double, width: Int, height: Int, rotation: Int, targetPackage: String,
                   durationMs: Long, startSpan: Double, scale: Double, axis: String): TapResult =
        actionQueue.queuePinch(x, y, width, height, rotation, targetPackage, durationMs, startSpan, scale, axis)

    fun getPointTapResult(): TapResult? = actionQueue.getPointTapResult()

    fun queueUtilityAction(
        action: String, targetPackage: String, width: Int, height: Int, rotation: Int, text: String? = null,
    ): TapResult = actionQueue.queueUtilityAction(action, targetPackage, width, height, rotation, text)

    fun getQueuedUtilityTargetPackage(): String? = actionQueue.getQueuedUtilityTargetPackage()

    fun tapNormalizedPoint(
        x: Double, y: Double, screenshotWidth: Int, screenshotHeight: Int, screenshotRotation: Int,
        callback: (TapResult) -> Unit,
    ) = gestures.tapNormalizedPoint(x, y, screenshotWidth, screenshotHeight, screenshotRotation, callback)

    private fun isLikelyTargetAppPackage(candidatePackage: String): Boolean {
        if (candidatePackage == packageName) return false
        if (candidatePackage == "android" || candidatePackage == "com.android.systemui") return false
        val homeIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val homePackage = packageManager.resolveActivity(
            homeIntent,
            PackageManager.MATCH_DEFAULT_ONLY,
        )?.activityInfo?.packageName
        val inputMethodPackages = getSystemService(InputMethodManager::class.java)
            ?.enabledInputMethodList
            ?.mapTo(mutableSetOf()) { it.packageName }
            .orEmpty()
        return candidatePackage != homePackage && candidatePackage !in inputMethodPackages
    }

    data class ScreenCaptureResult(
        val success: Boolean,
        val jpeg: ByteArray?,
        val width: Int,
        val height: Int,
        val rotation: Int,
        val error: String?,
    )

    data class ExternalScreenCapture(
        val capture: ScreenCaptureResult,
        val packageName: String,
    )

    data class TapResult(val success: Boolean, val code: String, val message: String)

    companion object {
        const val SETTINGS_TEST_PREFS = "mobilepilot_settings_test"
        const val FLOATING_CONTROLS_PREFS = "mobilepilot_floating_controls"
        const val FLOATING_CONTROLS_ENABLED_KEY = "enabled"

        @Volatile
        var activeService: MobilePilotAccessibilityService? = null
            private set

        fun takeLastExternalScreenCapture(): ExternalScreenCapture? =
            ScreenCaptureController.takeLastExternalScreenCapture()
    }
}
