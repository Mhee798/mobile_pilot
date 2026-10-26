package com.example.mobile_pilot

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityService.GestureResultCallback
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.graphics.Rect
import android.os.Build
import android.view.accessibility.AccessibilityNodeInfo
import com.example.mobile_pilot.MobilePilotAccessibilityService.TapResult

class UiTreeController(private val service: AccessibilityService) {
    fun readUiTree(): List<Map<String, Any?>> {
        val root = service.rootInActiveWindow ?: return emptyList()
        val elements = mutableListOf<Map<String, Any?>>()

        fun visit(node: AccessibilityNodeInfo, depth: Int) {
            if (depth > MAX_TREE_DEPTH || elements.size >= MAX_TREE_ELEMENTS) return

            val text = node.text?.toString()?.takeIf(String::isNotBlank)
            val description = node.contentDescription?.toString()?.takeIf(String::isNotBlank)
            val resourceId = node.viewIdResourceName
            if (text != null || description != null || resourceId != null) {
                val bounds = Rect()
                node.getBoundsInScreen(bounds)
                elements += mapOf(
                    "text" to text,
                    "contentDescription" to description,
                    "resourceId" to resourceId,
                    "className" to node.className?.toString(),
                    "clickable" to node.isClickable,
                    "editable" to node.isEditable,
                    "depth" to depth,
                    "bounds" to mapOf(
                        "left" to bounds.left,
                        "top" to bounds.top,
                        "right" to bounds.right,
                        "bottom" to bounds.bottom,
                    ),
                )
            }

            for (index in 0 until node.childCount) {
                if (elements.size >= MAX_TREE_ELEMENTS) break
                val child = node.getChild(index) ?: continue
                try {
                    visit(child, depth + 1)
                } finally {
                    child.recycle()
                }
            }
        }

        try {
            visit(root, 0)
        } finally {
            root.recycle()
        }
        return elements
    }

    fun tapElementByText(target: String): TapResult {
        val normalizedTarget = target.trim()
        if (normalizedTarget.isEmpty()) {
            return TapResult(false, "EMPTY_TARGET", "Enter text to tap.")
        }

        val root = service.rootInActiveWindow
            ?: return TapResult(false, "NO_ACTIVE_WINDOW", "No active window is available.")
        val candidates = linkedMapOf<String, AccessibilityNodeInfo>()
        var matchedInput = false

        fun collect(node: AccessibilityNodeInfo, depth: Int) {
            if (depth > MAX_TREE_DEPTH) return

            val matches = node.text?.toString()?.equals(normalizedTarget, ignoreCase = true) == true ||
                node.contentDescription?.toString()?.equals(normalizedTarget, ignoreCase = true) == true
            if (matches) {
                val isInput = node.isEditable ||
                    node.className?.toString()?.contains("EditText", ignoreCase = true) == true
                if (isInput) {
                    matchedInput = true
                } else {
                    var clickableNode: AccessibilityNodeInfo? = AccessibilityNodeInfo.obtain(node)
                    var ancestorDepth = 0
                    while (clickableNode != null && !clickableNode.isClickable && ancestorDepth < 10) {
                        val className = clickableNode.className?.toString().orEmpty()
                        if (clickableNode.isEditable || className.contains("EditText", ignoreCase = true)) {
                            matchedInput = true
                            clickableNode.recycle()
                            clickableNode = null
                            break
                        }
                        val parent = clickableNode.parent
                        clickableNode.recycle()
                        clickableNode = parent
                        ancestorDepth++
                    }

                    if (clickableNode != null) {
                        if (clickableNode.isClickable) {
                            val bounds = Rect()
                            clickableNode.getBoundsInScreen(bounds)
                            val key = "${clickableNode.viewIdResourceName}:${bounds.flattenToString()}:${clickableNode.className}"
                            if (candidates.containsKey(key)) {
                                clickableNode.recycle()
                            } else {
                                candidates[key] = clickableNode
                            }
                        } else {
                            clickableNode.recycle()
                        }
                    }
                }
            }

            for (index in 0 until node.childCount) {
                val child = node.getChild(index) ?: continue
                try {
                    collect(child, depth + 1)
                } finally {
                    child.recycle()
                }
            }
        }

        try {
            collect(root, 0)
        } finally {
            root.recycle()
        }

        if (candidates.isEmpty()) {
            if (matchedInput) {
                return TapResult(false, "INPUT_TARGET", "This target is an input field; select a button or other clickable control.")
            }
            return TapResult(false, "TARGET_NOT_FOUND", "No clickable element matched that text.")
        }
        if (candidates.size > 1) {
            candidates.values.forEach(AccessibilityNodeInfo::recycle)
            return TapResult(false, "AMBIGUOUS_TARGET", "More than one clickable element matched that text.")
        }

        val candidate = candidates.values.first()
        val accepted = try {
            candidate.performAction(AccessibilityNodeInfo.ACTION_CLICK)
        } finally {
            candidate.recycle()
        }
        return if (accepted) {
            TapResult(true, "ACTION_DISPATCHED", "Android accepted the click action; verify the resulting screen.")
        } else {
            TapResult(false, "ACTION_REJECTED", "The matched element rejected the click action.")
        }
    }

