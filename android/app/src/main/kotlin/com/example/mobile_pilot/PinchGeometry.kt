package com.example.mobile_pilot

import android.graphics.PointF
import kotlin.math.min

/** Span is the distance between fingers as a fraction of the shorter display side. */
data class PinchOptions(val startSpan: Double, val scale: Double, val axis: String)
data class PinchGeometry(val firstStart: PointF, val firstEnd: PointF, val secondStart: PointF, val secondEnd: PointF) {
    companion object {
        fun create(x: Double, y: Double, width: Int, height: Int, options: PinchOptions): PinchGeometry? {
            if (width <= 0 || height <= 0 || !x.isFinite() || !y.isFinite() || x !in 0.0..1.0 || y !in 0.0..1.0 ||
                !options.startSpan.isFinite() || options.startSpan !in 0.05..0.8 ||
                !options.scale.isFinite() || options.scale !in 0.25..4.0 || options.scale == 1.0 ||
                options.axis !in setOf("horizontal", "vertical")) return null
            val cx = x * width
            val cy = y * height
            val halfStart = min(width, height) * options.startSpan / 2.0
            val halfEnd = halfStart * options.scale
            fun point(distance: Double): PointF = if (options.axis == "horizontal") PointF((cx + distance).toFloat(), cy.toFloat())
                else PointF(cx.toFloat(), (cy + distance).toFloat())
            val geometry = PinchGeometry(point(-halfStart), point(-halfEnd), point(halfStart), point(halfEnd))
            return geometry.takeIf { listOf(it.firstStart, it.firstEnd, it.secondStart, it.secondEnd)
                .all { point -> point.x >= 0 && point.x < width && point.y >= 0 && point.y < height } }
        }
    }
}
