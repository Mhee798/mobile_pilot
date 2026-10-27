package com.example.mobile_pilot

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.InputMethod
import android.os.Build
import android.os.SystemClock
import android.view.KeyEvent
import android.view.inputmethod.EditorInfo

interface KeyboardEditor {
    fun info(): EditorInfo?
    fun action(target: String, id: Int): Boolean
    fun enter(target: String): Boolean
}

class AndroidKeyboardEditor(private val service: AccessibilityService) : KeyboardEditor {
    override fun info(): EditorInfo? =
        if (Build.VERSION.SDK_INT >= 33) service.inputMethod?.currentInputEditorInfo else null

    override fun action(target: String, id: Int): Boolean {
        val connection = connectionFor(target) ?: return false
        if (id == EditorInfo.IME_ACTION_NEXT) {
            // Some editors advertise Next but ignore performEditorAction(NEXT).
            sendKeyPair(connection, KeyEvent.KEYCODE_TAB)
        } else {
            connection.performEditorAction(id)
        }
        return true // Dispatch only: the editor call is asynchronous.
    }

    override fun enter(target: String): Boolean {
        val connection = connectionFor(target) ?: return false
        sendKeyPair(connection, KeyEvent.KEYCODE_ENTER)
        return true
    }

    private fun connectionFor(target: String): InputMethod.AccessibilityInputConnection? {
        if (Build.VERSION.SDK_INT < 33) return null
        val method = service.inputMethod ?: return null
        if (method.currentInputEditorInfo?.packageName != target) return null
        return method.currentInputConnection
    }

    private fun sendKeyPair(connection: InputMethod.AccessibilityInputConnection, keyCode: Int) {
        val now = SystemClock.uptimeMillis()
        for (action in listOf(KeyEvent.ACTION_DOWN, KeyEvent.ACTION_UP)) {
            connection.sendKeyEvent(KeyEvent(now, now, action, keyCode, 0, 0, -1, 0, KeyEvent.FLAG_SOFT_KEYBOARD))
        }
    }
}
