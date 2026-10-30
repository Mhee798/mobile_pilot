package com.example.mobile_pilot

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import android.app.Activity
import android.Manifest
import android.content.pm.PackageManager
import android.os.Build

/** In-process task status; never persisted as if a task survived process death. */
object AiTaskOverlayBridge {
    private var channel: MethodChannel? = null
    var running: Boolean = false
        private set
    private var status = "AI: ยังไม่ได้เริ่มงาน"
    private var notification: AiTaskNotification? = null
    private var permissionRequested = false

    fun attach(messenger: BinaryMessenger, activity: Activity) {
        notification = AiTaskNotification(activity.applicationContext)
        channel = MethodChannel(messenger, "com.mobilepilot/ai_task").also { connection ->
            connection.setMethodCallHandler { call, result ->
                if (call.method != "setAiTaskStatus") {
                    result.notImplemented()
                } else {
                    val message = call.argument<String>("status")
                    val active = call.argument<Boolean>("running")
                    if (message == null || active == null) {
                        result.error("INVALID_ARGUMENT", "Task status and running are required", null)
                    } else {
                        running = active
                        status = "AI: ${message.take(240)}"
                        if (active && Build.VERSION.SDK_INT >= 33 && !permissionRequested &&
                            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            permissionRequested = true
                            activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 401)
                        }
                        refresh()
                        result.success(null)
                    }
                }
            }
        }
    }

    fun refresh() {
        MobilePilotAccessibilityService.activeService?.setAiTaskStatus(status)
        notification?.publish(status, running)
    }

    fun dismissNotification() { notification?.dismiss() }

    fun requestStop() {
        if (!running) { refresh(); return }
        val connection = channel ?: return
        status = "AI: กำลังขอหยุดงาน"
        refresh()
        connection.invokeMethod("stopAiTask", null, object : MethodChannel.Result {
            override fun success(result: Any?) = Unit // Dart publishes actual completion.
            override fun error(code: String, message: String?, details: Any?) {
                status = "AI: ส่งคำขอหยุดไม่สำเร็จ โปรดกลับเข้าแอป"
                refresh()
            }
            override fun notImplemented() {
                status = "AI: ติดต่อ AI ไม่ได้ โปรดกลับเข้าแอป"
                refresh()
            }
        })
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        running = false
        status = "AI: ตัวควบคุมไม่ได้เชื่อมต่อ"
        refresh()
        notification = null
    }
}
