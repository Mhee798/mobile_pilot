package com.example.mobile_pilot

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityService.GestureResultCallback
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.hardware.display.DisplayManager
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
        }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 100))
            .build()
        val accepted = service.dispatchGesture(
            gesture,
            object : GestureResultCallback() {
                override fun onCompleted(gestureDescription: GestureDescription?) {
                    callback(TapResult(true, "GESTURE_COMPLETED", "Coordinate gesture completed; verify the resulting screen."))
                }

                override fun onCancelled(gestureDescription: GestureDescription?) {
                    callback(TapResult(false, "GESTURE_CANCELLED", "Android cancelled the coordinate gesture."))
                }
            },
            null,
        )
        if (!accepted) callback(TapResult(false, "GESTURE_REJECTED", "Android rejected the coordinate gesture."))
    }

    fun isCapturedDisplayCurrent(width: Int, height: Int, rotation: Int): Boolean {
        val display = service.getSystemService(DisplayManager::class.java).getDisplay(Display.DEFAULT_DISPLAY)
            ?: return false
        val metrics = DisplayMetrics()
        display.getRealMetrics(metrics)
        return metrics.widthPixels == width && metrics.heightPixels == height && display.rotation == rotation
    }

}
