package com.example.mobile_pilot

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_BACK
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.os.Bundle
import android.os.Handler
import android.os.SystemClock
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import com.example.mobile_pilot.MobilePilotAccessibilityService.TapResult

class DeviceActionQueue(
    private val service: AccessibilityService,
    private val mainHandler: Handler,
    private val floatingControls: FloatingControlsController,
    private val gestures: DeviceGestureController,
    private val isLikelyTargetAppPackage: (String) -> Boolean,
) {
    private var pendingPointTap: PendingPointTap? = null
    private var pendingPointTapTimeout: Runnable? = null
    private var pendingPointTapDispatchTimeout: Runnable? = null
    private var pendingUtilityAction: PendingUtilityAction? = null
    private var utilityActionTimeout: Runnable? = null
    private var utilityActionDispatchTimeout: Runnable? = null
    private var autoSwitchingForUtilityAction = false
    private var lastExternalForegroundPackage: String? = null
    private var lastExternalForegroundAt: Long = 0L

    fun trackForeground(event: AccessibilityEvent?) {
        val eventPackage = event?.packageName?.toString()
        if (event?.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            !eventPackage.isNullOrBlank() && eventPackage != service.packageName
        ) {
            if (isLikelyTargetAppPackage(eventPackage)) {
                lastExternalForegroundPackage = eventPackage
                lastExternalForegroundAt = SystemClock.elapsedRealtime()
            }
        }
    }

    fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val eventPackage = event?.packageName?.toString()
        if (event?.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            val pendingTap = pendingPointTap
            if (pendingTap != null) {
                if (pendingTap.targetPackage == eventPackage) {
                    schedulePointTapAfterForegroundSettles(pendingTap)
                } else {
                    if (eventPackage == service.packageName) {
                        val activeRoot = service.rootInActiveWindow
                        val activePackage = try {
                            activeRoot?.packageName?.toString()
                        } finally {
                            activeRoot?.recycle()
                        }
                        // Overlay/outgoing-window events can name MobilePilot while the target is active.
                        if (activePackage != pendingTap.targetPackage) {
                            clearPendingPointTap(
                                TapResult(false, "TAP_CANCELLED", "MobilePilot กลับมาอยู่ด้านหน้าก่อนส่งคำสั่งแตะ จึงยกเลิกเพื่อป้องกันแตะผิดแอป"),
                            )
                        }
                    } else {
                        pendingPointTapDispatchTimeout?.let(mainHandler::removeCallbacks)
                        pendingPointTapDispatchTimeout = null
                    }
                }
            }

            val utilityAction = pendingUtilityAction
            if (utilityAction != null) {
                if (utilityAction.targetPackage == eventPackage) {
                    autoSwitchingForUtilityAction = false
                    scheduleUtilityActionAfterForegroundSettles(utilityAction)
                } else if (eventPackage != null) {
                    if (eventPackage == service.packageName) {
                        val activeRoot = service.rootInActiveWindow
                        val activePackage = try {
                            activeRoot?.packageName?.toString()
                        } finally {
                            activeRoot?.recycle()
                        }
                        if (activePackage == utilityAction.targetPackage || autoSwitchingForUtilityAction) {
                            // Ignore MobilePilot's outgoing window while the target becomes active.
                        } else {
                            utilityActionDispatchTimeout?.let(mainHandler::removeCallbacks)
                            utilityActionDispatchTimeout = null
                            clearUtilityAction(
                                TapResult(false, "ACTION_CANCELLED", "ยกเลิกคำสั่ง เพราะ MobilePilot กลับมาอยู่ด้านหน้าก่อนคำสั่งทำงาน"),
                            )
                        }
                    } else {
                        utilityActionDispatchTimeout?.let(mainHandler::removeCallbacks)
                        utilityActionDispatchTimeout = null
                    }
                }
            }
        }

        if (event?.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) {
            val utilityAction = pendingUtilityAction
            if (utilityAction != null) {
                val activeRoot = service.rootInActiveWindow
                val activePackage = try {
                    activeRoot?.packageName?.toString()
                } finally {
                    activeRoot?.recycle()
                }
                if (activePackage == utilityAction.targetPackage) {
                    autoSwitchingForUtilityAction = false
                    scheduleUtilityActionAfterForegroundSettles(utilityAction)
                }
            }
        }

    }

    val hasPendingActions: Boolean get() = pendingPointTap != null || pendingUtilityAction != null

    fun cancelPendingActions() {
        if (pendingPointTap != null) {
            clearPendingPointTap(TapResult(false, "TAP_CANCELLED", "ยกเลิกคำสั่งแตะที่รออยู่แล้ว"))
        }
        if (pendingUtilityAction != null) {
            clearUtilityAction(TapResult(false, "ACTION_CANCELLED", "ยกเลิกคำสั่งที่รออยู่แล้ว"))
        }
    }

    fun dispose() {
        pendingPointTapTimeout?.let(mainHandler::removeCallbacks)
        pendingPointTapDispatchTimeout?.let(mainHandler::removeCallbacks)
        utilityActionTimeout?.let(mainHandler::removeCallbacks)
        utilityActionDispatchTimeout?.let(mainHandler::removeCallbacks)
    }

    fun queuePointTap(
        x: Double,
        y: Double,
        width: Int,
        height: Int,
        rotation: Int,
        targetPackage: String,
    ): TapResult {
        if (!x.isFinite() || !y.isFinite() || x !in 0.0..1.0 || y !in 0.0..1.0) {
            return TapResult(false, "INVALID_COORDINATE", "Normalized coordinates must be between 0 and 1.")
        }
        if (targetPackage.isBlank() || targetPackage == service.packageName) {
            return TapResult(false, "INVALID_TARGET", "Capture a screen from another app before queuing a tap.")
        }
        if (pendingUtilityAction != null) {
            return TapResult(false, "ACTION_IN_PROGRESS", "รอให้คำสั่งก่อนหน้าจบหรือหมดอายุก่อน")
        }
        pendingPointTap = PendingPointTap(x, y, width, height, rotation, targetPackage)
        pendingPointTapTimeout?.let(mainHandler::removeCallbacks)
        pendingPointTapDispatchTimeout?.let(mainHandler::removeCallbacks)
        pendingPointTapDispatchTimeout = null
        val timeout = Runnable {
            if (pendingPointTap?.targetPackage == targetPackage) {
                pendingPointTap = null
                pendingPointTapDispatchTimeout = null
                lastPointTapResult = TapResult(false, "TAP_EXPIRED", "คำสั่งแตะหมดอายุหลัง 60 วินาที")
            }
            pendingPointTapTimeout = null
        }
        pendingPointTapTimeout = timeout
        mainHandler.postDelayed(timeout, 60_000)
        lastPointTapResult = TapResult(true, "TAP_QUEUED", "เข้าคิวแตะแล้ว สลับกลับไปแอปเป้าหมายและรอให้หน้าแอปนิ่งก่อน")
        return lastPointTapResult!!
    }

    fun getPointTapResult(): TapResult? = lastPointTapResult

    fun queueUtilityAction(
        action: String,
        targetPackage: String,
        width: Int,
        height: Int,
        rotation: Int,
        text: String? = null,
    ): TapResult {
        val type = when (action) {
            "scroll_up" -> UtilityActionType.SCROLL_UP
            "scroll_down" -> UtilityActionType.SCROLL_DOWN
            "swipe_left" -> UtilityActionType.SWIPE_LEFT
            "swipe_right" -> UtilityActionType.SWIPE_RIGHT
            "back" -> UtilityActionType.BACK
            "type_text" -> UtilityActionType.TYPE_TEXT
            else -> return TapResult(false, "UNKNOWN_ACTION", "ไม่รู้จักคำสั่งนี้")
        }
        if (targetPackage.isBlank() || targetPackage == service.packageName || width <= 0 || height <= 0) {
            return TapResult(false, "INVALID_TARGET", "จับภาพจากแอปเป้าหมายก่อน แล้วลองอีกครั้ง")
        }
        if (type == UtilityActionType.TYPE_TEXT && (text.isNullOrEmpty() || text.length > 2000)) {
            return TapResult(false, "INVALID_TEXT", "ข้อความต้องมี 1 ถึง 2,000 ตัวอักษร")
        }
        if (pendingPointTap != null || pendingUtilityAction != null) {
            return TapResult(false, "ACTION_IN_PROGRESS", "รอให้คำสั่งก่อนหน้าจบหรือหมดอายุก่อน")
        }

        val recentExternalPackage = lastExternalForegroundPackage
            ?.takeIf { SystemClock.elapsedRealtime() - lastExternalForegroundAt <= RECENT_EXTERNAL_PACKAGE_MAX_AGE_MS }
        val executionTargetPackage = if (type == UtilityActionType.TYPE_TEXT &&
            !recentExternalPackage.isNullOrBlank() && recentExternalPackage != service.packageName
        ) {
            recentExternalPackage
        } else {
            targetPackage
        }
        val actionRequest = PendingUtilityAction(type, executionTargetPackage, width, height, rotation, text)
        pendingUtilityAction = actionRequest
        val targetDescription = if (type == UtilityActionType.TYPE_TEXT && executionTargetPackage != targetPackage) {
            "แอปล่าสุดที่กลับมา ($executionTargetPackage)"
        } else {
            "แอปเป้าหมาย ($executionTargetPackage)"
        }
        lastPointTapResult = TapResult(true, "ACTION_QUEUED", "เข้าคิวแล้ว กำลังสลับไป$targetDescription")
        val timeout = Runnable {
            if (pendingUtilityAction === actionRequest) {
                pendingUtilityAction = null
                utilityActionDispatchTimeout = null
                autoSwitchingForUtilityAction = false
                lastPointTapResult = TapResult(false, "ACTION_EXPIRED", "คำสั่งหมดอายุหลัง 60 วินาที")
            }
            utilityActionTimeout = null
        }
        utilityActionTimeout = timeout
        mainHandler.postDelayed(timeout, 60_000)
        autoSwitchingForUtilityAction = true
        return lastPointTapResult!!
    }

    fun getQueuedUtilityTargetPackage(): String? = pendingUtilityAction?.targetPackage

    fun failQueuedUtilityActionToLaunch(): TapResult {
        if (pendingUtilityAction == null) {
            return TapResult(false, "NO_PENDING_ACTION", "ไม่มีคำสั่งที่รอให้สลับแอป")
        }
        clearUtilityAction(
            TapResult(false, "TARGET_LAUNCH_FAILED", "เปิดแอปเป้าหมายอัตโนมัติไม่ได้ เปิดแอปนั้นเองแล้วลองเข้าคิวใหม่"),
        )
        return lastPointTapResult!!
    }

    private fun scheduleUtilityActionAfterForegroundSettles(actionRequest: PendingUtilityAction) {
        if (utilityActionDispatchTimeout != null) return
        val dispatchTimeout = Runnable {
            utilityActionDispatchTimeout = null
            if (pendingUtilityAction !== actionRequest) return@Runnable
            val activeRoot = service.rootInActiveWindow
            val activePackage = try {
                activeRoot?.packageName?.toString()
            } finally {
                activeRoot?.recycle()
            }
            if (activePackage != actionRequest.targetPackage) {
                lastPointTapResult = TapResult(
                    true,
                    "ACTION_WAITING_FOR_TARGET",
                    "ยังไม่พบแอปเป้าหมายเป็นหน้าปัจจุบัน คำสั่งยังรออยู่",
                )
                return@Runnable
            }
            clearUtilityAction(TapResult(true, "ACTION_SENDING", "แอปเป้าหมายเปิดเต็มหน้าแล้ว กำลังส่งคำสั่ง"))
            when (actionRequest.type) {
                UtilityActionType.BACK -> {
                    val accepted = service.performGlobalAction(GLOBAL_ACTION_BACK)
                    lastPointTapResult = if (accepted) {
                        TapResult(true, "BACK_DISPATCHED", "Android ส่งคำสั่งย้อนกลับแล้ว ตรวจดูว่าแอปกลับหน้าก่อนหน้าหรือไม่")
                    } else {
                        TapResult(false, "BACK_REJECTED", "Android ไม่รับคำสั่งย้อนกลับ")
                    }
                }
                UtilityActionType.SCROLL_UP,
                UtilityActionType.SCROLL_DOWN,
                UtilityActionType.SWIPE_LEFT,
                UtilityActionType.SWIPE_RIGHT -> dispatchUtilityGesture(actionRequest)
                UtilityActionType.TYPE_TEXT -> setFocusedText(actionRequest)
            }
        }
        utilityActionDispatchTimeout = dispatchTimeout
        mainHandler.postDelayed(dispatchTimeout, POINT_TAP_SETTLE_DELAY_MS)
    }

    private fun dispatchUtilityGesture(actionRequest: PendingUtilityAction) {
        if (!gestures.isCapturedDisplayCurrent(actionRequest.width, actionRequest.height, actionRequest.rotation)) {
            lastPointTapResult = TapResult(false, "STALE_SCREEN", "ขนาดหรือแนวหน้าจอเปลี่ยนไป จึงยกเลิก gesture")
            return
        }
        val horizontal = actionRequest.type == UtilityActionType.SWIPE_LEFT || actionRequest.type == UtilityActionType.SWIPE_RIGHT
        val startX: Float
        val endX: Float
        val startY: Float
        val endY: Float
        if (horizontal) {
            startX = if (actionRequest.type == UtilityActionType.SWIPE_LEFT) actionRequest.width * 0.80f else actionRequest.width * 0.20f
            endX = if (actionRequest.type == UtilityActionType.SWIPE_LEFT) actionRequest.width * 0.20f else actionRequest.width * 0.80f
            startY = floatingControls.horizontalSwipeY(actionRequest.height)
            endY = startY
        } else {
            startX = floatingControls.scrollGestureX(actionRequest.width)
            endX = startX
            startY = if (actionRequest.type == UtilityActionType.SCROLL_UP) actionRequest.height * 0.30f else actionRequest.height * 0.72f
            endY = if (actionRequest.type == UtilityActionType.SCROLL_UP) actionRequest.height * 0.72f else actionRequest.height * 0.30f
        }
        val path = Path().apply {
            moveTo(startX, startY)
            lineTo(endX, endY)
        }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 400))
            .build()
        val accepted = floatingControls.dispatchGestureAvoidingOverlay(
            gesture,
            onCompleted = {
                val label = if (horizontal) "ปัด" else "เลื่อน"
                lastPointTapResult = TapResult(true, "GESTURE_COMPLETED", "Android ส่ง gesture${label}แล้ว ตรวจดูผลบนหน้าจอ")
            },
            onCancelled = {
                lastPointTapResult = TapResult(false, "GESTURE_CANCELLED", "Android ยกเลิก gesture")
            },
        )
        if (!accepted) lastPointTapResult = TapResult(false, "GESTURE_REJECTED", "Android ไม่รับ gesture")
    }

    private fun setFocusedText(actionRequest: PendingUtilityAction) {
        val root = service.rootInActiveWindow
        if (root == null || root.packageName?.toString() != actionRequest.targetPackage) {
            root?.recycle()
            lastPointTapResult = TapResult(false, "TARGET_NOT_FOREGROUND", "ไม่พบแอปเป้าหมายอยู่ด้านหน้า จึงไม่ส่งข้อความ")
            return
        }
        val focused = try { root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) } finally { root.recycle() }
        if (focused == null) {
            lastPointTapResult = TapResult(false, "INPUT_NOT_FOCUSED", "ไม่พบช่องพิมพ์ที่กำลังโฟกัส ให้แตะช่องพิมพ์แล้วลองใหม่")
            return
        }
        try {
            if (!focused.isEditable) {
                lastPointTapResult = TapResult(false, "INPUT_NOT_EDITABLE", "element ที่โฟกัสไม่ใช่ช่องพิมพ์")
            } else if (focused.isPassword) {
                lastPointTapResult = TapResult(false, "PASSWORD_FIELD_BLOCKED", "ป้องกันการพิมพ์ลงช่องรหัสผ่าน")
            } else {
                val args = Bundle().apply {
                    putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, actionRequest.text)
                }
                val accepted = focused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
                lastPointTapResult = if (accepted) {
                    TapResult(true, "TEXT_SET", "ใส่ข้อความลงช่องที่โฟกัสแล้ว โดยไม่ได้กดส่ง")
                } else {
                    TapResult(false, "TEXT_SET_REJECTED", "ช่องนี้ไม่รับคำสั่งใส่ข้อความผ่าน Accessibility")
                }
            }
        } finally { focused.recycle() }
    }

    private fun clearUtilityAction(result: TapResult) {
        pendingUtilityAction = null
        autoSwitchingForUtilityAction = false
        utilityActionTimeout?.let(mainHandler::removeCallbacks)
        utilityActionTimeout = null
        utilityActionDispatchTimeout?.let(mainHandler::removeCallbacks)
        utilityActionDispatchTimeout = null
        lastPointTapResult = result
    }

    private fun schedulePointTapAfterForegroundSettles(pendingTap: PendingPointTap) {
        pendingPointTapDispatchTimeout?.let(mainHandler::removeCallbacks)
        val dispatchTimeout = Runnable {
            pendingPointTapDispatchTimeout = null
            if (pendingPointTap !== pendingTap) return@Runnable

            val activeRoot = service.rootInActiveWindow
            val activePackage = try {
                activeRoot?.packageName?.toString()
            } finally {
                activeRoot?.recycle()
            }
            if (activePackage != pendingTap.targetPackage) {
                lastPointTapResult = TapResult(
                    true,
                    "TAP_WAITING_FOR_TARGET",
                    "ยังไม่พบแอปเป้าหมายเป็นหน้าปัจจุบัน คำสั่งแตะยังรออยู่",
                )
                return@Runnable
            }

            clearPendingPointTap(
                TapResult(true, "TAP_SENDING", "แอปเป้าหมายอยู่ด้านหน้าและนิ่งแล้ว กำลังส่ง gesture"),
            )
            gestures.tapNormalizedPoint(
                pendingTap.x,
                pendingTap.y,
                pendingTap.width,
                pendingTap.height,
                pendingTap.rotation,
            ) { result ->
                lastPointTapResult = if (result.code == "GESTURE_COMPLETED") {
                    TapResult(
                        true,
                        result.code,
                        "Android ส่ง gesture ที่พิกัด x=${pendingTap.x}, y=${pendingTap.y} แล้ว แต่ยังยืนยันไม่ได้ว่าแอปตอบสนองหรือจุดถูกต้อง",
                    )
                } else {
                    result
                }
            }
        }
        pendingPointTapDispatchTimeout = dispatchTimeout
        mainHandler.postDelayed(dispatchTimeout, POINT_TAP_SETTLE_DELAY_MS)
    }

    private fun clearPendingPointTap(result: TapResult) {
        pendingPointTap = null
        pendingPointTapTimeout?.let(mainHandler::removeCallbacks)
        pendingPointTapTimeout = null
        pendingPointTapDispatchTimeout?.let(mainHandler::removeCallbacks)
        pendingPointTapDispatchTimeout = null
        lastPointTapResult = result
    }

    private data class PendingPointTap(
        val x: Double,
        val y: Double,
        val width: Int,
        val height: Int,
        val rotation: Int,
        val targetPackage: String,
    )

    private enum class UtilityActionType {
        SCROLL_UP,
        SCROLL_DOWN,
        SWIPE_LEFT,
        SWIPE_RIGHT,
        BACK,
        TYPE_TEXT,
    }

    private data class PendingUtilityAction(
        val type: UtilityActionType,
        val targetPackage: String,
        val width: Int,
        val height: Int,
        val rotation: Int,
        val text: String? = null,
    )

    @Volatile
    var lastPointTapResult: TapResult? = null

    companion object {
        private const val RECENT_EXTERNAL_PACKAGE_MAX_AGE_MS = 120_000L
        private const val POINT_TAP_SETTLE_DELAY_MS = 1500L
    }
}
