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
    private val floatingControls: FlutterChatOverlay,
    private val gestures: DeviceGestureController,
) {
    private var pointGestureInFlight = false
    private var pointGestureSequence = 0
    private var dragCancellationGeneration = 0
    private var pointGestureTimeout: Runnable? = null
    private var pendingPointTap: PendingPointTap? = null
    private var pendingPointTapTimeout: Runnable? = null
    private var pendingPointTapDispatchTimeout: Runnable? = null
    private var pendingUtilityAction: PendingUtilityAction? = null
    private var utilityActionTimeout: Runnable? = null
    private var utilityActionDispatchTimeout: Runnable? = null
    // Events only wake the checks; their package does not prove which app is foreground.
    fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            event?.eventType != AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
        ) return
        pendingPointTap?.let(::schedulePointTapAfterForegroundSettles)
        pendingUtilityAction?.let(::scheduleUtilityActionAfterForegroundSettles)
    }

    private fun activePackage(): String? {
        val root = service.rootInActiveWindow
        return try { root?.packageName?.toString() } finally { root?.recycle() }
    }

    val hasPendingActions: Boolean get() = pointGestureInFlight || pendingPointTap != null || pendingUtilityAction != null

    fun cancelPendingActions() {
        dragCancellationGeneration++
        if (pendingPointTap != null) {
            clearPendingPointTap(TapResult(false, "TAP_CANCELLED", "ยกเลิกคำสั่งพิกัดที่รออยู่แล้ว"))
        }
        if (pendingUtilityAction != null) {
            clearUtilityAction(TapResult(false, "ACTION_CANCELLED", "ยกเลิกคำสั่งที่รออยู่แล้ว"))
        }
    }

    fun dispose() {
        pointGestureSequence++
        pointGestureInFlight = false
        pointGestureTimeout?.let(mainHandler::removeCallbacks)
        pointGestureTimeout = null
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
    ): TapResult = queuePointPress(x, y, width, height, rotation, targetPackage, 100L)

    fun queueDoubleTap(x: Double, y: Double, width: Int, height: Int, rotation: Int,
                       targetPackage: String): TapResult =
        queuePointPress(x, y, width, height, rotation, targetPackage, 200L, doubleTap = true)

    fun queueLongPress(x: Double, y: Double, width: Int, height: Int, rotation: Int,
                       targetPackage: String, durationMs: Long): TapResult {
        if (durationMs !in 500L..3000L) return TapResult(false, "INVALID_DURATION", "ระยะเวลากดค้างต้องอยู่ระหว่าง 500–3000 มิลลิวินาที")
        return queuePointPress(x, y, width, height, rotation, targetPackage, durationMs)
    }

    fun queueDrag(x: Double, y: Double, endX: Double, endY: Double, width: Int, height: Int,
                  rotation: Int, targetPackage: String, holdMs: Long, durationMs: Long): TapResult {
        if (android.os.Build.VERSION.SDK_INT < 26 || holdMs !in 500L..2000L || durationMs !in 100L..3000L ||
            !endX.isFinite() || !endY.isFinite() || endX !in 0.0..1.0 || endY !in 0.0..1.0 || (x==endX && y==endY))
            return TapResult(false,"INVALID_DRAG","ตรวจจุดปลาย เวลากดค้าง และเวลาลาก (Android 8 ขึ้นไป)")
        return queuePointPress(x,y,width,height,rotation,targetPackage,durationMs,endX,endY,dragHoldMs=holdMs)
    }

    fun queueSwipe(x: Double, y: Double, endX: Double, endY: Double,
                   width: Int, height: Int, rotation: Int, targetPackage: String, durationMs: Long): TapResult {
        if (durationMs !in 100L..3000L) return TapResult(false, "INVALID_DURATION", "ระยะเวลาปัดต้องอยู่ระหว่าง 100–3000 มิลลิวินาที")
        if (!endX.isFinite() || !endY.isFinite() || endX !in 0.0..1.0 || endY !in 0.0..1.0 || (x == endX && y == endY)) {
            return TapResult(false, "INVALID_COORDINATE", "ต้องเลือกจุดปลายที่ต่างจากจุดเริ่มและอยู่ในภาพ")
        }
        return queuePointPress(x, y, width, height, rotation, targetPackage, durationMs, endX, endY)
    }

    fun queuePinch(x: Double, y: Double, width: Int, height: Int, rotation: Int,
                   targetPackage: String, durationMs: Long, startSpan: Double, scale: Double, axis: String): TapResult {
        if (durationMs !in 100L..3000L) return TapResult(false, "INVALID_DURATION", "ระยะเวลาต้องอยู่ระหว่าง 100–3000 มิลลิวินาที")
        val options = PinchOptions(startSpan, scale, axis)
        if (PinchGeometry.create(x, y, width, height, options) == null) {
            return TapResult(false, "INVALID_PINCH", "สองนิ้วต้องอยู่ในจอ เลือกจุดใกล้กลางภาพหรือลดระยะนิ้ว/ระดับซูม")
        }
        return queuePointPress(x, y, width, height, rotation, targetPackage, durationMs, pinch = options)
    }

    private fun queuePointPress(x: Double, y: Double, width: Int, height: Int, rotation: Int,
                                targetPackage: String, durationMs: Long, endX: Double? = null, endY: Double? = null, pinch: PinchOptions? = null, doubleTap: Boolean = false, dragHoldMs: Long = 0): TapResult {
        if (!x.isFinite() || !y.isFinite() || x !in 0.0..1.0 || y !in 0.0..1.0) {
            return TapResult(false, "INVALID_COORDINATE", "Normalized coordinates must be between 0 and 1.")
        }
        if (targetPackage.isBlank() || targetPackage == service.packageName || width <= 0 || height <= 0 || rotation !in 0..3) {
            return TapResult(false, "INVALID_TARGET", "Capture a screen from another app before queuing a tap.")
        }
        if (pointGestureInFlight || pendingUtilityAction != null) {
            return TapResult(false, "ACTION_IN_PROGRESS", "รอให้คำสั่งก่อนหน้าจบหรือหมดอายุก่อน")
        }
        pendingPointTap = PendingPointTap(x, y, width, height, rotation, targetPackage, durationMs, endX, endY, pinch, doubleTap, dragHoldMs)
        pendingPointTapTimeout?.let(mainHandler::removeCallbacks)
        pendingPointTapDispatchTimeout?.let(mainHandler::removeCallbacks)
        pendingPointTapDispatchTimeout = null
        val timeout = Runnable {
            if (pendingPointTap?.targetPackage == targetPackage) {
                pendingPointTap = null
                pendingPointTapDispatchTimeout = null
                lastPointTapResult = TapResult(false, "TAP_EXPIRED", "คำสั่งพิกัดหมดอายุหลัง 60 วินาที")
            }
            pendingPointTapTimeout = null
        }
        pendingPointTapTimeout = timeout
        mainHandler.postDelayed(timeout, 60_000)
        val label = if (dragHoldMs>0) "ลากหลังค้าง ${dragHoldMs} ms" else if (doubleTap) "แตะสองครั้ง" else if (pinch != null) "สองนิ้ว อัตราระยะนิ้ว ${pinch.scale}" else if (endX != null) "ปัด ${durationMs} ms" else if (durationMs == 100L) "แตะ" else "กดค้าง ${durationMs} ms"
        lastPointTapResult = TapResult(true, "TAP_QUEUED", "เข้าคิว$label แล้ว เปิดแอปเป้าหมายภายใน 60 วินาที")
        schedulePointTapAfterForegroundSettles(pendingPointTap!!)
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
            "keyboard" -> UtilityActionType.KEYBOARD
            else -> return TapResult(false, "UNKNOWN_ACTION", "ไม่รู้จักคำสั่งนี้")
        }
        if (targetPackage.isBlank() || targetPackage == service.packageName || width <= 0 || height <= 0) {
            return TapResult(false, "INVALID_TARGET", "จับภาพจากแอปเป้าหมายก่อน แล้วลองอีกครั้ง")
        }
        if(type==UtilityActionType.KEYBOARD && text !in setOf("default","search","next","enter"))
            return TapResult(false,"INVALID_ARGUMENT","ต้องระบุปุ่มคีย์บอร์ด")
        if (type == UtilityActionType.TYPE_TEXT && (text.isNullOrEmpty() || text.length > 2000)) {
            return TapResult(false, "INVALID_TEXT", "ข้อความต้องมี 1 ถึง 2,000 ตัวอักษร")
        }
        if (pointGestureInFlight || pendingPointTap != null || pendingUtilityAction != null) {
            return TapResult(false, "ACTION_IN_PROGRESS", "รอให้คำสั่งก่อนหน้าจบหรือหมดอายุก่อน")
        }

        val actionRequest = PendingUtilityAction(type, targetPackage, width, height, rotation, text)
        pendingUtilityAction = actionRequest
        lastPointTapResult = TapResult(true, "ACTION_QUEUED", "รอแอปเป้าหมาย ($targetPackage) กดเปิดแอปเป้าหมายได้ คำสั่งนี้ไม่เปิดแอปอัตโนมัติ")
        val timeout = Runnable {
            if (pendingUtilityAction === actionRequest) {
                pendingUtilityAction = null
                utilityActionDispatchTimeout = null
                lastPointTapResult = TapResult(false, "ACTION_EXPIRED", "คำสั่งหมดอายุหลัง 60 วินาที")
            }
            utilityActionTimeout = null
        }
        utilityActionTimeout = timeout
        mainHandler.postDelayed(timeout, 60_000)
        scheduleUtilityActionAfterForegroundSettles(actionRequest)
        return lastPointTapResult!!
    }

    fun getQueuedUtilityTargetPackage(): String? = pendingUtilityAction?.targetPackage

    private fun scheduleUtilityActionAfterForegroundSettles(actionRequest: PendingUtilityAction) {
        utilityActionDispatchTimeout?.let {
            mainHandler.removeCallbacks(it)
            it.run()
            return
        }
        var matchingSince: Long? = null
        val check = object : Runnable {
            override fun run() {
                if (pendingUtilityAction !== actionRequest) return
                val now = SystemClock.elapsedRealtime()
                if (activePackage() == actionRequest.targetPackage) {
                    val since = matchingSince ?: now.also { matchingSince = it }
                    if (now - since >= POINT_TAP_SETTLE_DELAY_MS) {
                        clearUtilityAction(TapResult(true, "ACTION_SENDING", "แอปเป้าหมายอยู่ด้านหน้านิ่งแล้ว กำลังส่งคำสั่ง"))
                        dispatchUtilityAction(actionRequest)
                        return
                    }
                } else {
                    matchingSince = null
                    lastPointTapResult = TapResult(true, "ACTION_WAITING_FOR_TARGET", "รอแอปเป้าหมายอยู่ด้านหน้า คำสั่งยังไม่ทำงาน กดหยุดเพื่อยกเลิกได้")
                }
                mainHandler.postDelayed(this, FOREGROUND_POLL_MS)
            }
        }
        utilityActionDispatchTimeout = check
        mainHandler.post(check)
    }

    private fun dispatchUtilityAction(actionRequest: PendingUtilityAction) {
        when (actionRequest.type) {
            UtilityActionType.BACK -> {
                val accepted = service.performGlobalAction(GLOBAL_ACTION_BACK)
                lastPointTapResult = if (accepted) {
                    TapResult(true, "BACK_DISPATCHED", "Android ส่งคำสั่งย้อนกลับแล้ว ตรวจดูผลบนหน้าจอ")
                } else {
                    TapResult(false, "BACK_REJECTED", "Android ไม่รับคำสั่งย้อนกลับ")
                }
            }
            UtilityActionType.SCROLL_UP,
            UtilityActionType.SCROLL_DOWN,
            UtilityActionType.SWIPE_LEFT,
            UtilityActionType.SWIPE_RIGHT -> dispatchUtilityGesture(actionRequest)
            UtilityActionType.TYPE_TEXT -> setFocusedText(actionRequest)
            UtilityActionType.KEYBOARD -> {
                lastPointTapResult=if(!gestures.isCapturedDisplayCurrent(actionRequest.width,actionRequest.height,actionRequest.rotation))
                    TapResult(false,"STALE_SCREEN","หน้าจอเปลี่ยนไป กรุณาจับภาพใหม่")
                else KeyboardActionController(service).perform(actionRequest.targetPackage,actionRequest.text!!)
            }
        }
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
        utilityActionTimeout?.let(mainHandler::removeCallbacks)
        utilityActionTimeout = null
        utilityActionDispatchTimeout?.let(mainHandler::removeCallbacks)
        utilityActionDispatchTimeout = null
        lastPointTapResult = result
    }

    private fun schedulePointTapAfterForegroundSettles(pendingTap: PendingPointTap) {
        pendingPointTapDispatchTimeout?.let {
            mainHandler.removeCallbacks(it)
            it.run()
            return
        }
        var matchingSince: Long? = null
        val check = object : Runnable {
            override fun run() {
                if (pendingPointTap !== pendingTap) return
                val now = SystemClock.elapsedRealtime()
                if (activePackage() == pendingTap.targetPackage) {
                    val since = matchingSince ?: now.also { matchingSince = it }
                    if (now - since >= POINT_TAP_SETTLE_DELAY_MS) {
                        clearPendingPointTap(TapResult(true, "TAP_SENDING", "แอปเป้าหมายอยู่ด้านหน้านิ่งแล้ว กำลังส่ง gesture"))
                        pointGestureInFlight = true
                        val sequence = ++pointGestureSequence
                        val timeout = Runnable {
                            if (pointGestureInFlight && pointGestureSequence == sequence) {
                                pointGestureInFlight = false
                                pointGestureTimeout = null
                                lastPointTapResult = TapResult(false, "GESTURE_TIMEOUT", "ไม่ได้รับผล gesture จาก Android ภายในเวลาที่กำหนด กรุณาตรวจหน้าจอก่อนลองใหม่")
                            }
                        }
                        pointGestureTimeout = timeout
                        mainHandler.postDelayed(timeout, pendingTap.durationMs + pendingTap.dragHoldMs + 2000L)
                        val completed: (TapResult) -> Unit = { result ->
                            if (pointGestureInFlight && pointGestureSequence == sequence) {
                                pointGestureInFlight = false
                                pointGestureTimeout?.let(mainHandler::removeCallbacks)
                                pointGestureTimeout = null
                                lastPointTapResult = result
                            }
                        }
                        if (pendingTap.dragHoldMs>0) {
                            val dragGeneration = dragCancellationGeneration
                            gestures.dragNormalizedPoints(pendingTap.x,pendingTap.y,pendingTap.endX!!,pendingTap.endY!!,
                                pendingTap.width,pendingTap.height,pendingTap.rotation,pendingTap.dragHoldMs,pendingTap.durationMs,pendingTap.targetPackage,
                                { if (!pointGestureInFlight || pointGestureSequence != sequence) null else dragCancellationGeneration == dragGeneration }, completed)
                        } else if (pendingTap.doubleTap) {
                            gestures.doubleTapNormalizedPoint(pendingTap.x, pendingTap.y, pendingTap.width, pendingTap.height, pendingTap.rotation, completed)
                        } else if (pendingTap.pinch != null) {
                            gestures.pinchNormalizedPoint(pendingTap.x, pendingTap.y, pendingTap.width, pendingTap.height,
                                pendingTap.rotation, pendingTap.durationMs, pendingTap.pinch.startSpan,
                                pendingTap.pinch.scale, pendingTap.pinch.axis, completed)
                        } else if (pendingTap.endX != null && pendingTap.endY != null) {
                            gestures.swipeNormalizedPoints(pendingTap.x, pendingTap.y, pendingTap.endX, pendingTap.endY,
                                pendingTap.width, pendingTap.height, pendingTap.rotation, pendingTap.durationMs, completed)
                        } else if (pendingTap.durationMs == 100L) {
                            gestures.tapNormalizedPoint(
                                pendingTap.x, pendingTap.y, pendingTap.width, pendingTap.height, pendingTap.rotation, completed,
                            )
                        } else {
                            gestures.longPressNormalizedPoint(
                                pendingTap.x, pendingTap.y, pendingTap.width, pendingTap.height, pendingTap.rotation, pendingTap.durationMs, completed,
                            )
                        }
                        return
                    }
                } else {
                    matchingSince = null
                    lastPointTapResult = TapResult(true, "TAP_WAITING_FOR_TARGET", "รอแอปเป้าหมายอยู่ด้านหน้า ยังไม่ส่งคำสั่ง กดหยุดเพื่อยกเลิกได้")
                }
                mainHandler.postDelayed(this, FOREGROUND_POLL_MS)
            }
        }
        pendingPointTapDispatchTimeout = check
        mainHandler.post(check)
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
        val durationMs: Long,
        val endX: Double?,
        val endY: Double?,
        val pinch: PinchOptions?,
        val doubleTap: Boolean,
        val dragHoldMs: Long,
    )

    private enum class UtilityActionType {
        SCROLL_UP,
        SCROLL_DOWN,
        SWIPE_LEFT,
        SWIPE_RIGHT,
        BACK,
        TYPE_TEXT,
        KEYBOARD,
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
        private const val POINT_TAP_SETTLE_DELAY_MS = 1500L
        private const val FOREGROUND_POLL_MS = 100L
    }
}
