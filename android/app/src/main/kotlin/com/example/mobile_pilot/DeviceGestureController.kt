package com.example.mobile_pilot

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityService.GestureResultCallback
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.hardware.display.DisplayManager
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.os.Build
import android.util.DisplayMetrics
import android.view.Display
import com.example.mobile_pilot.MobilePilotAccessibilityService.TapResult

class DeviceGestureController(private val service: AccessibilityService) {
    fun tapNormalizedPoint(
        x: Double,
        y: Double,
        screenshotWidth: Int,
        screenshotHeight: Int,
        screenshotRotation: Int,
        callback: (TapResult) -> Unit,
    ) = pressNormalizedPoint(x, y, screenshotWidth, screenshotHeight, screenshotRotation, 100L, callback)

    fun doubleTapNormalizedPoint(x: Double, y: Double, width: Int, height: Int, rotation: Int,
                                 callback: (TapResult) -> Unit) {
        if (Build.VERSION.SDK_INT < 24 || !x.isFinite() || !y.isFinite() || x !in 0.0..1.0 || y !in 0.0..1.0) {
            callback(TapResult(false, "INVALID_COORDINATE", "พิกัดแตะสองครั้งไม่ถูกต้อง หรือ Android ไม่รองรับ")); return
        }
        if (!isCapturedDisplayCurrent(width, height, rotation)) {
            callback(TapResult(false, "STALE_SCREEN", "หน้าจอเปลี่ยนไป กรุณาจับภาพใหม่")); return
        }
        val path = Path().apply { moveTo((x * width).toFloat(), (y * height).toFloat()) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 60))
            .addStroke(GestureDescription.StrokeDescription(path, 140, 60)).build()
        dispatch(gesture, "Android แตะสองครั้งแล้ว โปรดตรวจผลบนหน้าจอ", callback)
    }

    fun longPressNormalizedPoint(
        x: Double, y: Double, screenshotWidth: Int, screenshotHeight: Int,
        screenshotRotation: Int, durationMs: Long, callback: (TapResult) -> Unit,
    ) {
        if (durationMs !in 500L..3000L) {
            callback(TapResult(false, "INVALID_DURATION", "ระยะเวลากดค้างต้องอยู่ระหว่าง 500–3000 มิลลิวินาที"))
            return
        }
        pressNormalizedPoint(x, y, screenshotWidth, screenshotHeight, screenshotRotation, durationMs, callback)
    }

    fun dragNormalizedPoints(x: Double, y: Double, endX: Double, endY: Double,
                             width: Int, height: Int, rotation: Int, holdMs: Long, durationMs: Long,
                             target: String, shouldContinue: () -> Boolean?, callback: (TapResult) -> Unit) {
        if (Build.VERSION.SDK_INT < 26 || holdMs !in 500L..2000L || durationMs !in 100L..3000L ||
            listOf(x,y,endX,endY).any { !it.isFinite() || it !in 0.0..1.0 } || (x==endX && y==endY)) {
            callback(TapResult(false,"INVALID_DRAG","ลากต้องใช้ Android 8 ขึ้นไป พิกัดต่างกัน และเวลาถูกต้อง"));return
        }
        if (!isCapturedDisplayCurrent(width,height,rotation)) {
            callback(TapResult(false,"STALE_SCREEN","หน้าจอเปลี่ยน กรุณาจับภาพใหม่"));return
        }
        val startX=(x*width).toFloat();val startY=(y*height).toFloat()
        val hold=GestureDescription.StrokeDescription(Path().apply { moveTo(startX,startY) },0,holdMs,true)
        val holdStartedAt = SystemClock.uptimeMillis()
        val accepted=service.dispatchGesture(GestureDescription.Builder().addStroke(hold).build(),object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) {
                // Some devices report the continuing stroke complete before its duration elapses.
                // Check cancellation and foreground at the actual end of the hold.
                val remaining = (holdMs - (SystemClock.uptimeMillis() - holdStartedAt)).coerceAtLeast(0)
                Handler(Looper.getMainLooper()).postDelayed(Runnable {
                    val root=service.rootInActiveWindow
                    val sameTarget=try { root?.packageName?.toString()==target } finally { root?.recycle() }
                    // A stale callback must not dispatch anything: a newer gesture may be running.
                    val continueDrag = shouldContinue() ?: return@Runnable
                    val cancelled = !continueDrag
                    val ready=!cancelled && sameTarget && isCapturedDisplayCurrent(width,height,rotation)
                    val path=Path().apply { moveTo(startX,startY);if(ready) lineTo((endX*width).toFloat(),(endY*height).toFloat()) }
                    val stroke=hold.continueStroke(path,0,if(ready) durationMs else 1L,false)
                    val gesture=GestureDescription.Builder().addStroke(stroke).build()
                    // Always release the held contact, even if foreground/display changed during the hold.
                    dispatch(gesture,"Android ลากแล้ว โปรดตรวจผลบนหน้าจอ") { result ->
                        callback(if (ready) result else if (cancelled)
                            TapResult(false, "DRAG_CANCELLED", "ยกเลิกการลากและปล่อยนิ้วแล้ว")
                        else TapResult(false,"DRAG_TARGET_CHANGED","หยุดลากและปล่อยนิ้ว เพราะแอปหรือหน้าจอเปลี่ยน"))
                    }
                }, remaining)
            }
            override fun onCancelled(gestureDescription: GestureDescription?) {
                callback(TapResult(false,"GESTURE_CANCELLED","Android ยกเลิกการกดค้างก่อนลาก"))
            }
        },null)
        if(!accepted) callback(TapResult(false,"GESTURE_REJECTED","Android ไม่รับการลาก"))
    }

    fun swipeNormalizedPoints(x: Double, y: Double, endX: Double, endY: Double,
                              screenshotWidth: Int, screenshotHeight: Int, screenshotRotation: Int,
                              durationMs: Long, callback: (TapResult) -> Unit) {
        if (durationMs !in 100L..3000L) {
            callback(TapResult(false, "INVALID_DURATION", "ระยะเวลาปัดต้องอยู่ระหว่าง 100–3000 มิลลิวินาที"))
            return
        }
        if (!endX.isFinite() || !endY.isFinite() || endX !in 0.0..1.0 || endY !in 0.0..1.0 || (x == endX && y == endY)) {
            callback(TapResult(false, "INVALID_COORDINATE", "ต้องระบุจุดปลายที่ต่างจากจุดเริ่มและอยู่ในภาพ"))
            return
        }
        pressNormalizedPoint(x, y, screenshotWidth, screenshotHeight, screenshotRotation, durationMs, callback, endX, endY)
    }

    private fun pressNormalizedPoint(
        x: Double, y: Double, screenshotWidth: Int, screenshotHeight: Int,
        screenshotRotation: Int, durationMs: Long, callback: (TapResult) -> Unit,
        endX: Double? = null, endY: Double? = null,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            callback(TapResult(false, "GESTURES_UNSUPPORTED", "Coordinate gestures require Android 7.0 or later."))
            return
        }
        if (!x.isFinite() || !y.isFinite() || x !in 0.0..1.0 || y !in 0.0..1.0) {
            callback(TapResult(false, "INVALID_COORDINATE", "Normalized coordinates must be between 0 and 1."))
            return
        }

        if (!isCapturedDisplayCurrent(screenshotWidth, screenshotHeight, screenshotRotation)) {
            callback(TapResult(false, "STALE_SCREEN", "The screen changed after capture. Capture it again before tapping."))
            return
        }

        val path = Path().apply {
            moveTo((x * screenshotWidth).toFloat(), (y * screenshotHeight).toFloat())
            if (endX != null && endY != null) lineTo((endX * screenshotWidth).toFloat(), (endY * screenshotHeight).toFloat())
        }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, durationMs))
            .build()
        val message = if (endX != null) "Android ปัดแล้ว กรุณาตรวจผลบนหน้าจอ" else if (durationMs == 100L) "Android แตะแล้ว กรุณาตรวจผลบนหน้าจอ" else "Android กดค้าง ${durationMs} ms แล้ว กรุณาตรวจผลบนหน้าจอ"
        dispatch(gesture, message, callback)
    }

    fun pinchNormalizedPoint(x: Double, y: Double, width: Int, height: Int, rotation: Int,
                             durationMs: Long, startSpan: Double, scale: Double, axis: String, callback: (TapResult) -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            callback(TapResult(false, "GESTURES_UNSUPPORTED", "สองนิ้วต้องใช้ Android 7.0 ขึ้นไป"))
            return
        }
        if (durationMs !in 100L..3000L) {
            callback(TapResult(false, "INVALID_DURATION", "ระยะเวลาต้องอยู่ระหว่าง 100–3000 มิลลิวินาที"))
            return
        }
        val geometry = PinchGeometry.create(x, y, width, height, PinchOptions(startSpan, scale, axis))
        if (geometry == null) {
            callback(TapResult(false, "INVALID_PINCH", "สองนิ้วต้องอยู่ในจอ เลือกจุดใกล้กลางภาพหรือลดระยะนิ้ว/ระดับซูม"))
            return
        }
        if (!isCapturedDisplayCurrent(width, height, rotation)) {
            callback(TapResult(false, "STALE_SCREEN", "ขนาดหรือแนวหน้าจอเปลี่ยน กรุณาจับภาพใหม่"))
            return
        }
        val builder = GestureDescription.Builder()
        for ((start, end) in listOf(geometry.firstStart to geometry.firstEnd, geometry.secondStart to geometry.secondEnd)) {
            val path = Path().apply { moveTo(start.x, start.y); lineTo(end.x, end.y) }
            builder.addStroke(GestureDescription.StrokeDescription(path, 0, durationMs))
        }
        dispatch(builder.build(), "Android ส่ง gesture สองนิ้วแล้ว กรุณาตรวจผลการซูมบนหน้าจอ", callback)
    }

    private fun dispatch(gesture: GestureDescription, message: String, callback: (TapResult) -> Unit) {
        val accepted = service.dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) {
                callback(TapResult(true, "GESTURE_COMPLETED", message))
            }
            override fun onCancelled(gestureDescription: GestureDescription?) {
                callback(TapResult(false, "GESTURE_CANCELLED", "Android ยกเลิก gesture"))
            }
        }, null)
        if (!accepted) callback(TapResult(false, "GESTURE_REJECTED", "Android ไม่รับ gesture"))
    }

    fun isCapturedDisplayCurrent(width: Int, height: Int, rotation: Int): Boolean {
        val display = service.getSystemService(DisplayManager::class.java).getDisplay(Display.DEFAULT_DISPLAY)
            ?: return false
        val metrics = DisplayMetrics()
        display.getRealMetrics(metrics)
        return metrics.widthPixels == width && metrics.heightPixels == height && display.rotation == rotation
    }

}
