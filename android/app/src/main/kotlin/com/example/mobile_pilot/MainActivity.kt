package com.example.mobile_pilot

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.content.pm.ApplicationInfo

class MainActivity : FlutterActivity() {
    private var debugInput: MethodChannel? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
            debugInput = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.mobilepilot/debug_input")
        }
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
        AiTaskOverlayBridge.detach()
        debugInput = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 401) AiTaskOverlayBridge.refresh()
    }
}
