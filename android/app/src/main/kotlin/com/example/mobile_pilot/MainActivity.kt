package com.example.mobile_pilot

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.content.pm.ApplicationInfo

class MainActivity : FlutterActivity() {
    companion object {
        var isVisible = false
            private set
        private var overlayPick: Pair<Boolean, (Any?) -> Unit>? = null

        fun pickForOverlay(context: android.content.Context, image: Boolean, done: (Any?) -> Unit) {
            if (overlayPick != null) { done(null); return }
            val pending = image to done
            overlayPick = pending
            try {
                context.startActivity(Intent(context, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP))
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                    if (overlayPick === pending) {
                        overlayPick = null
                        done(null)
                    }
                }, 5000)
            } catch (_: RuntimeException) {
                overlayPick = null
                done(null)
            }
        }
    }

    override fun onStart() {
        isVisible = true
        MobilePilotAccessibilityService.activeService?.refreshFloatingVisibility()
        super.onStart()
    }

    override fun onStop() {
        super.onStop()
        isVisible = false
        MobilePilotAccessibilityService.activeService?.refreshFloatingVisibility()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus) return
        val (image, done) = overlayPick ?: return
        overlayPick = null
        FloatingChatBridge.pick(image, done)
    }

    private var debugInput: MethodChannel? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
            debugInput = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.mobilepilot/debug_input")
        }
        FloatingChatBridge.attach(flutterEngine.dartExecutor.binaryMessenger)
        AiTaskOverlayBridge.attach(flutterEngine.dartExecutor.binaryMessenger, this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.mobilepilot/settings")
            .setMethodCallHandler(MobilePilotMethodCallHandler(this))
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) == 0) return
        if (intent.getBooleanExtra("mobilepilot.testLiveUpdate", false) && !AiTaskOverlayBridge.running) {
            // Debug-only 30-second system-surface probe; never starts an AI task.
            AiTaskNotification(applicationContext).publish("ทดสอบ Live Update · ไม่มีงาน AI กำลังทำงาน", true)
            android.os.Handler(mainLooper).postDelayed({ AiTaskOverlayBridge.refresh() }, 30_000)
        }
        val prompt = intent.getStringExtra("mobilepilot.testPrompt") ?: return
        if (prompt.length <= 2000) debugInput?.invokeMethod("fillPrompt", prompt)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        FloatingChatBridge.detach()
        AiTaskOverlayBridge.detach()
        debugInput = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 401) AiTaskOverlayBridge.refresh()
    }
}
