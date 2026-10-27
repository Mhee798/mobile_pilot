package com.example.mobile_pilot

import android.accessibilityservice.AccessibilityService
import android.graphics.Rect
import android.os.Handler
import android.os.SystemClock
import android.view.accessibility.AccessibilityNodeInfo

/** Bounded UI lookup; scrolling is explicitly opt-in and never clicks a match. */
class WaitForUiController @JvmOverloads constructor(
    private val service: AccessibilityService, private val handler: Handler,
    private val scrollGestures: ScrollGestureController = ScrollGestureController(service),
) {
    private data class Request(
        val id: String,
        val target: String,
        val selector: String,
        val value: String,
        val startedAt: Long,
        val deadline: Long,
        val callback: (Map<String, Any?>) -> Unit,
        val direction: String? = null,
        val maxScrolls: Int = 0,
        val distance: String = "app",
        val condition: String = "present",
        val tracker: UiConditionTracker = UiConditionTracker(condition),
        var ambiguous: Boolean = false,
        var scanComplete: Boolean = false,
        var gestureInFlight: Boolean = false,
        var scrolls: Int = 0,
        var targetSeen: Boolean = false,
        var readySince: Long? = null,
        var nextScrollAt: Long = 0,

    )

    private var pending: Request? = null
    private var check: Runnable? = null
    val isWaiting: Boolean get() = pending != null
    val isScrolling: Boolean get() = pending?.direction != null

    fun startScroll(id: String, target: String, selector: String, value: String, timeoutMs: Long,
                    direction: String, maxScrolls: Int, callback: (Map<String, Any?>) -> Unit) {
        if (direction !in setOf("down", "up") || maxScrolls !in 1..40) {
            callback(mapOf("code" to "INVALID_ARGUMENT", "message" to "เลือกทิศทางและจำนวนครั้ง 1–40"))
            return
        }
        begin(id, target, selector, value, timeoutMs, callback, direction, maxScrolls)
    }

    fun startScrollWithDistance(id: String, target: String, selector: String, value: String, timeoutMs: Long,
                                direction: String, maxScrolls: Int, distance: String, callback: (Map<String, Any?>) -> Unit) {
        if (direction !in setOf("up", "down") || maxScrolls !in 1..40 || distance !in setOf("app", "short", "long")) {
            callback(mapOf("code" to "INVALID_ARGUMENT", "message" to "ทิศทาง จำนวนครั้ง หรือระยะเลื่อนไม่ถูกต้อง"))
            return
        }
        begin(id, target, selector, value, timeoutMs, callback, direction, maxScrolls, distance)
    }

    fun start(id: String, target: String, selector: String, value: String, timeoutMs: Long,
              callback: (Map<String, Any?>) -> Unit) =
        begin(id, target, selector, value, timeoutMs, callback, null, 0)

    fun startCondition(id: String, target: String, selector: String, value: String, timeoutMs: Long,
                       condition: String, callback: (Map<String, Any?>) -> Unit) {
        if (condition !in setOf("present", "disappeared", "enabled", "textChanged") || (condition=="textChanged" && selector=="text")) {
            callback(mapOf("code" to "INVALID_ARGUMENT", "message" to "เงื่อนไขไม่ถูกต้อง การรอข้อความเปลี่ยนต้องใช้รหัสรายการหรือคำอธิบาย"))
            return
        }
        begin(id, target, selector, value, timeoutMs, callback, null, 0, condition = condition)
    }

    private fun begin(id: String, target: String, selector: String, value: String, timeoutMs: Long,
                      callback: (Map<String, Any?>) -> Unit, direction: String?, maxScrolls: Int, distance: String = "app", condition: String = "present") {
        if (id.isBlank() || id.length > 100 || target.isBlank() || target == service.packageName ||
            selector !in setOf("text", "contentDescription", "resourceId") ||
            value.isBlank() || value.length > 200 || timeoutMs !in 1_000L..60_000L
        ) {
            callback(mapOf("code" to "INVALID_ARGUMENT", "message" to "เลือกแอป ระบุค่าที่รอ 1–200 ตัวอักษร และเวลารอ 1–60 วินาที"))
            return
        }
        if (pending != null) {
            callback(mapOf("code" to "UI_WAIT_IN_PROGRESS", "message" to "มีคำขอรอ UI อยู่แล้ว กรุณายกเลิกก่อน"))
            return
        }
        val now = SystemClock.elapsedRealtime()
        val request = Request(id, target, selector, value.trim(), now, now + timeoutMs, callback, direction, maxScrolls, distance, condition)
        pending = request
        val poll = object : Runnable {
            override fun run() {
                if (pending !== request) return
                if (SystemClock.elapsedRealtime() >= request.deadline) {
                    finish(request, "UI_TIMEOUT", if (request.condition == "disappeared")
                        "หมดเวลา ยังยืนยันไม่ได้ว่าพบรายการแล้วหายไป" else "หมดเวลารอ ยังไม่พบองค์ประกอบที่มองเห็นในแอปเป้าหมาย")
                    return
                }
                if (request.direction != null) {
                    if (!isTargetForeground(request.target)) {
                        request.readySince = null
                        if (request.targetSeen) {
                            finish(request, "SCROLL_TARGET_CHANGED", "หยุดเลื่อนเพราะออกจากแอปเป้าหมาย")
                            return
                        }
                    } else {
                        request.targetSeen = true
                        if (request.readySince == null) request.readySince = SystemClock.elapsedRealtime()
                    }
                }
                val element = if (request.gestureInFlight) null else findVisibleElement(request)
                if (request.condition != "present") {
                    val outcome=request.tracker.evaluate(SystemClock.elapsedRealtime(),isTargetForeground(request.target),
                        element,request.scanComplete,request.ambiguous)
                    if(outcome!=null) {finish(request,outcome.code,outcome.message,element);return}
                    handler.postDelayed(this,minOf(POLL_INTERVAL_MS,(request.deadline-SystemClock.elapsedRealtime()).coerceAtLeast(0)))
                    return
                }
                if (element != null && isTargetForeground(request.target) &&
                    SystemClock.elapsedRealtime() < request.deadline
                ) {
                    finish(request, "UI_FOUND", "พบองค์ประกอบที่รอแล้ว", element)
                } else {
                    if (request.direction != null && !request.gestureInFlight && request.readySince != null &&
                        SystemClock.elapsedRealtime() - request.readySince!! >= TARGET_SETTLE_MS &&
                        SystemClock.elapsedRealtime() >= request.nextScrollAt) {
                        if (request.scrolls >= request.maxScrolls) {
                            finish(request, "SCROLL_LIMIT", "ครบจำนวนครั้งที่กำหนด ยังไม่พบรายการ")
                            return
                        }
                        if (!scrollOnce(request)) {
                            finish(request, "SCROLL_UNAVAILABLE", "ไม่พบส่วนที่เลื่อนได้ หรือ Android ไม่รับการเลื่อน; อาจถึงขอบรายการ")
                            return
                        }
                        request.scrolls++
                        if (!request.gestureInFlight) request.nextScrollAt = SystemClock.elapsedRealtime() + SCROLL_SETTLE_MS
                    }
                    val remaining = request.deadline - SystemClock.elapsedRealtime()
                    handler.postDelayed(this, minOf(POLL_INTERVAL_MS, remaining.coerceAtLeast(0L)))
                }
            }
        }
        check = poll
        handler.post(poll)
    }

    fun cancel(id: String? = null) {
        val request = pending ?: return
        if (id == null || request.id == id) finish(request, "UI_CANCELLED", "ยกเลิกการรอ UI แล้ว")
    }

    private fun finish(request: Request, code: String, message: String, element: Map<String, Any?>? = null) {
        if (pending !== request) return
        pending = null
        check?.let(handler::removeCallbacks)
        check = null
        request.callback(mapOf(
            "requestId" to request.id, "code" to code, "message" to message,
            "targetPackage" to request.target,
            "elapsedMs" to SystemClock.elapsedRealtime() - request.startedAt, "element" to element,
            "scrollCount" to request.scrolls, "condition" to request.condition, "matchSeen" to request.tracker.matchSeen, "beforeText" to request.tracker.beforeText,
        ))
    }

    private fun scrollOnce(request: Request): Boolean {
        val root = service.rootInActiveWindow ?: return false
        val viewport = Rect().also(root::getBoundsInScreen)
        var visited = 0
        var attempted = false
        fun visit(node: AccessibilityNodeInfo, depth: Int): Boolean {
            if (depth > 30 || visited++ >= 500 || attempted) return false
            // Prefer the first visible scroll container in tree order; do not scroll several panes.
            if (node.isVisibleToUser && node.isScrollable) {
                attempted = true
                if (!isTargetForeground(request.target)) return false
                if (request.distance != "app") {
                    val bounds = Rect().also(node::getBoundsInScreen)
                    if (!bounds.intersect(viewport)) return false
                    request.gestureInFlight = true
                    val accepted = scrollGestures.dispatch(bounds, request.direction!!,
                        if (request.distance == "long") LONG_SWIPE_FRACTION else SHORT_SWIPE_FRACTION) { completed ->
                        if (pending === request) {
                            request.gestureInFlight = false
                            request.nextScrollAt = SystemClock.elapsedRealtime() + GESTURE_SETTLE_MS
                            if (!completed) finish(request, "SCROLL_CANCELLED", "Android ยกเลิกการปัดค้นหา")
                        }
                    }
                    if (!accepted) request.gestureInFlight = false
                    return accepted
                }
                return node.performAction(if (request.direction == "down")
                    AccessibilityNodeInfo.ACTION_SCROLL_FORWARD else AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD)
            }
            for (i in 0 until node.childCount) {
                if (attempted || visited >= 500) break
                val child = node.getChild(i) ?: continue
                val accepted = try { visit(child, depth + 1) } finally { child.recycle() }
                if (accepted) return true
            }
            return false
        }
        return try {
            root.packageName?.toString() == request.target && visit(root, 0)
        } finally { root.recycle() }
    }

    private fun isTargetForeground(target: String): Boolean {
        val root = service.rootInActiveWindow
        return try { root?.packageName?.toString() == target } finally { root?.recycle() }
    }

    private fun findVisibleElement(request: Request): Map<String, Any?>? {
        request.scanComplete = false
        request.ambiguous = false
        val root = service.rootInActiveWindow ?: return null
        request.scanComplete = true
        var visited = 0
        val viewport = Rect().also(root::getBoundsInScreen)
        if (viewport.isEmpty) {
            request.scanComplete = false
            root.recycle()
            return null
        }
        val candidates = mutableListOf<Map<String,Any?>>()
        fun visit(node: AccessibilityNodeInfo, depth: Int, clip: Rect, clickableAncestor: Boolean): Map<String, Any?>? {
            if (depth > 30 || visited >= 500) {
                request.scanComplete = false
                return null
            }
            visited++
            val candidate = when (request.selector) {
                "text" -> node.text?.toString()
                "contentDescription" -> node.contentDescription?.toString()
                else -> node.viewIdResourceName
            }
            val matches = if (request.selector == "resourceId") {
                candidate == request.value
            } else {
                candidate?.trim()?.equals(request.value, ignoreCase = true) == true
            }
            val bounds = Rect().also(node::getBoundsInScreen)
            val onScreen = !bounds.isEmpty && Rect.intersects(bounds, clip)
            val actionable = node.isEnabled && !node.isEditable && (node.isClickable || clickableAncestor)
            if (node.isVisibleToUser && onScreen && matches &&
                (request.condition != "enabled" || actionable)) {
                val element=mapOf(
                "text" to node.text?.toString(), "contentDescription" to node.contentDescription?.toString(),
                "resourceId" to node.viewIdResourceName, "enabled" to node.isEnabled, "clickable" to if (request.condition == "enabled") actionable else node.isClickable,
                )
                if(request.condition=="textChanged") candidates.add(element) else return element
            }
            val childClip = Rect(clip)
            if (node.isScrollable && !childClip.intersect(bounds)) return null
            for (index in 0 until node.childCount) {
                if (visited >= 500) { request.scanComplete = false; break }
                val child = node.getChild(index)
                if (child == null) { request.scanComplete = false; continue }
                val found = try { visit(child, depth + 1, childClip, actionable) } finally { child.recycle() }
                if (found != null) return found
            }
            return null
        }
        return try {
            if(root.packageName?.toString()!=request.target) null else {
                val found=visit(root,0,viewport,false)
                if(request.condition=="textChanged") {
                    request.ambiguous=candidates.size>1
                    candidates.singleOrNull()
                } else found
            }
        } finally { root.recycle() }
    }
    private companion object {
        const val POLL_INTERVAL_MS = 250L
        const val TARGET_SETTLE_MS = 1000L
        const val SCROLL_SETTLE_MS = 1000L
        const val GESTURE_SETTLE_MS = 350L
        const val LONG_SWIPE_FRACTION = 0.8
        const val SHORT_SWIPE_FRACTION = 0.4
    }

}
