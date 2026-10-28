package com.example.mobile_pilot

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityService.GestureResultCallback
import android.accessibilityservice.GestureDescription
import android.content.Context.WINDOW_SERVICE
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.util.DisplayMetrics
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView

class FloatingControlsController(
    private val service: AccessibilityService,
    private val mainHandler: Handler,
    private val onAction: (String) -> Unit,
    private val onCancel: () -> Unit,
) {
    private var floatingWindowManager: WindowManager? = null
    private var floatingOverlayRoot: LinearLayout? = null
    private var floatingOverlayParams: WindowManager.LayoutParams? = null
    private var floatingControlsPanel: LinearLayout? = null
    private var floatingPanelStatus: TextView? = null
    private var aiPanelStatus: TextView? = null
    private var aiStatus = "AI: ยังไม่ได้เริ่มงาน"

    fun show(): Boolean {
        if (floatingOverlayRoot != null) return true
        val manager = service.getSystemService(WINDOW_SERVICE) as WindowManager
        val density = service.resources.displayMetrics.density
        fun dp(value: Int) = (value * density).toInt()

        val root = LinearLayout(service).apply {
            orientation = LinearLayout.VERTICAL
            clipChildren = false
            clipToPadding = false
        }
        val panel = LinearLayout(service).apply {
            orientation = LinearLayout.VERTICAL
            visibility = View.GONE
            setPadding(dp(10), dp(10), dp(10), dp(10))
            background = GradientDrawable().apply {
                setColor(Color.rgb(250, 250, 252))
                cornerRadius = dp(16).toFloat()
            }
            elevation = dp(8).toFloat()
        }
        val title = TextView(service).apply {
            text = "MobilePilot"
            textSize = 16f
            setTextColor(Color.rgb(30, 38, 56))
            setPadding(dp(4), dp(2), dp(4), dp(6))
        }
        val status = TextView(service).apply {
            text = "พร้อมใช้งาน"
            textSize = 12f
            setTextColor(Color.rgb(75, 85, 105))
            setPadding(dp(4), 0, dp(4), dp(6))
        }
        panel.addView(title)
        panel.addView(status)
        val aiStatusView = TextView(service).apply {
            text = aiStatus
            textSize = 12f
            setTextColor(Color.rgb(49, 87, 213))
            setPadding(dp(4), 0, dp(4), dp(6))
        }
        panel.addView(aiStatusView)
        panel.addView(createFloatingButton("เลื่อนขึ้น") { onAction("scroll_up") }, floatingButtonLayout(dp(42), dp(5)))
        panel.addView(createFloatingButton("เลื่อนลง") { onAction("scroll_down") }, floatingButtonLayout(dp(42), dp(5)))
        panel.addView(createFloatingButton("ปัดซ้าย") { onAction("swipe_left") }, floatingButtonLayout(dp(42), dp(5)))
        panel.addView(createFloatingButton("ปัดขวา") { onAction("swipe_right") }, floatingButtonLayout(dp(42), dp(5)))
        panel.addView(createFloatingButton("หน้าหลัก Home") { onAction("home") }, floatingButtonLayout(dp(42), dp(5)))
        panel.addView(createFloatingButton("แอปล่าสุด Recents") { onAction("recents") }, floatingButtonLayout(dp(42), dp(5)))
        panel.addView(createFloatingButton("ย้อนกลับ") { onAction("back") }, floatingButtonLayout(dp(42), dp(5)))
        panel.addView(createFloatingButton("หยุด AI / ยกเลิกคำสั่ง") { onCancel() }, floatingButtonLayout(dp(42), dp(5)))
        panel.addView(createFloatingButton("ย่อแผง") { toggleFloatingPanel() }, floatingButtonLayout(dp(42), dp(5)))

        val bubble = TextView(service).apply {
            text = "MP"
            textSize = 15f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            contentDescription = "เปิดหรือปิดแผงคำสั่ง MobilePilot"
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.rgb(49, 87, 213))
            }
            elevation = dp(8).toFloat()
        }
        root.addView(bubble, LinearLayout.LayoutParams(dp(56), dp(56)))
        root.addView(panel, LinearLayout.LayoutParams(dp(196), LinearLayout.LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(8)
        })

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = dp(12)
            y = dp(180)
        }

        bubble.setOnTouchListener(createFloatingBubbleTouchListener(root, panel, manager, params))
        return try {
            manager.addView(root, params)
            floatingWindowManager = manager
            floatingOverlayRoot = root
            floatingOverlayParams = params
            floatingControlsPanel = panel
            floatingPanelStatus = status
            aiPanelStatus = aiStatusView
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun floatingButtonLayout(heightPx: Int, topMarginPx: Int) = LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.MATCH_PARENT,
        heightPx,
    ).apply {
        topMargin = topMarginPx
    }

    private fun createFloatingButton(label: String, action: () -> Unit): TextView {
        val density = service.resources.displayMetrics.density
        val view = TextView(service).apply {
            text = label
            textSize = 14f
            gravity = Gravity.CENTER
            setTextColor(Color.rgb(30, 38, 56))
            background = GradientDrawable().apply {
                setColor(Color.rgb(234, 238, 248))
                cornerRadius = 10 * density
            }
            setOnClickListener { action() }
        }
        return view
    }

    private fun createFloatingBubbleTouchListener(
        root: View,
        panel: LinearLayout,
        manager: WindowManager,
        params: WindowManager.LayoutParams,
    ): View.OnTouchListener {
        val touchSlop = ViewConfiguration.get(service).scaledTouchSlop
        var startRawX = 0f
        var startRawY = 0f
        var startX = 0
        var startY = 0
        var moved = false

        return View.OnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    startRawX = event.rawX
                    startRawY = event.rawY
                    startX = params.x
                    startY = params.y
                    moved = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.rawX - startRawX).toInt()
                    val dy = (event.rawY - startRawY).toInt()
                    if (kotlin.math.abs(dx) > touchSlop || kotlin.math.abs(dy) > touchSlop) moved = true
                    if (moved) {
                        val metrics = DisplayMetrics()
                        @Suppress("DEPRECATION")
                        manager.defaultDisplay.getRealMetrics(metrics)
                        params.x = (startX + dx).coerceIn(0, (metrics.widthPixels - root.width).coerceAtLeast(0))
                        params.y = (startY + dy).coerceIn(0, (metrics.heightPixels - root.height).coerceAtLeast(0))
                        manager.updateViewLayout(root, params)
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) {
                        panel.visibility = if (panel.visibility == View.VISIBLE) View.GONE else View.VISIBLE
                        manager.updateViewLayout(root, params)
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> true
                else -> false
            }
        }
    }

    private fun toggleFloatingPanel() {
        val panel = floatingControlsPanel ?: return
        panel.visibility = if (panel.visibility == View.VISIBLE) View.GONE else View.VISIBLE
        val root = floatingOverlayRoot ?: return
        val params = floatingOverlayParams ?: return
        floatingWindowManager?.updateViewLayout(root, params)
    }

    fun remove() {
        val root = floatingOverlayRoot ?: return
        try {
            floatingWindowManager?.removeView(root)
        } catch (_: Exception) {
            // The window may already have been removed by the system.
        }
        floatingOverlayRoot = null
        floatingOverlayParams = null
        floatingControlsPanel = null
        floatingPanelStatus = null
        aiPanelStatus = null
        floatingWindowManager = null
    }

    fun setStatus(message: String) {
        floatingPanelStatus?.text = message
    }

    fun setAiStatus(message: String) {
        aiStatus = message
        aiPanelStatus?.text = message
    }

    fun scrollGestureX(screenWidth: Int): Float {
        val overlay = floatingOverlayRoot ?: return screenWidth * 0.5f
        if (overlay.width <= 0) return screenWidth * 0.75f

        val location = IntArray(2)
        overlay.getLocationOnScreen(location)
        val overlayLeft = location[0].toFloat()
        val overlayRight = overlayLeft + overlay.width
        val screenCenter = screenWidth * 0.5f
        if (screenCenter < overlayLeft || screenCenter > overlayRight) return screenCenter

        val leftSpace = overlayLeft.coerceAtLeast(0f)
        val rightSpace = (screenWidth - overlayRight).coerceAtLeast(0f)
        return if (rightSpace >= leftSpace) {
            (overlayRight + screenWidth) * 0.5f
        } else {
            overlayLeft * 0.5f
        }
    }

    fun horizontalSwipeY(screenHeight: Int): Float {
        val overlay = floatingOverlayRoot ?: return screenHeight * 0.5f
        if (overlay.height <= 0) return screenHeight * 0.75f
        val location = IntArray(2)
        overlay.getLocationOnScreen(location)
        val top = location[1].toFloat()
        val bottom = top + overlay.height
        val center = screenHeight * 0.5f
        if (center < top || center > bottom) return center
        val topSpace = top.coerceAtLeast(0f)
        val bottomSpace = (screenHeight - bottom).coerceAtLeast(0f)
        return if (bottomSpace >= topSpace) (bottom + screenHeight) * 0.5f else top * 0.5f
    }

    fun dispatchGestureAvoidingOverlay(
        gesture: GestureDescription,
        onCompleted: () -> Unit,
        onCancelled: () -> Unit,
    ): Boolean {
        val overlay = floatingOverlayRoot
        val params = floatingOverlayParams
        val manager = floatingWindowManager
        val originalFlags = params?.flags
        if (overlay != null && params != null && manager != null) {
            params.flags = params.flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
            manager.updateViewLayout(overlay, params)
        }

        var restored = false
        val restore = {
            if (!restored) {
                restored = true
                if (overlay != null && manager != null && originalFlags != null && floatingOverlayRoot === overlay) {
                    params.flags = originalFlags
                    manager.updateViewLayout(overlay, params)
                }
            }
        }
        val restoreTimeout = Runnable { restore() }
        mainHandler.postDelayed(restoreTimeout, 2_000)
        val accepted = service.dispatchGesture(
            gesture,
            object : GestureResultCallback() {
                override fun onCompleted(gestureDescription: GestureDescription?) {
                    mainHandler.removeCallbacks(restoreTimeout)
                    restore()
                    onCompleted()
                }

                override fun onCancelled(gestureDescription: GestureDescription?) {
                    mainHandler.removeCallbacks(restoreTimeout)
                    restore()
                    onCancelled()
                }
            },
            null,
        )
        if (!accepted) {
            mainHandler.removeCallbacks(restoreTimeout)
            restore()
        }
        return accepted
    }

}
