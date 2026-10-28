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
        AiTaskOverlayBridge.attach(flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.mobilepilot/settings")
            .setMethodCallHandler(MobilePilotMethodCallHandler(this))
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) == 0) return
        val prompt = intent.getStringExtra("mobilepilot.testPrompt") ?: return
        if (prompt.length <= 2000) debugInput?.invokeMethod("fillPrompt", prompt)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        AiTaskOverlayBridge.detach()
        debugInput = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
