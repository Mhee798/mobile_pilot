package com.example.mobile_pilot

import android.accessibilityservice.AccessibilityService
import android.os.Build
import android.view.accessibility.AccessibilityNodeInfo
import android.view.inputmethod.EditorInfo
import com.example.mobile_pilot.MobilePilotAccessibilityService.TapResult

class KeyboardActionController @JvmOverloads constructor(private val service: AccessibilityService, private val editor: KeyboardEditor = AndroidKeyboardEditor(service)) {
    fun perform(target: String, action: String): TapResult {
        if(action !in setOf("default","search","next","enter")) return TapResult(false,"INVALID_ARGUMENT","ปุ่มคีย์บอร์ดไม่ถูกต้อง")
        val root=service.rootInActiveWindow ?: return TapResult(false,"TARGET_NOT_READY","ไม่พบหน้าจอเป้าหมาย")
        var focused: AccessibilityNodeInfo?=null
        try {
            if(root.packageName?.toString()!=target) return TapResult(false,"TARGET_NOT_READY","แอปเป้าหมายไม่ได้อยู่ด้านหน้า")
            focused=root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            val field=focused ?: return TapResult(false,"INPUT_NOT_FOCUSED","เลือกช่องพิมพ์ในแอปเป้าหมายก่อน")
            if(!field.isEditable || !field.isEnabled || field.isPassword || field.packageName?.toString()!=target)
                return TapResult(false,"INPUT_NOT_ACTIONABLE","ช่องที่โฟกัสไม่พร้อม หรือเป็นช่องรหัสผ่าน")
            if(action=="default") {
                if(Build.VERSION.SDK_INT<30 || field.actionList.none {it.id==AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.id})
                    return TapResult(false,"IME_UNSUPPORTED","ช่องนี้ไม่เปิดเผยปุ่มคีย์บอร์ดผ่าน Accessibility")
                val latestRoot = service.rootInActiveWindow
                val targetStillActive = try { latestRoot?.packageName?.toString() == target } finally { latestRoot?.recycle() }
                if (!targetStillActive) return TapResult(false, "TARGET_NOT_READY", "แอปเป้าหมายเปลี่ยนไปแล้ว")
                val accepted=field.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.id)
                return TapResult(accepted,if(accepted) "IME_DISPATCHED" else "IME_REJECTED","Android ${if(accepted) "รับ" else "ไม่รับ"}คำสั่งปุ่มปัจจุบันของช่องนี้; โปรดตรวจผล")
            }
            if(Build.VERSION.SDK_INT<33) return TapResult(false,"IME_UNSUPPORTED","ปุ่มที่ระบุเองต้องใช้ Android 13 ขึ้นไป")
            val info=editor.info()
            if(info?.packageName!=target) return TapResult(false,"IME_UNAVAILABLE","ไม่พบการเชื่อมต่อช่องพิมพ์ของแอปเป้าหมาย")
            val currentRoot=service.rootInActiveWindow
            val stillTarget=try {currentRoot?.packageName?.toString()==target} finally {currentRoot?.recycle()}
            if(!stillTarget) return TapResult(false,"TARGET_NOT_READY","แอปเป้าหมายเปลี่ยนไปแล้ว")
            val dispatched=if(action=="enter") editor.enter(target) else {
                val requested=if(action=="search") EditorInfo.IME_ACTION_SEARCH else EditorInfo.IME_ACTION_NEXT
                if(info.imeOptions and EditorInfo.IME_MASK_ACTION != requested)
                    return TapResult(false,"IME_ACTION_MISMATCH","ช่องนี้ไม่ได้เสนอปุ่ม $action เลือกปุ่มปัจจุบันของช่องหรือโฟกัสช่องใหม่")
                editor.action(target,requested)
            }
            if(!dispatched) return TapResult(false,"IME_UNAVAILABLE","การเชื่อมต่อช่องพิมพ์ไม่พร้อมหรือเปลี่ยนไปแล้ว")
            return TapResult(true,"IME_DISPATCHED","ส่งปุ่ม $action ให้ช่องที่โฟกัสแล้ว; โปรดตรวจผลบนหน้าจอ")
        } finally {if(focused!==root) focused?.recycle();root.recycle()}
    }
}
