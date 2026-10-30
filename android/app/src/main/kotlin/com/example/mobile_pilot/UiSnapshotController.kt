package com.example.mobile_pilot

import android.accessibilityservice.AccessibilityService
import android.graphics.Rect
import android.os.Bundle
import android.view.accessibility.AccessibilityNodeInfo
import com.example.mobile_pilot.MobilePilotAccessibilityService.TapResult
import org.json.JSONArray
import java.security.MessageDigest
import java.util.UUID

/** References belong to one bounded tree snapshot. No Android nodes are retained between calls. */
class UiSnapshotController(private val service: AccessibilityService) {
    private data class Snapshot(val id: String, val packageName: String, val fingerprint: String,
        val nodes: Map<String, Map<String, Any?>>, val anchors: Map<String, Map<String, Any?>>,
        val windowId: Int, val complete: Boolean)
    private data class Tree(val elements: List<Map<String, Any?>>, val fingerprint: String,
        val target: AccessibilityNodeInfo?, val complete: Boolean, val anchors: Map<String, Map<String, Any?>>)
    private var snapshot: Snapshot? = null

    fun invalidate() { snapshot = null }

    fun read(targetPackage: String?): List<Map<String, Any?>> {
        invalidate()
        val root = service.rootInActiveWindow ?: run {
            if (targetPackage != null) throw IllegalStateException("Target app has no active window.")
            return emptyList()
        }
        try {
            val pkg = root.packageName?.toString() ?: throw IllegalStateException("Window has no package.")
            if (targetPackage != null && targetPackage != pkg) throw IllegalStateException("Target app is no longer foreground.")
            val tree = collect(root)
            val id = UUID.randomUUID().toString()
            snapshot = Snapshot(id, pkg, tree.fingerprint,
                tree.elements.associateBy { it["nodeId"] as String }, tree.anchors, root.windowId, tree.complete)
            return tree.elements.map { it + mapOf("screenId" to id, "packageName" to pkg) }
        } finally { root.recycle() }
    }

    fun tap(screenId: String, nodeId: String, targetPackage: String): TapResult = act(screenId,nodeId,targetPackage)

    fun edit(screenId: String,nodeId: String,targetPackage: String,action: String,text: String): TapResult {
        if(action !in setOf("focus","replace","clear") || text.length>2000)
            return TapResult(false,"INVALID_ARGUMENT","ระบุ focus/replace/clear และข้อความไม่เกิน 2000 ตัวอักษร")
        return act(screenId,nodeId,targetPackage,action,text)
    }

