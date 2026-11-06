package com.example.mobile_pilot

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Context.WINDOW_SERVICE
import android.content.Intent
import android.graphics.PixelFormat
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowInsets
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.widget.FrameLayout
import android.widget.TextView
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterTextureView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

/** Android owns window placement. The overlay isolate only renders and forwards chat actions. */
class FlutterChatOverlay(
    private val service: MobilePilotAccessibilityService,
    private val handler: Handler,
    private val onAction: (String) -> Unit,
) {
    private val manager by lazy { service.getSystemService(WINDOW_SERVICE) as WindowManager }
    private var engine: FlutterEngine? = null
    private var view: FlutterView? = null
    private var channel: MethodChannel? = null
    private var params: WindowManager.LayoutParams? = null
    private var capsuleEngine: FlutterEngine? = null
    private var capsule: FlutterView? = null
    private var capsuleChannel: MethodChannel? = null
    private var capsuleParams: WindowManager.LayoutParams? = null
    private var dismissTarget: FrameLayout? = null
    private var dismissCircle: View? = null
    private var statusLabel: TextView? = null
    private var statusParams: WindowManager.LayoutParams? = null
    private val hideStatus = Runnable { statusLabel?.visibility = View.INVISIBLE }
    private var dismissHighlighted = false
    private var mode = "bubble"
    private var bubbleX = 0
    private var bubbleY = 0
    private var status = "พร้อมใช้งาน"
    private var gestureCount = 0
    private var dragging = false
    private var overTarget = false
    private var allowedVisible = false
    private var picking = false
    private var keyboardInset = 0
    private val density get() = service.resources.displayMetrics.density
    private fun dp(value: Int) = (value * density).roundToInt()

    fun setVisible(visible: Boolean): Boolean {
        allowedVisible = visible
        if (visible && !picking && view == null) return show()
        updateVisibility()
        return true
    }

    private fun updateVisibility() {
        val root = view ?: return
        val visible = allowedVisible && !picking
        if (!visible && !picking && (mode != "bubble" || dragging)) {
            service.getSystemService(InputMethodManager::class.java)
                ?.hideSoftInputFromWindow(root.windowToken, 0)
            root.clearFocus()
            mode = "bubble"
            dragging = false
            overTarget = false
            layoutWindow()
            publishWindow()
        }
        val chatVisible = visible && mode == "expanded"
        if (chatVisible && root.visibility != View.VISIBLE) {
            root.visibility = View.VISIBLE
            root.requestApplyInsets()
        } else if (!chatVisible) {
            root.visibility = View.INVISIBLE
            publishKeyboardInset(0)
        }
        val bubbleVisible = visible && mode == "bubble"
        val bubbleAppearing = bubbleVisible && capsule?.visibility != View.VISIBLE
        capsule?.visibility = if (bubbleVisible) View.VISIBLE else View.INVISIBLE
        if (bubbleAppearing) showStatusLabel()
        if (!bubbleVisible) hideStatus.run()
        updateDismissTarget()
    }

    private fun show(): Boolean {
        if (view != null) return true
        return try {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(service)
            loader.ensureInitializationComplete(service, null)
            val renderer = FlutterEngine(service)
            engine = renderer
            val bubbleRenderer = FlutterEngine(service, null, false)
            capsuleEngine = bubbleRenderer
            val bubbleView = object : FlutterView(service, FlutterTextureView(service).apply { isOpaque = false }) {
                private var startX = 0f
                private var startY = 0f
                private var originalX = 0
                private var originalY = 0
                private val touchSlop = ViewConfiguration.get(service).scaledTouchSlop

                override fun dispatchTouchEvent(event: MotionEvent): Boolean {
                    if (mode != "bubble") return super.dispatchTouchEvent(event)
                    when (event.actionMasked) {
                        MotionEvent.ACTION_DOWN -> {
                            startX = event.rawX
                            startY = event.rawY
                            originalX = capsuleParams?.x ?: bubbleX
                            originalY = capsuleParams?.y ?: bubbleY
                        }
                        MotionEvent.ACTION_MOVE -> {
                            val dx = event.rawX - startX
                            val dy = event.rawY - startY
                            if (!dragging && maxOf(kotlin.math.abs(dx), kotlin.math.abs(dy)) > touchSlop) {
                                val cancel = MotionEvent.obtain(event)
                                cancel.action = MotionEvent.ACTION_CANCEL
                                super.dispatchTouchEvent(cancel)
                                cancel.recycle()
                                dragging = true
                                hideStatus.run()
                            }
                            if (dragging) {
                                moveBubble(originalX + dx, originalY + dy, event.rawX, event.rawY)
                                return true
                            }
                        }
                        MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> if (dragging) {
                            val dismiss = event.actionMasked == MotionEvent.ACTION_UP &&
                                hitsDismissTarget(event.rawX, event.rawY)
                            dragging = false
                            overTarget = false
                            publishWindow()
                            updateDismissTarget()
                            if (dismiss) handler.post { service.setFloatingControlsEnabled(false) }
                            else if (event.actionMasked == MotionEvent.ACTION_UP) showStatusLabel()
                            return true
                        }
                    }
                    return super.dispatchTouchEvent(event)
                }
            }
            capsule = bubbleView
            bubbleView.visibility = View.INVISIBLE
            bubbleView.attachToFlutterEngine(bubbleRenderer)
            capsuleChannel = MethodChannel(bubbleRenderer.dartExecutor.binaryMessenger, "com.mobilepilot/overlay_ui").also {
                it.setMethodCallHandler(::handle)
            }
            val flutterView = FlutterView(service, FlutterTextureView(service).apply { isOpaque = false })
            view = flutterView
            flutterView.attachToFlutterEngine(renderer)
            channel = MethodChannel(renderer.dartExecutor.binaryMessenger, "com.mobilepilot/overlay_ui").also {
                it.setMethodCallHandler(::handle)
            }
            bubbleX = dp(12)
            bubbleY = dp(120)
            capsuleParams = WindowManager.LayoutParams(
                dp(54), dp(54), WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
                PixelFormat.TRANSLUCENT,
            ).apply {
                gravity = Gravity.TOP or Gravity.LEFT
                fitInsetsTypes = WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout()
                softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING
            }
            val layout = WindowManager.LayoutParams().apply { copyFrom(capsuleParams!!) }
            layout.setFitInsetsIgnoringVisibility(true)
            params = layout
            flutterView.setOnApplyWindowInsetsListener { target, insets ->
                target.onApplyWindowInsets(insets)
                target.post {
                    if (view === target && target.visibility == View.VISIBLE) {
                        layoutWindow()
                        val windowInsets = manager.currentWindowMetrics.windowInsets
                        val ime = windowInsets.getInsets(WindowInsets.Type.ime()).bottom
                        val system = windowInsets.getInsetsIgnoringVisibility(layout.fitInsetsTypes).bottom
                        publishKeyboardInset((ime - system).coerceAtLeast(0))
                    }
                }
                insets
            }
            layoutWindow(update = false)
            flutterView.visibility = View.INVISIBLE
            manager.addView(flutterView, layout)
            manager.addView(bubbleView, capsuleParams!!)
            prepareStatusLabel()
            prepareDismissTarget()
            bubbleRenderer.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "floatingChatMain"),
                listOf("capsule"),
            )
            bubbleRenderer.lifecycleChannel.appIsResumed()
            FloatingChatBridge.onProductionUpdate = {
                if (view?.visibility == View.VISIBLE) channel?.invokeMethod("chat", it)
            }
            renderer.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "floatingChatMain"),
                emptyList(),
            )
            renderer.lifecycleChannel.appIsResumed()
            updateVisibility()
            true
        } catch (error: Exception) {
            android.util.Log.e("MobilePilotOverlay", "Could not open Flutter overlay", error)
            remove()
            false
        }
    }

    private fun handle(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "ready" -> {
                publishWindow()
                if (mode == "expanded") FloatingChatBridge.snapshot()
                result.success(null)
            }
            "mode" -> {
                if (!allowedVisible || picking) {
                    result.success(null)
                    return
                }
                val next = call.arguments as? String
                if (next != "bubble" && next != "expanded") {
                    result.error("INVALID_MODE", "Unknown overlay size", null)
                    return
                }
                setMode(next)
                if (next == "expanded") FloatingChatBridge.snapshot()
                result.success(null)
            }
            "send" -> FloatingChatBridge.sendDraft(call.arguments as? Map<*, *> ?: emptyMap<String, Any>()) {
                result.success(it)
            }
            "pick" -> {
                if (picking) {
                    result.success(null)
                    return
                }
                val root = view
                picking = true
                updateVisibility()
                MainActivity.pickForOverlay(service, call.arguments == true) {
                    if (view === root) {
                        picking = false
                        service.refreshFloatingVisibility()
                    }
                    result.success(it)
                }
            }
            "openApp" -> {
                try {
                    service.startActivity(Intent(service, MainActivity::class.java).addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP,
                    ))
                    result.success(null)
                } catch (error: RuntimeException) {
                    result.error("OPEN_APP_FAILED", error.message, null)
                }
            }
            "messageImage" -> FloatingChatBridge.messageImage(call.arguments as? Map<*, *> ?: emptyMap<String, Any>()) {
                result.success(it)
            }
            "loadOlder" -> FloatingChatBridge.loadOlder(call.arguments) { result.success(it) }
            "chooseApp" -> {
                val choice = call.arguments as? Map<*, *>
                if (choice == null) result.success(false)
                else FloatingChatBridge.chooseApp(choice) { result.success(it == true) }
            }
            "newChat" -> FloatingChatBridge.newChat { created ->
                if (created) FloatingChatBridge.snapshot()
                result.success(created)
            }
            "stop" -> { FloatingChatBridge.stop {}; result.success(null) }
            "read" -> { FloatingChatBridge.read(call.arguments as? String ?: ""); result.success(null) }
            "retry" -> FloatingChatBridge.retry(call.argument<Any>("conversation"), call.argument<Any>("index")) {
                result.success(it)
            }
            "action" -> {
                val action = call.arguments as? String
                if (action in listOf("scroll_up", "scroll_down", "swipe_left", "swipe_right", "home", "recents", "back")) {
                    onAction(action!!)
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun collapseForTool() {
        if (allowedVisible && !picking && mode == "expanded") setMode("bubble")
    }

    private fun setMode(next: String) {
        if (mode == next) return
        if (next == "bubble") view?.let {
            service.getSystemService(InputMethodManager::class.java)
                ?.hideSoftInputFromWindow(it.windowToken, 0)
            it.clearFocus()
        }
        mode = next
        layoutWindow()
        publishWindow()
        updateVisibility()
    }

    private fun moveBubble(x: Float, y: Float, touchX: Float, touchY: Float) {
        val metrics = manager.currentWindowMetrics
        val safe = metrics.windowInsets.getInsets(params?.fitInsetsTypes ?: 0)
        val width = metrics.bounds.width() - safe.left - safe.right
        val height = metrics.bounds.height() - safe.top - safe.bottom
        bubbleX = x.roundToInt().coerceIn(0, (width - dp(54)).coerceAtLeast(0))
        bubbleY = y.roundToInt().coerceIn(0, (height - dp(54)).coerceAtLeast(0))
        val wasOverTarget = overTarget
        overTarget = hitsDismissTarget(touchX, touchY)
        layoutWindow()
        if (overTarget != wasOverTarget) publishWindow()
        updateDismissTarget()
    }

    private fun hitsDismissTarget(x: Float, y: Float): Boolean {
        val target = dismissTarget ?: return false
        if (target.visibility != View.VISIBLE || target.width == 0) return false
        val location = IntArray(2)
        target.getLocationOnScreen(location)
        val radius = target.width / 2f
        val dx = x - (location[0] + radius)
        val dy = y - (location[1] + radius)
        val touchRadius = dp(36).toFloat()
        return dx * dx + dy * dy <= touchRadius * touchRadius
    }

    private fun publishWindow() {
        val state = mapOf("mode" to mode, "status" to status, "overTarget" to overTarget)
        channel?.invokeMethod("window", state)
        capsuleChannel?.invokeMethod("window", state)
    }

    private fun publishKeyboardInset(inset: Int) {
        if (keyboardInset == inset) return
        keyboardInset = inset
        channel?.invokeMethod("keyboard", inset / density)
    }

    private fun layoutWindow(update: Boolean = true) {
        val layout = params ?: return
        val root = view ?: return
        val previous = WindowManager.LayoutParams().apply { copyFrom(layout) }
        val metrics = manager.currentWindowMetrics
        val safe = metrics.windowInsets.getInsetsIgnoringVisibility(layout.fitInsetsTypes)
        val width = metrics.bounds.width() - safe.left - safe.right
        val height = metrics.bounds.height() - safe.top - safe.bottom
        val touchFlag = if (gestureCount > 0) WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE else 0
        layout.width = width
        layout.height = height
        layout.gravity = Gravity.BOTTOM or Gravity.LEFT
        layout.x = 0
        layout.y = 0
        layout.flags = WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or touchFlag
        if (update && root.isAttachedToWindow && previous.copyFrom(layout) != 0) {
            manager.updateViewLayout(root, layout)
        }
        val bubbleLayout = capsuleParams ?: return
        val bubble = capsule ?: return
        val oldBubbleLayout = WindowManager.LayoutParams().apply { copyFrom(bubbleLayout) }
        bubbleLayout.width = dp(54).coerceAtMost(width)
        bubbleLayout.x = bubbleX.coerceIn(0, (width - bubbleLayout.width).coerceAtLeast(0))
        bubbleLayout.y = bubbleY.coerceIn(0, (height - dp(54)).coerceAtLeast(0))
        bubbleLayout.flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or touchFlag
        if (update && bubble.isAttachedToWindow && oldBubbleLayout.copyFrom(bubbleLayout) != 0) {
            manager.updateViewLayout(bubble, bubbleLayout)
        }
    }

    private fun prepareDismissTarget() {
        val circle = object : View(service) {
            private val paint = Paint(Paint.ANTI_ALIAS_FLAG)

            override fun onDraw(canvas: Canvas) {
                super.onDraw(canvas)
                val center = width / 2f
                paint.color = 0xb087929a.toInt()
                canvas.drawCircle(center, center, center, paint)
                paint.color = android.graphics.Color.WHITE
                paint.strokeWidth = dp(2).toFloat()
                paint.strokeCap = Paint.Cap.ROUND
                val arm = dp(8).toFloat()
                canvas.drawLine(center - arm, center - arm, center + arm, center + arm, paint)
                canvas.drawLine(center + arm, center - arm, center - arm, center + arm, paint)
            }
        }
        val target = FrameLayout(service).apply {
            addView(circle, FrameLayout.LayoutParams(dp(48), dp(48), Gravity.CENTER))
            visibility = View.INVISIBLE
        }
        val layout = WindowManager.LayoutParams(
            dp(64), dp(64), WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            fitInsetsTypes = params!!.fitInsetsTypes
            y = dp(16)
        }
        dismissTarget = target
        dismissCircle = circle
        manager.addView(target, layout)
    }

    private fun updateDismissTarget() {
        val target = dismissTarget ?: return
        val circle = dismissCircle ?: return
        if (!allowedVisible || picking || !dragging || mode != "bubble") {
            circle.animate().cancel()
            target.visibility = View.INVISIBLE
            return
        }
        val appearing = target.visibility != View.VISIBLE
        if (appearing) {
            circle.alpha = 0f
            circle.scaleX = .75f
            circle.scaleY = .75f
            target.visibility = View.VISIBLE
        }
        if (!appearing && dismissHighlighted == overTarget) return
        dismissHighlighted = overTarget
        val scale = if (overTarget) 1.2f else 1f
        circle.animate().alpha(1f).scaleX(scale).scaleY(scale).setDuration(140).start()
    }

    fun setStatus(message: String) {
        if (status == message) return
        status = message
        publishWindow()
        showStatusLabel()
    }

    private fun prepareStatusLabel() {
        val label = TextView(service).apply {
            visibility = View.INVISIBLE
            gravity = Gravity.CENTER_VERTICAL
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            textSize = 12f
            setTextColor(0xff00865f.toInt())
            setPadding(dp(12), 0, dp(12), 0)
            background = GradientDrawable().apply {
                setColor(android.graphics.Color.WHITE)
                cornerRadius = dp(12).toFloat()
            }
        }
        val layout = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT, dp(32),
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.LEFT
            fitInsetsTypes = capsuleParams!!.fitInsetsTypes
        }
        statusLabel = label
        statusParams = layout
        manager.addView(label, layout)
    }

    private fun showStatusLabel() {
        val label = statusLabel ?: return
        val layout = statusParams ?: return
        val bubble = capsuleParams ?: return
        if (!allowedVisible || picking || dragging || mode != "bubble" || status.isBlank()) return
        val metrics = manager.currentWindowMetrics
        val safe = metrics.windowInsets.getInsets(layout.fitInsetsTypes)
        val width = metrics.bounds.width() - safe.left - safe.right
        val height = metrics.bounds.height() - safe.top - safe.bottom
        val gap = dp(6)
        val edgeMargin = dp(8)
        val showOnRight = bubble.x + bubble.width / 2 <= width / 2
        val available = if (showOnRight) width - bubble.x - bubble.width else bubble.x
        val labelWidth = minOf(available - gap - edgeMargin, dp(200))
        if (labelWidth <= 0) return
        label.text = status
        label.maxWidth = labelWidth
        label.measure(
            View.MeasureSpec.makeMeasureSpec(label.maxWidth, View.MeasureSpec.AT_MOST),
            View.MeasureSpec.makeMeasureSpec(dp(32), View.MeasureSpec.EXACTLY),
        )
        layout.x = if (showOnRight) bubble.x + bubble.width + gap
            else bubble.x - gap - label.measuredWidth
        layout.y = (bubble.y + (bubble.height - dp(32)) / 2)
            .coerceIn(0, (height - dp(32)).coerceAtLeast(0))
        manager.updateViewLayout(label, layout)
        label.visibility = View.VISIBLE
        handler.removeCallbacks(hideStatus)
        handler.postDelayed(hideStatus, 3000)
    }

    fun setAiStatus(message: String) = setStatus(message.removePrefix("AI: "))

    fun remove() {
        handler.removeCallbacks(hideStatus)
        statusLabel?.let { if (it.isAttachedToWindow) manager.removeViewImmediate(it) }
        statusLabel = null
        statusParams = null
        FloatingChatBridge.onProductionUpdate = null
        channel?.setMethodCallHandler(null)
        channel = null
        capsuleChannel?.setMethodCallHandler(null)
        capsuleChannel = null
        dismissCircle?.animate()?.cancel()
        dismissCircle = null
        dismissTarget?.let {
            if (it.isAttachedToWindow) manager.removeViewImmediate(it)
        }
        dismissTarget = null
        capsule?.let {
            if (it.isAttachedToWindow) manager.removeViewImmediate(it)
            it.detachFromFlutterEngine()
        }
        capsule = null
        capsuleParams = null
        capsuleEngine?.destroy()
        capsuleEngine = null
        view?.let {
            if (it.isAttachedToWindow) manager.removeViewImmediate(it)
            it.detachFromFlutterEngine()
        }
        view = null
        params = null
        engine?.destroy()
        engine = null
        mode = "bubble"
        dragging = false
        overTarget = false
        gestureCount = 0
        allowedVisible = false
        picking = false
        keyboardInset = 0
    }

    fun scrollGestureX(screenWidth: Int) = screenWidth * .5f
    fun horizontalSwipeY(screenHeight: Int) = screenHeight * .5f

    fun dispatchGestureAvoidingOverlay(
        gesture: GestureDescription, onCompleted: () -> Unit, onCancelled: () -> Unit,
    ): Boolean {
        val window = view
        gestureCount++
        layoutWindow()
        var restored = false
        val restore = Runnable {
            if (!restored && view === window) {
                restored = true
                gestureCount = (gestureCount - 1).coerceAtLeast(0)
                layoutWindow()
            }
        }
        handler.postDelayed(restore, 2000)
        val accepted = service.dispatchGesture(gesture, object : AccessibilityService.GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) {
                handler.removeCallbacks(restore)
                restore.run()
                onCompleted()
            }
            override fun onCancelled(gestureDescription: GestureDescription?) {
                handler.removeCallbacks(restore)
                restore.run()
                onCancelled()
            }
        }, handler)
        if (!accepted) {
            handler.removeCallbacks(restore)
            restore.run()
        }
        return accepted
    }
}