    fun tapElementByTextWithGesture(target: String, callback: (TapResult) -> Unit) {
        val normalizedTarget = target.trim()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            callback(TapResult(false, "GESTURES_UNSUPPORTED", "Gesture fallback requires Android 7.0 or later."))
            return
        }
        val root = service.rootInActiveWindow
        if (root == null) {
            callback(TapResult(false, "NO_ACTIVE_WINDOW", "No active window is available."))
            return
        }

        val candidates = linkedMapOf<String, Rect>()
        var matchedInput = false

        fun visit(node: AccessibilityNodeInfo, depth: Int) {
            if (depth > MAX_TREE_DEPTH) return
            val matches = node.text?.toString()?.equals(normalizedTarget, ignoreCase = true) == true ||
                node.contentDescription?.toString()?.equals(normalizedTarget, ignoreCase = true) == true
            if (matches) {
                val isInput = node.isEditable ||
                    node.className?.toString()?.contains("EditText", ignoreCase = true) == true
                if (isInput) {
                    matchedInput = true
                } else {
                    var clickableNode: AccessibilityNodeInfo? = AccessibilityNodeInfo.obtain(node)
                    var ancestorDepth = 0
                    while (clickableNode != null && !clickableNode.isClickable && ancestorDepth < 10) {
                        val className = clickableNode.className?.toString().orEmpty()
                        if (clickableNode.isEditable || className.contains("EditText", ignoreCase = true)) {
                            matchedInput = true
                            clickableNode.recycle()
                            clickableNode = null
                            break
                        }
                        val parent = clickableNode.parent
                        clickableNode.recycle()
                        clickableNode = parent
                        ancestorDepth++
                    }
                    if (clickableNode?.isClickable == true) {
                        val bounds = Rect()
                        clickableNode.getBoundsInScreen(bounds)
                        if (!bounds.isEmpty) candidates[bounds.flattenToString()] = bounds
                    }
                    clickableNode?.recycle()
                }
            }

            for (index in 0 until node.childCount) {
                val child = node.getChild(index) ?: continue
                try {
                    visit(child, depth + 1)
                } finally {
                    child.recycle()
                }
            }
        }

        try {
            if (normalizedTarget.isNotEmpty()) visit(root, 0)
        } finally {
            root.recycle()
        }

        if (matchedInput && candidates.isEmpty()) {
            callback(TapResult(false, "INPUT_TARGET", "This target is an input field; gestures are blocked for input targets."))
            return
        }
        if (candidates.isEmpty()) {
            callback(TapResult(false, "TARGET_NOT_FOUND", "No clickable element matched that text."))
            return
        }
        if (candidates.size > 1) {
            callback(TapResult(false, "AMBIGUOUS_TARGET", "More than one clickable element matched that text."))
            return
        }

        val bounds = candidates.values.first()
        val path = Path().apply { moveTo(bounds.exactCenterX(), bounds.exactCenterY()) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 100))
            .build()
        val accepted = service.dispatchGesture(
            gesture,
            object : GestureResultCallback() {
                override fun onCompleted(gestureDescription: GestureDescription?) {
                    callback(TapResult(true, "GESTURE_COMPLETED", "Gesture completed at the matched element."))
                }

                override fun onCancelled(gestureDescription: GestureDescription?) {
                    callback(TapResult(false, "GESTURE_CANCELLED", "Android cancelled the gesture."))
                }
            },
            null,
        )
        if (!accepted) callback(TapResult(false, "GESTURE_REJECTED", "Android rejected the gesture."))
    }

    companion object {
        private const val MAX_TREE_DEPTH = 30
        private const val MAX_TREE_ELEMENTS = 500
    }
}