    private fun act(screenId: String, nodeId: String, targetPackage: String, inputAction: String? = null, text: String = ""): TapResult {
        val saved = snapshot
        if (saved == null || saved.id != screenId || saved.packageName != targetPackage) {
            return TapResult(false, "STALE_SCREEN", "รายการนี้มาจากหน้าจอเก่า กรุณาอ่าน UI tree ใหม่")
        }
        if (nodeId !in saved.nodes) return TapResult(false, "INVALID_NODE", "ไม่พบรายการนี้ในภาพหน้าจออ้างอิง")
        val root = service.rootInActiveWindow ?: return TapResult(false, "TARGET_NOT_READY", "ไม่พบหน้าจอเป้าหมาย")
        var target: AccessibilityNodeInfo? = null
        try {
            if (root.packageName?.toString() != targetPackage) return TapResult(false, "TARGET_NOT_READY", "แอปเป้าหมายไม่อยู่ด้านหน้า")
            val tree = collect(root, nodeId)
            target = tree.target
            if (tree.fingerprint != saved.fingerprint &&
                !(inputAction == null && root.windowId == saved.windowId && sameAnchoredTarget(saved, tree, nodeId))) {
                invalidate()
                return TapResult(false, "STALE_SCREEN", "หน้าจอเปลี่ยนแล้ว กรุณาอ่าน UI tree ใหม่ก่อนแตะ")
            }
            val node = target ?: return TapResult(false, "INVALID_NODE", "ไม่พบรายการนี้แล้ว")
            if (!node.isVisibleToUser || !node.isEnabled || node.isPassword ||
                (if(inputAction==null) !node.isClickable || node.isEditable else !node.isEditable)) {
                return TapResult(false, "NODE_NOT_ACTIONABLE", "รายการนี้ไม่พร้อมสำหรับคำสั่งนี้ หรือเป็นช่องรหัสผ่าน")
            }
            val currentRoot = service.rootInActiveWindow
            val foregroundMatches = try { currentRoot?.packageName?.toString() == targetPackage } finally { currentRoot?.recycle() }
            if (!foregroundMatches) return TapResult(false, "TARGET_NOT_READY", "แอปเป้าหมายเปลี่ยนไปแล้ว")
            invalidate() // A reference is consumed before dispatch; retry requires a fresh read.
            if(inputAction!=null) {
                val accepted=if(inputAction=="focus") node.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
                else node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT,Bundle().apply {
                    putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,if(inputAction=="clear") "" else text)
                })
                return TapResult(accepted,if(accepted) "INPUT_DISPATCHED" else "INPUT_REJECTED",
                    if(accepted) "Android รับคำสั่งช่องพิมพ์แล้ว กรุณาตรวจผลและอ่าน UI tree ใหม่" else "ช่องนี้ไม่รับคำสั่งแก้ไข")
            }
            return if (node.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
                TapResult(true, "ACTION_DISPATCHED", "Android รับคำสั่งแตะรายการนี้แล้ว ตรวจดูผลบนหน้าจอ")
            } else {
                TapResult(false, "ACTION_REJECTED", "รายการนี้ไม่รับคำสั่งแตะ กรุณาอ่านหน้าจอใหม่")
            }
        } finally { if (target !== root) target?.recycle(); root.recycle() }
    }

    /** Allow unrelated live content to change only when the exact target, all
     * ancestors, and either a unique resource-ID + label or a unique content
     * description with class and nonempty bounds still match. No fuzzy
     * matching, path rebinding, editing, or truncated-tree fallback. */
    private fun sameAnchoredTarget(saved: Snapshot, tree: Tree, nodeId: String): Boolean {
        if (!saved.complete || !tree.complete) return false
        val before = saved.nodes[nodeId] ?: return false
        val current = tree.elements.associateBy { it["nodeId"] as String }
        if (before != current[nodeId] || saved.anchors[nodeId] != tree.anchors[nodeId]) return false
        val resource = before["resourceId"] as? String
        val label = (before["text"] as? String)?.takeIf { it.isNotBlank() }
            ?: (before["contentDescription"] as? String)?.takeIf { it.isNotBlank() }
        if (label == null) return false
        val description = (before["contentDescription"] as? String)?.takeIf { it.isNotBlank() }
        if (resource.isNullOrBlank()) {
            val klass = before["className"] as? String
            val bounds = before["bounds"] as? Map<*, *> ?: return false
            val width = ((bounds["right"] as? Int) ?: 0) - ((bounds["left"] as? Int) ?: 0)
            val height = ((bounds["bottom"] as? Int) ?: 0) - ((bounds["top"] as? Int) ?: 0)
            if (description == null || klass.isNullOrBlank() || width <= 0 || height <= 0) return false
        }
        fun sameIdentity(node: Map<String, Any?>) =
            if (resource.isNullOrBlank()) node["contentDescription"] == description
            else node["resourceId"] == resource && node["text"] == before["text"] && node["contentDescription"] == before["contentDescription"]
        if (saved.nodes.values.count(::sameIdentity) != 1 || tree.elements.count(::sameIdentity) != 1) return false
        var parent = nodeId.substringBeforeLast('.', "")
        while (parent.isNotEmpty()) {
            if (saved.anchors[parent] == null || saved.anchors[parent] != tree.anchors[parent]) return false
            parent = parent.substringBeforeLast('.', "")
        }
        return true
    }

    private fun collect(root: AccessibilityNodeInfo, wanted: String? = null): Tree {
        val elements = mutableListOf<Map<String, Any?>>()
        val anchors = mutableMapOf<String, Map<String, Any?>>()
        val records = JSONArray()
        var count = 0
        var complete = true
        var target: AccessibilityNodeInfo? = null
        fun visit(node: AccessibilityNodeInfo, path: String, depth: Int) {
            if (depth > 30 || count >= 500) { complete = false; return }
            count++
            val text = node.text?.toString()
            val description = node.contentDescription?.toString()
            val resourceId = node.viewIdResourceName
            val bounds = Rect().also(node::getBoundsInScreen)
            val id = "node-$path"
            records.put(JSONArray(listOf(path, text, description, resourceId,
                node.className?.toString(), bounds.flattenToString(), node.isVisibleToUser,
                node.isEnabled, node.isClickable, node.isEditable, node.isPassword, node.isScrollable,
                node.isCheckable, node.isChecked, node.isSelected, node.childCount)))
            anchors[id] = mapOf("text" to text, "description" to description, "resourceId" to resourceId,
                "class" to node.className?.toString(), "bounds" to bounds.flattenToString(),
                "visible" to node.isVisibleToUser, "enabled" to node.isEnabled, "clickable" to node.isClickable,
                "editable" to node.isEditable, "password" to node.isPassword, "scrollable" to node.isScrollable,
                "checkable" to node.isCheckable, "checked" to node.isChecked, "selected" to node.isSelected,
                "children" to node.childCount)
            if (!text.isNullOrBlank() || !description.isNullOrBlank() || resourceId != null || node.isClickable || node.isEditable) {
                elements += mapOf("nodeId" to id, "text" to text, "contentDescription" to description,
                    "resourceId" to resourceId, "className" to node.className?.toString(),
                    "clickable" to node.isClickable, "editable" to node.isEditable, "password" to node.isPassword,
                    "visible" to node.isVisibleToUser, "enabled" to node.isEnabled,
                    "checkable" to node.isCheckable, "checked" to node.isChecked, "selected" to node.isSelected, "depth" to depth,
                    "childCount" to node.childCount,
                    "bounds" to mapOf("left" to bounds.left, "top" to bounds.top, "right" to bounds.right, "bottom" to bounds.bottom))
                if (id == wanted) target = node
            }
            for (index in 0 until node.childCount) {
                if (count >= 500) { complete = false; break }
                val child = node.getChild(index) ?: continue
                try { visit(child, "$path.$index", depth + 1) } finally { if (child !== target) child.recycle() }
            }
        }
        try {
            visit(root, "0", 0)
            val hash = MessageDigest.getInstance("SHA-256").digest(records.toString().toByteArray(Charsets.UTF_8))
                .joinToString("") { "%02x".format(it) }
            return Tree(elements, hash, target, complete, anchors)
        } catch (error: Exception) { if (target !== root) target?.recycle(); throw error }
    }
}
