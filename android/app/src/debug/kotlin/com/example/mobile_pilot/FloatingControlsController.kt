package com.example.mobile_pilot

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityService.GestureResultCallback
import android.accessibilityservice.GestureDescription
import android.content.Context.WINDOW_SERVICE
import android.content.ClipData
import android.content.ClipboardManager
import android.graphics.Color
import android.content.Intent
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.util.DisplayMetrics
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowInsets
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.EditText
import android.widget.ScrollView
import android.widget.PopupMenu
import android.view.inputmethod.InputMethodManager
import android.view.inputmethod.EditorInfo
import android.text.InputFilter
import android.graphics.Typeface

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
    private var dismissTarget: TextView? = null
    private var overDismissTarget = false
    private var expanded = false
    private var keyboardOffset = 0
    private var bubbleX = 0
    private var bubbleY = 0
    private var busy = false
    private var running = false
    private var sending = false
    private var stopping = false
    private var closeIcon: Any? = null
    private val tablerTypeface by lazy {
        runCatching {
            Typeface.createFromAsset(
                service.assets,
                "flutter_assets/packages/flutter_tabler_icons/assets/fonts/tabler-icons.ttf",
            )
        }.getOrNull()
    }
    private var recognizer: SpeechRecognizer? = null
    private fun dp(value: Int) = (value * service.resources.displayMetrics.density).toInt()

    private var aiStatus = "AI: ยังไม่ได้เริ่มงาน"

    fun show(): Boolean {
        if (floatingOverlayRoot != null) return true
        val manager = service.getSystemService(WINDOW_SERVICE) as WindowManager
        val root = LinearLayout(service).apply {
            orientation = LinearLayout.VERTICAL
            clipChildren = false
            clipToPadding = false
            isFocusableInTouchMode = true
        }
        val panel = LinearLayout(service).apply {
            orientation = LinearLayout.VERTICAL
            visibility = View.GONE
            setPadding(dp(20), 0, dp(20), dp(24))
            background = GradientDrawable(
                GradientDrawable.Orientation.TOP_BOTTOM,
                intArrayOf(Color.rgb(5, 7, 14), Color.rgb(7, 10, 18), Color.rgb(22, 39, 61)),
            ).apply { cornerRadius = dp(24).toFloat() }
            clipToOutline = true
        }
        val status = TextView(service).apply {
            text = aiStatus
            textSize = 12f
            setTextColor(Color.rgb(148, 163, 184))
            maxLines = 2
        }
        val handle = TextView(service).apply {
            contentDescription = "ขยายหรือย่อพื้นที่แชท"
            setOnClickListener {
                expanded = !expanded
                resizeChat()
            }
        }
        panel.addView(handle, LinearLayout.LayoutParams(-1, dp(12)))
        val messages = LinearLayout(service).apply { orientation = LinearLayout.VERTICAL }
        messages.addView(welcomeMessage("สวัสดี พิมพ์ข้อความหรือระบุคำสั่งได้เลย"))
        val scroll = ScrollView(service).apply {
            addView(messages)
            isFillViewport = true
        }
        panel.addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))
        val composer = LinearLayout(service).apply {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(8), 0, dp(8), 0)
            background = rounded(Color.rgb(15, 25, 42), 28).apply {
                setStroke(dp(1), Color.rgb(38, 53, 73))
            }
        }
        val controls = iconButton("+", "ตัวเลือกหน้าลอย") {}
        controls.background = rounded(Color.rgb(35, 49, 69), 24)
        controls.layoutParams = LinearLayout.LayoutParams(dp(40), dp(40))
        controls.setOnClickListener {
            val menu = PopupMenu(service, controls)
            val actions = listOf(
                "พับแชท", "ขยายหรือย่อพื้นที่แชท", "เลื่อนขึ้น", "เลื่อนลง",
                "ปัดซ้าย", "ปัดขวา", "หน้าหลัก", "แอปล่าสุด", "ย้อนกลับ",
            )
            actions.forEachIndexed { index, title -> menu.menu.add(0, index, index, title) }
            menu.setOnMenuItemClickListener {
                when (it.itemId) {
                    0 -> toggleFloatingPanel()
                    1 -> { expanded = !expanded; resizeChat() }
                    else -> onAction(listOf("scroll_up", "scroll_down", "swipe_left",
                        "swipe_right", "home", "recents", "back")[it.itemId - 2])
                }
                true
            }
            menu.show()
        }
        composer.addView(controls)
        val input = EditText(service).apply {
            hint = "พิมพ์ข้อความ หรือระบุคำสั่ง…"
            textSize = 14f
            setTextColor(Color.WHITE)
            setHintTextColor(Color.rgb(148, 163, 184))
            setPadding(dp(16), 0, dp(8), 0)
            background = null
            setSingleLine()
            filters = arrayOf(InputFilter.LengthFilter(8000))
            imeOptions = EditorInfo.IME_ACTION_SEND
            setOnTouchListener { _, event ->
                if (event.actionMasked == MotionEvent.ACTION_DOWN) {
                    setChatFocusable(true)
                    post {
                        requestFocus()
                        service.getSystemService(InputMethodManager::class.java)
                            ?.showSoftInput(this, InputMethodManager.SHOW_IMPLICIT)
                    }
                }
                false
            }
        }
        composer.addView(input, LinearLayout.LayoutParams(0, dp(52), 1f))
        fun send() {
            if (running) {
                if (!stopping) FloatingChatBridge.stop(onCancel)
                return
            }
            if (busy) return
            val request = input.text.toString().trim()
            if (request.isEmpty() || sending) return
            sending = true
            stopDictation()
            hideKeyboard(input)
            input.clearFocus()
            setChatFocusable(false)
            FloatingChatBridge.send(request) sendResult@{ accepted ->
                sending = false
                if (floatingOverlayRoot !== root) return@sendResult
                if (accepted && input.text.toString().trim() == request) {
                    input.text.clear()
                } else if (!accepted) {
                    input.error = "ส่งไม่ได้ โปรดเปิด MobilePilot และตรวจว่าโมเดลพร้อม"
                }
            }
        }
        val sendButton = iconButton("➤", "ส่งข้อความ") { send() }
        val micButton = iconButton("ไมค์", "พูดข้อความ") {
            if (!busy) dictate(input, status)
        }.apply {
            layoutParams = LinearLayout.LayoutParams(dp(36), dp(36)).apply { marginEnd = dp(6) }
            background = rounded(Color.rgb(26, 41, 61), 18)
        }
        composer.addView(micButton)
        sendButton.background = rounded(Color.rgb(30, 127, 185), 20)
        sendButton.layoutParams = LinearLayout.LayoutParams(dp(40), dp(40))
        composer.addView(sendButton)
        input.setOnEditorActionListener { _, action, _ ->
            if (action == EditorInfo.IME_ACTION_SEND && !busy) { send(); true } else false
        }
        panel.addView(status, LinearLayout.LayoutParams(-1, -2))
        status.visibility = View.GONE
        panel.addView(composer, LinearLayout.LayoutParams(-1, dp(58)).apply {
            topMargin = dp(8)
        })

        val bubble = LinearLayout(service).apply {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(5), dp(5), dp(12), dp(5))
            background = rounded(Color.rgb(224, 225, 241), 32).apply {
                setStroke(dp(1), Color.rgb(155, 166, 186))
            }
            elevation = dp(6).toFloat()
            contentDescription = "เปิดแชท MobilePilot"
        }
        val robotIcon = TextView(service).apply {
            text = "MP"
            textSize = 24f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            background = GradientDrawable(
                GradientDrawable.Orientation.LEFT_RIGHT,
                intArrayOf(Color.rgb(5, 175, 219), Color.rgb(45, 62, 157)),
            ).apply { shape = GradientDrawable.OVAL }
        }
        bubble.addView(robotIcon, LinearLayout.LayoutParams(dp(40), dp(40)))
        val label = LinearLayout(service).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(8), 0, 0, 0)
        }
        label.addView(TextView(service).apply {
            text = "MobilePilot"
            textSize = 16f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.BLACK)
        })
        val bubbleStatus = TextView(service).apply {
            text = "● พร้อมใช้งาน"
            textSize = 11f
            maxWidth = dp(150)
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            setTextColor(Color.rgb(0, 113, 84))
        }
        label.addView(bubbleStatus)
        bubble.addView(label)
        root.addView(bubble, LinearLayout.LayoutParams(-2, -2))
        root.addView(panel, LinearLayout.LayoutParams(-1, dp(360)))

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING
            fitInsetsTypes = WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout()
            gravity = Gravity.TOP or Gravity.START
            x = dp(12)
            y = dp(180)
        }

        bubble.setOnClickListener { toggleFloatingPanel() }
        bubble.setOnTouchListener(createFloatingBubbleTouchListener(root, manager, params))
        root.setOnApplyWindowInsetsListener { _, insets ->
            root.post {
                if (floatingOverlayRoot === root && panel.visibility == View.VISIBLE) {
                    // Use display-sized insets so moving the window does not change the measured overlap.
                    val windowInsets = manager.currentWindowMetrics.windowInsets
                    val bottom = windowInsets.getInsets(WindowInsets.Type.ime()).bottom
                    val systemBottom = windowInsets.getInsets(params.fitInsetsTypes).bottom
                    moveAboveKeyboard((bottom - systemBottom).coerceAtLeast(0))
                }
            }
            insets
        }
        var renderedConversation: Any? = null
        return try {
            manager.addView(root, params)
            floatingWindowManager = manager
            sending = false
            busy = false
            floatingOverlayRoot = root
            floatingOverlayParams = params
            floatingControlsPanel = panel
            floatingPanelStatus = status
            aiPanelStatus = bubbleStatus
            FloatingChatBridge.onUpdate = onUpdate@{ snapshot ->
                busy = snapshot["busy"] == true
                running = snapshot["running"] == true
                stopping = snapshot["stopping"] == true
                sendButton.isEnabled = !stopping && (!busy || running)
                micButton.isEnabled = !busy
                val labels = snapshot["labels"] as? Map<*, *>
                val icons = snapshot["icons"] as? Map<*, *>
                closeIcon = icons?.get("close") ?: closeIcon
                setTablerIcon(controls, icons?.get("plus"), "+")
                setTablerIcon(micButton, icons?.get("microphone"), "ไมค์")
                setTablerIcon(robotIcon, icons?.get("robot"), "MP")
                setTablerIcon(sendButton, icons?.get(if (running) "stop" else "send"),
                    if (running) "□" else "➤")
                sendButton.contentDescription = when {
                    stopping -> labels?.get("stopping") as? String ?: "กำลังหยุด"
                    running -> "หยุด AI"
                    else -> "ส่งข้อความ"
                }
                sendButton.background = GradientDrawable(
                    GradientDrawable.Orientation.LEFT_RIGHT,
                    if (running) intArrayOf(Color.rgb(247, 107, 118), Color.rgb(144, 36, 55))
                    else intArrayOf(Color.rgb(15, 172, 220), Color.rgb(52, 76, 171)),
                ).apply { shape = GradientDrawable.OVAL }
                if (panel.visibility != View.VISIBLE) return@onUpdate
                val conversation = snapshot["conversation"]
                val follow = renderedConversation != conversation || !scroll.canScrollVertically(1)
                renderedConversation = conversation
                messages.removeAllViews()
                val chatMessages = snapshot["messages"] as? List<*> ?: emptyList<Any>()
                val heading = snapshot["heading"] as? String
                if (!heading.isNullOrBlank()) {
                    messages.addView(TextView(service).apply {
                        text = heading
                        gravity = Gravity.CENTER
                        textSize = 12f
                        setTextColor(Color.rgb(135, 146, 154))
                        setPadding(0, dp(8), 0, dp(24))
                    })
                }
                if (chatMessages.isEmpty()) {
                    messages.addView(welcomeMessage(snapshot["welcome"] as? String
                        ?: "สวัสดี พิมพ์ข้อความหรือระบุคำสั่งได้เลย"))
                }
                chatMessages.forEach { item ->
                    val message = item as? Map<*, *> ?: return@forEach
                    val text = message["text"] as? String ?: return@forEach
                    val attachment = message["attachment"] as? String
                    if (text.isEmpty() && attachment == null && message["failed"] != true) return@forEach
                    val user = message["user"] == true
                    val failed = message["failed"] == true
                    val bubbleView = TextView(service).apply {
                        this.text = listOfNotNull(
                            attachment, text.takeIf { it.isNotEmpty() },
                            (labels?.get("failed") as? String)?.takeIf { failed },
                        ).joinToString("\n")
                        textSize = 14f
                        setTextColor(Color.WHITE)
                        setPadding(dp(12), dp(8), dp(12), dp(8))
                        maxWidth = (panel.width - dp(56)).coerceAtLeast(dp(160))
                        background = if (user) GradientDrawable(
                            GradientDrawable.Orientation.LEFT_RIGHT,
                            intArrayOf(Color.rgb(5, 133, 182), Color.rgb(44, 70, 194)),
                        ).apply { cornerRadius = dp(16).toFloat() }
                        else rounded(Color.rgb(12, 17, 29), 16).apply {
                            setStroke(dp(1), Color.rgb(35, 43, 58))
                        }
                    }
                    bubbleView.setOnLongClickListener {
                        val menu = PopupMenu(service, bubbleView)
                        if (text.isNotEmpty()) menu.menu.add(0, 0, 0, labels?.get("copy") as? String ?: "คัดลอก")
                        if (!user && text.isNotEmpty()) menu.menu.add(0, 1, 1, labels?.get("read") as? String ?: "อ่านออกเสียง")
                        val retry = labels?.get("retry") as? String ?: "ลองใหม่"
                        if (failed && !user && !busy) menu.menu.add(0, 2, 2, retry)
                        menu.setOnMenuItemClickListener {
                            when (it.itemId) {
                                0 -> service.getSystemService(ClipboardManager::class.java)
                                    ?.setPrimaryClip(ClipData.newPlainText("MobilePilot", text))
                                1 -> FloatingChatBridge.read(text)
                                2 -> confirmRetry(bubbleView, retry, labels, conversation, message["index"])
                            }
                            true
                        }
                        if (menu.menu.size() == 0) false else { menu.show(); true }
                    }
                    messages.addView(bubbleView, LinearLayout.LayoutParams(-2, -2).apply {
                        gravity = if (user) Gravity.END else Gravity.START
                        bottomMargin = dp(4)
                    })
                    (message["time"] as? String)?.let { time ->
                        messages.addView(TextView(service).apply {
                            this.text = time
                            textSize = 11f
                            setTextColor(Color.rgb(148, 163, 184))
                        }, LinearLayout.LayoutParams(-2, -2).apply {
                            gravity = if (user) Gravity.END else Gravity.START
                            bottomMargin = dp(12)
                        })
                    }
                }
                val steps = (snapshot["steps"] as? List<*>)?.filterIsInstance<Map<*, *>>().orEmpty()
                if (steps.isNotEmpty()) {
                    messages.addView(executionCard(snapshot["stepsTitle"] as? String ?: "", steps))
                }
                if (follow) scroll.post {
                    scroll.scrollTo(0, (messages.height - scroll.height).coerceAtLeast(0))
                }
            }
            FloatingChatBridge.snapshot()
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun welcomeMessage(message: String) = TextView(service).apply {
        text = message
        textSize = 15f
        setTextColor(Color.rgb(224, 225, 241))
        setPadding(dp(15), dp(14), dp(15), dp(14))
        background = rounded(Color.rgb(12, 17, 29), 16).apply {
            setStroke(dp(1), Color.rgb(35, 43, 58))
        }
    }

    private fun confirmRetry(
        anchor: View, retry: String, labels: Map<*, *>?, conversation: Any?, index: Any?,
    ) {
        val dialog = android.app.AlertDialog.Builder(service)
            .setTitle(retry)
            .setMessage(labels?.get("retry_notice") as? String)
            .setNegativeButton(labels?.get("cancel") as? String ?: "ยกเลิก", null)
            .setPositiveButton(retry) { _, _ ->
                FloatingChatBridge.retry(conversation, index) { accepted ->
                    if (!accepted && anchor.isAttachedToWindow) {
                        android.widget.Toast.makeText(service, "ลองใหม่ไม่ได้", android.widget.Toast.LENGTH_SHORT).show()
                    }
                }
            }
            .create()
        dialog.window?.setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
        dialog.show()
    }

    private fun styleClose(view: TextView) {
        val gray = Color.rgb(135, 146, 154)
        val translucent = Color.argb(128, 135, 146, 154)
        view.setTextColor(gray)
        view.textSize = 24f
        view.background = rounded(translucent, 24).apply { setStroke(dp(1), translucent) }
    }

    private fun executionCard(title: String, steps: List<Map<*, *>>) =
        LinearLayout(service).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(12), dp(14), dp(12))
            background = rounded(Color.rgb(12, 17, 29), 24).apply {
                setStroke(dp(1), Color.rgb(35, 43, 58))
            }
            addView(TextView(service).apply {
                text = title
                textSize = 12f
                setTextColor(Color.rgb(125, 211, 252))
            })
            for (step in steps) {
                val row = LinearLayout(service).apply {
                    gravity = Gravity.CENTER_VERTICAL
                    setPadding(dp(12), dp(12), dp(12), dp(12))
                    background = rounded(Color.rgb(21, 29, 45), 18)
                }
                row.addView(TextView(service).apply {
                    text = step["label"] as? String
                    textSize = 14f
                    setTextColor(Color.WHITE)
                }, LinearLayout.LayoutParams(0, -2, 1f))
                row.addView(TextView(service).apply {
                    text = step["status"] as? String
                    textSize = 11f
                    setTextColor(Color.rgb(125, 211, 252))
                    setPadding(dp(8), dp(3), dp(8), dp(3))
                    background = rounded(Color.rgb(27, 49, 68), 12)
                })
                addView(row, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(8) })
            }
        }

    private fun rounded(color: Int, radius: Int) = GradientDrawable().apply {
        setColor(color)
        cornerRadius = dp(radius).toFloat()
    }

    private fun setTablerIcon(view: TextView, codePoint: Any?, fallback: String) {
        val font = tablerTypeface
        val code = (codePoint as? Number)?.toInt()
        view.typeface = if (font != null && code != null) font else Typeface.DEFAULT
        val glyph = code?.let { String(Character.toChars(it)) }
        view.text = if (font != null && glyph != null && view.paint.hasGlyph(glyph)) glyph else fallback
    }

    private fun iconButton(label: String, description: String, action: () -> Unit) =
        actionButton(label, description, action).apply {
            textSize = 20f
            includeFontPadding = false
            layoutParams = LinearLayout.LayoutParams(dp(40), dp(40))
        }

    private fun actionButton(label: String, description: String, action: () -> Unit) =
        TextView(service).apply {
            text = label
            textSize = 22f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            contentDescription = description
            layoutParams = LinearLayout.LayoutParams(dp(48), dp(48))
            setOnClickListener { action() }
        }

    private fun stopDictation() {
        recognizer?.destroy()
        recognizer = null
    }

    private fun dictate(input: EditText, status: TextView) {
        status.visibility = View.VISIBLE
        if (recognizer != null) { stopDictation(); status.visibility = View.GONE; return }
        if (service.checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) !=
            android.content.pm.PackageManager.PERMISSION_GRANTED) {
            status.visibility = View.VISIBLE
            status.text = "เปิดไมค์ในแอป MobilePilot เพื่ออนุญาตการบันทึกเสียงก่อน"
            return
        }
        if (!SpeechRecognizer.isRecognitionAvailable(service)) {
            status.text = "เครื่องนี้ไม่มีบริการรู้จำเสียง"
            return
        }
        try {
            val speech = SpeechRecognizer.createSpeechRecognizer(service)
            recognizer = speech
            speech.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) { status.text = "กำลังฟัง…" }
                override fun onBeginningOfSpeech() = Unit
                override fun onRmsChanged(rmsdB: Float) = Unit
                override fun onBufferReceived(buffer: ByteArray?) = Unit
                override fun onEndOfSpeech() = Unit
                override fun onPartialResults(partialResults: Bundle?) = Unit
                override fun onEvent(eventType: Int, params: Bundle?) = Unit
                override fun onError(error: Int) {
                    if (recognizer !== speech) return
                    stopDictation()
                    status.text = "รับเสียงไม่ได้ ลองอีกครั้ง"
                }
                override fun onResults(results: Bundle?) {
                    if (recognizer !== speech) return
                    val spoken = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        ?.firstOrNull()
                    stopDictation()
                    if (!spoken.isNullOrBlank()) {
                        if (input.text.isNotEmpty()) input.append(" ")
                        input.append(spoken)
                    }
                    status.visibility = View.GONE
                }
            })
            speech.startListening(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            })
        } catch (_: Exception) {
            stopDictation()
            status.text = "เปิดไมโครโฟนไม่ได้"
        }
    }

    private fun hideKeyboard(view: View) {
        service.getSystemService(InputMethodManager::class.java)
            ?.hideSoftInputFromWindow(view.windowToken, 0)
    }

    private fun setChatFocusable(focusable: Boolean) {
        val root = floatingOverlayRoot ?: return
        val params = floatingOverlayParams ?: return
        val flag = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
        params.flags = if (focusable) params.flags and flag.inv() else params.flags or flag
        floatingWindowManager?.updateViewLayout(root, params)
    }

    private fun showDismissTarget(manager: WindowManager) {
        if (dismissTarget != null) return
        val target = actionButton("×", "ลากมาที่นี่เพื่อปิดหน้าลอย") {}
        styleClose(target)
        setTablerIcon(target, closeIcon, "×")
        val params = WindowManager.LayoutParams(
            dp(48), dp(48), WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
            PixelFormat.TRANSLUCENT,
        ).apply { gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL; y = dp(30) }
        target.alpha = 0f
        target.scaleX = .7f
        target.scaleY = .7f
        try {
            manager.addView(target, params)
            dismissTarget = target
            target.animate().alpha(1f).scaleX(1f).scaleY(1f).setDuration(160).start()
        } catch (_: Exception) { }
    }

    private fun hitsDismissTarget(event: MotionEvent): Boolean {
        val target = dismissTarget ?: return false
        val location = IntArray(2)
        target.getLocationOnScreen(location)
        val slop = dp(24)
        return event.rawX in (location[0] - slop).toFloat()..(location[0] + target.width + slop).toFloat() &&
            event.rawY in (location[1] - slop).toFloat()..(location[1] + target.height + slop).toFloat()
    }

    private fun highlightDismissTarget(active: Boolean) {
        val target = dismissTarget ?: return
        if (overDismissTarget == active) return
        overDismissTarget = active
        val scale = if (active) 1.2f else 1f
        target.animate().alpha(1f).scaleX(scale).scaleY(scale).setDuration(120).start()
    }

    private fun removeDismissTarget() {
        val target = dismissTarget ?: return
        dismissTarget = null
        overDismissTarget = false
        target.animate().cancel()
        try {
            floatingWindowManager?.removeViewImmediate(target)
        } catch (_: IllegalArgumentException) {
            // Android may already have removed the overlay.
        }
    }

    private fun resizeChat() {
        val panel = floatingControlsPanel ?: return
        val metrics = floatingWindowManager?.currentWindowMetrics ?: return
        val bars = metrics.windowInsets.getInsetsIgnoringVisibility(
            WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout(),
        )
        panel.layoutParams = panel.layoutParams.apply {
            // Leave room for the capsule, composer and system bars while the keyboard is visible.
            val available = (metrics.bounds.height() - bars.top - bars.bottom -
                dp(58) - keyboardOffset).coerceAtLeast(dp(100))
            this.height = if (expanded) available else dp(360).coerceAtMost(available)
        }
    }

    private fun moveAboveKeyboard(offset: Int) {
        val params = floatingOverlayParams ?: return
        val root = floatingOverlayRoot ?: return
        if (offset == keyboardOffset) return
        keyboardOffset = offset
        params.y = offset
        resizeChat()
        floatingWindowManager?.updateViewLayout(root, params)
    }

    private fun createFloatingBubbleTouchListener(
        root: View,
        manager: WindowManager,
        params: WindowManager.LayoutParams,
    ): View.OnTouchListener {
        val touchSlop = ViewConfiguration.get(service).scaledTouchSlop
        var startRawX = 0f
        var startRawY = 0f
        var startX = 0
        var startY = 0
        var moved = false

        return View.OnTouchListener { view, event ->
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
                    if (moved && floatingControlsPanel?.visibility != View.VISIBLE) {
                        showDismissTarget(manager)
                        val metrics = DisplayMetrics()
                        @Suppress("DEPRECATION")
                        manager.defaultDisplay.getRealMetrics(metrics)
                        params.x = (startX + dx).coerceIn(0, (metrics.widthPixels - root.width).coerceAtLeast(0))
                        params.y = (startY + dy).coerceIn(0, (metrics.heightPixels - root.height).coerceAtLeast(0))
                        manager.updateViewLayout(root, params)
                        highlightDismissTarget(hitsDismissTarget(event))
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    val dropped = hitsDismissTarget(event)
                    removeDismissTarget()
                    if (dropped) {
                        (service as? MobilePilotAccessibilityService)?.setFloatingControlsEnabled(false)
                    } else if (!moved) {
                        view.performClick()
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> { removeDismissTarget(); true }
                else -> false
            }
        }
    }

    private fun toggleFloatingPanel() {
        val panel = floatingControlsPanel ?: return
        val root = floatingOverlayRoot ?: return
        val params = floatingOverlayParams ?: return
        val opening = panel.visibility != View.VISIBLE
        if (opening) {
            bubbleX = params.x
            bubbleY = params.y
            root.getChildAt(0).layoutParams = LinearLayout.LayoutParams(-2, -2).apply {
                gravity = Gravity.END
                setMargins(0, 0, dp(8), dp(8))
            }
            panel.visibility = View.VISIBLE
            panel.alpha = 0f
            panel.translationY = dp(24).toFloat()
            panel.animate().alpha(1f).translationY(0f).setDuration(200).start()
            params.width = WindowManager.LayoutParams.MATCH_PARENT
            params.gravity = Gravity.BOTTOM or Gravity.START
            params.x = 0
            params.y = 0
            resizeChat()
            root.requestApplyInsets()
            FloatingChatBridge.snapshot()
        } else {
            panel.animate().cancel()
            stopDictation()
            hideKeyboard(root)
            root.requestFocus()
            panel.visibility = View.GONE
            root.getChildAt(0).layoutParams = LinearLayout.LayoutParams(-2, -2)
            params.width = WindowManager.LayoutParams.WRAP_CONTENT
            params.gravity = Gravity.TOP or Gravity.START
            params.x = bubbleX
            params.y = bubbleY
            keyboardOffset = 0
            expanded = false
        }
        setChatFocusable(false)
    }

    fun remove() {
        stopDictation()
        removeDismissTarget()
        FloatingChatBridge.onUpdate = null
        val root = floatingOverlayRoot ?: return
        try {
            floatingWindowManager?.removeView(root)
        } catch (_: Exception) {
            // The window may already have been removed by the system.
        }
        floatingOverlayRoot = null
        keyboardOffset = 0
        expanded = false
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
        aiPanelStatus?.text = "● " + message.removePrefix("AI: ")
        floatingPanelStatus?.text = message
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
