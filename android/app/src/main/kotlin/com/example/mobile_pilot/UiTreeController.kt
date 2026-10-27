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
    private val snapshots = UiSnapshotController(service)

    fun invalidateSnapshot() = snapshots.invalidate()
    fun readUiTree(): List<Map<String, Any?>> = readUiTreeForPackage(null)
    fun readUiTreeForPackage(targetPackage: String?): List<Map<String, Any?>> = snapshots.read(targetPackage)
    fun tapElementById(screenId: String, nodeId: String, targetPackage: String): TapResult =
        snapshots.tap(screenId, nodeId, targetPackage)

    fun editElementById(screenId: String,nodeId: String,targetPackage: String,action: String,text: String): TapResult =
        snapshots.edit(screenId,nodeId,targetPackage,action,text)

    fun tapElementByText(target: String): TapResult = tapElementForPackage(target, null)

    fun tapElementForPackage(target: String, targetPackage: String?): TapResult {
        val normalizedTarget = target.trim()
        if (normalizedTarget.isEmpty()) {
            return TapResult(false, "EMPTY_TARGET", "Enter text to tap.")
        }

        val root = service.rootInActiveWindow
            ?: return TapResult(false, "NO_ACTIVE_WINDOW", "No active window is available.")
        if (targetPackage != null && root.packageName?.toString() != targetPackage) {
            root.recycle()
            return TapResult(false, "TARGET_NOT_READY", "Target app is no longer foreground.")
        }
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
            if (isTargetForeground(targetPackage)) candidate.performAction(AccessibilityNodeInfo.ACTION_CLICK) else false
        } finally {
            candidate.recycle()
        }
        return if (accepted) {
            TapResult(true, "ACTION_DISPATCHED", "Android accepted the click action; verify the resulting screen.")
        } else {
            TapResult(false, "ACTION_REJECTED", "The matched element rejected the click action.")
        }
    }

    fun tapElementByTextWithGesture(target: String, callback: (TapResult) -> Unit) =
        tapElementWithGestureForPackage(target, null, callback)

    fun tapElementWithGestureForPackage(target: String, targetPackage: String?, callback: (TapResult) -> Unit) {
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

        if (targetPackage != null && root.packageName?.toString() != targetPackage) {
            root.recycle()
            callback(TapResult(false, "TARGET_NOT_READY", "Target app is no longer foreground."))
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

        if (!isTargetForeground(targetPackage)) {
            callback(TapResult(false, "TARGET_NOT_READY", "Target app is no longer foreground."))
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

    private fun isTargetForeground(targetPackage: String?): Boolean {
        if (targetPackage == null) return true
        val root = service.rootInActiveWindow
        return try { root?.packageName?.toString() == targetPackage } finally { root?.recycle() }
    }

    companion object {
        private const val MAX_TREE_DEPTH = 30
        private const val MAX_TREE_ELEMENTS = 500
    }
}
