package com.example.mobile_pilot

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.graphics.Rect
import android.os.Build

/** Slow swipe with overlap, restricted to the visible scroll container. */
class ScrollGestureController @JvmOverloads constructor(
    private val service: AccessibilityService,
    private val floating: FloatingControlsController? = null,
) {
    fun dispatch(bounds: Rect, direction: String, fraction: Double, done: (Boolean) -> Unit): Boolean {
        if (Build.VERSION.SDK_INT < 24 || bounds.width() < 24 || bounds.height() < 100 ||
            direction !in setOf("up", "down") || fraction !in 0.4..0.8) return false
        val x = bounds.exactCenterX()
        val inset = (bounds.height() * (1 - fraction) / 2).toFloat()
        val top = bounds.top + inset
        val bottom = bounds.bottom - inset
        val path = Path().apply {
            moveTo(x, if (direction == "down") bottom else top)
            lineTo(x, if (direction == "down") top else bottom)
        }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 600)).build()
        return if (floating != null) floating.dispatchGestureAvoidingOverlay(gesture, { done(true) }, { done(false) })
        else service.dispatchGesture(gesture, object : AccessibilityService.GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) = done(true)
            override fun onCancelled(gestureDescription: GestureDescription?) = done(false)
        }, null)
    }
}
