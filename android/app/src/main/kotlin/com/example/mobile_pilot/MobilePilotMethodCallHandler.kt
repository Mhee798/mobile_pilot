package com.example.mobile_pilot

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context.MODE_PRIVATE
import android.content.Intent
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MobilePilotMethodCallHandler(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private fun awaitTarget(target: String, callback: (Boolean) -> Unit) {
        val service = MobilePilotAccessibilityService.activeService
        if (service == null) callback(false) else service.awaitTargetReady(target, callback)
    }

    private fun sessionAllows(call: MethodCall, result: MethodChannel.Result): Boolean {
        val runId = call.argument<String>("runId")
        val service = MobilePilotAccessibilityService.activeService
        val target = call.argument<String>("targetPackage") ?: call.argument<String>("packageName")
        if (runId != null && service?.allowsCommandSession(runId, target) != true) {
            result.error("SEQUENCE_CANCELLED", "ชุดทดสอบหยุดหรือหมดอายุแล้ว", null)
            return false
        }
        val tools = setOf("launchApp", "getUiTree", "waitForUi", "scrollUntilUi", "tapElementById", "editElementById", "tapElementByText",
            "tapElementByTextWithGesture", "armScreenCapture", "queuePointTap", "queueDoubleTap", "queueLongPress", "queueSwipe", "queueDrag", "queuePinch", "queueScreenAction", "startSettingsTapTest")
        if (service?.isScrollingForUi == true && call.method in tools && call.method != "launchApp") {
            result.error("SCROLL_BUSY", "หยุดเลื่อนค้นหาก่อนใช้คำสั่งอื่น", null)
            return false
        }
        if (runId != null && call.method in tools && target.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "Session tools require their target package.", null)
            return false
        }
        if (runId == null && service?.hasCommandSession() == true && call.method in tools) {
            result.error("SEQUENCE_BUSY", "หยุดชุดทดสอบก่อนใช้คำสั่งแยก", null)
            return false
        }
        return true
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (!sessionAllows(call, result)) return
        val target = call.argument<String>("targetPackage")
        if (target != null && call.method in setOf("getUiTree", "tapElementByText", "tapElementByTextWithGesture", "tapElementById", "editElementById")) {
            if (target.isBlank() || target == activity.packageName) {
                result.error("INVALID_TARGET", "Select an external target app first.", null)
                return
            }
            awaitTarget(target) { ready ->
                if (!sessionAllows(call, result)) return@awaitTarget
                if (!ready) {
                    result.error("TARGET_NOT_READY", "แอปเป้าหมายไม่พร้อมภายใน 10 วินาที หรือคำขอถูกยกเลิก", null)
                } else {
                    handleReadyCall(call, result)
                }
            }
            return
        }
        handleReadyCall(call, result)
    }

    private fun handleReadyCall(call: MethodCall, result: MethodChannel.Result) {
        if (!sessionAllows(call, result)) return
        val target = call.argument<String>("targetPackage")
        when (call.method) {
            "navigateGlobally" -> {
                val service = MobilePilotAccessibilityService.activeService
                val action = call.argument<String>("action")
                if (service == null) result.error("SERVICE_UNAVAILABLE", "เปิด Accessibility ก่อน", null)
                else if (action == null) result.error("INVALID_ARGUMENT", "ต้องระบุคำสั่งนำทาง", null)
                else {
                    val response = service.navigateGlobally(action)
                    if (response.success) result.success(mapOf("code" to response.code, "message" to response.message))
                    else result.error(response.code, response.message, null)
                }
            }

            "beginCommandSession" -> {
                val id = call.argument<String>("sessionId")
                val service = MobilePilotAccessibilityService.activeService
                if (service == null) result.error("SERVICE_UNAVAILABLE", "เปิด Accessibility ก่อน", null)
                else if (id.isNullOrBlank() || target.isNullOrBlank()) result.error("INVALID_ARGUMENT", "ต้องระบุชุดทดสอบและแอปเป้าหมาย", null)
                else if (!service.beginCommandSession(id, target)) result.error("SEQUENCE_BUSY", "มีคำสั่งอื่นรออยู่ หรือแอปเป้าหมายไม่ถูกต้อง", null)
                else result.success(null)
            }

            "finishCommandSession" -> {
                val id = call.argument<String>("sessionId")
                val service = MobilePilotAccessibilityService.activeService
                if (id == null || service?.finishCommandSession(id) != true) result.error("SEQUENCE_CANCELLED", "ชุดทดสอบหยุดแล้ว", null)
                else result.success(null)
            }

            "cancelCommandSession" -> {
                call.argument<String>("sessionId")?.let { MobilePilotAccessibilityService.activeService?.cancelCommandSession(it) }
                result.success(null)
            }

            "editElementById" -> {
                val service=MobilePilotAccessibilityService.activeService
                val screenId=call.argument<String>("screenId");val nodeId=call.argument<String>("nodeId")
                val action=call.argument<String>("action");val text=call.argument<String>("text") ?: ""
                if(service==null) result.error("SERVICE_UNAVAILABLE","เปิด Accessibility ก่อน",null)
                else if(screenId.isNullOrBlank() || nodeId.isNullOrBlank() || target.isNullOrBlank() || action==null)
                    result.error("INVALID_ARGUMENT","ต้องระบุแอปและรหัสช่องจาก UI tree",null)
                else {
                    val response=service.editElementById(screenId,nodeId,target,action,text)
                    if(response.success) result.success(mapOf("code" to response.code,"message" to response.message))
                    else result.error(response.code,response.message,null)
                }
            }

            "tapElementById" -> {
                val service = MobilePilotAccessibilityService.activeService
                val screenId = call.argument<String>("screenId")
                val nodeId = call.argument<String>("nodeId")
                if (service == null) result.error("SERVICE_UNAVAILABLE", "เปิด Accessibility ก่อน", null)
                else if (screenId.isNullOrBlank() || nodeId.isNullOrBlank() || target.isNullOrBlank()) {
                    result.error("INVALID_ARGUMENT", "ต้องระบุหน้าจอ รายการ และแอปเป้าหมาย", null)
                } else {
                    val response = service.tapElementById(screenId, nodeId, target)
                    if (response.success) result.success(mapOf("code" to response.code, "message" to response.message))
                    else result.error(response.code, response.message, null)
                }
            }

            "waitForUi", "scrollUntilUi" -> {
                val service = MobilePilotAccessibilityService.activeService
                val id = call.argument<String>("requestId")
                val selector = call.argument<String>("selector")
                val value = call.argument<String>("value")
                val timeoutMs = call.argument<Number>("timeoutMs")?.toLong()
                if (service == null) {
                    result.error("SERVICE_UNAVAILABLE", "เปิด MobilePilot Accessibility ก่อนรอ UI", null)
                } else if (id == null || target == null || selector == null || value == null || timeoutMs == null) {
                    result.error("INVALID_ARGUMENT", "ต้องระบุแอปเป้าหมาย เงื่อนไข และเวลารอ", null)
                } else {
                    if (call.method == "scrollUntilUi") {
                        val direction = call.argument<String>("direction")
                        val maxScrolls = call.argument<Number>("maxScrolls")?.toInt()
                        if (direction == null || maxScrolls == null) result.error("INVALID_ARGUMENT", "ต้องระบุทิศทางและจำนวนครั้ง", null)
                        else service.scrollUntilUi(id, target, selector, value, timeoutMs, direction, maxScrolls, call.argument<String>("distance") ?: "app") { result.success(it) }
                    } else service.waitForUi(id, target, selector, value, timeoutMs, call.argument<String>("condition") ?: "present") { response -> result.success(response) }
                }
            }

            "cancelUiWait" -> {
                val id = call.argument<String>("requestId")
                if (id.isNullOrBlank()) {
                    result.error("INVALID_ARGUMENT", "ต้องระบุคำขอที่จะยกเลิก", null)
                } else {
                    MobilePilotAccessibilityService.activeService?.cancelUiWait(id)
                    result.success(null)
                }
            }

            "setTargetApp" -> {
                val selected = call.argument<String>("packageName")
                if (selected.isNullOrBlank() || selected == activity.packageName ||
                    getLaunchableApps().none { it.packageName == selected }
                ) {
                    result.error("INVALID_TARGET", "Select an app from the launcher results.", null)
                } else {
                    MobilePilotAccessibilityService.activeService?.cancelPendingCommands()
                    result.success(null)
                }
            }

            "findLaunchableApps" -> {
                val query = call.argument<String>("query")?.trim()
                if (query.isNullOrEmpty()) {
                    result.error("EMPTY_QUERY", "พิมพ์ชื่อแอปที่ต้องการค้นหาก่อน", null)
                } else {
                    result.success(
                        findLaunchableApps(query).map { app ->
                            mapOf("label" to app.label, "packageName" to app.packageName)
                        },
                    )
                }
            }

            "launchApp" -> {
                val selectedPackage = call.argument<String>("packageName")
                if (selectedPackage.isNullOrBlank()) {
                    result.error("INVALID_ARGUMENT", "เลือกแอปที่จะเปิดก่อน", null)
                } else {
                    val app = getLaunchableApps().firstOrNull { it.packageName == selectedPackage }
                    val launchIntent = activity.packageManager.getLaunchIntentForPackage(selectedPackage)
                    if (app == null || launchIntent == null) {
                        result.error("APP_NOT_LAUNCHABLE", "ไม่พบแอปที่เปิดได้ในรายการ Launcher", null)
                    } else {
                        try {
                            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            activity.startActivity(launchIntent)
                            awaitTarget(selectedPackage) { ready ->
                                if (!sessionAllows(call, result)) return@awaitTarget
                                if (ready) {
                                    result.success(mapOf("label" to app.label, "packageName" to app.packageName, "code" to "TARGET_READY"))
                                } else {
                                    result.error("TARGET_NOT_READY", "เปิดแอปแล้ว แต่ยังยืนยันว่าอยู่ด้านหน้าไม่ได้ภายใน 10 วินาที หรือคำขอถูกยกเลิก", null)
                                }
                            }
                        } catch (error: ActivityNotFoundException) {
                            result.error("APP_LAUNCH_FAILED", error.message, null)
                        }
                    }
                }
            }

            "openAccessibilitySettings" -> {
                try {
                    activity.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(null)
                } catch (error: ActivityNotFoundException) {
                    result.error(
                        "SETTINGS_UNAVAILABLE",
                        "Accessibility settings are not available on this device.",
                        null,
                    )
                }
            }

            "isAccessibilityServiceEnabled" -> {
                val enabledServices = Settings.Secure.getString(
                    activity.contentResolver,
                    Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
                ).orEmpty()
                val serviceName = ComponentName(
                    activity,
                    MobilePilotAccessibilityService::class.java,
                ).flattenToString()
                val isEnabled = enabledServices
                    .split(':')
                    .any { it.equals(serviceName, ignoreCase = true) }

                result.success(isEnabled)
            }

            "getFloatingControlsEnabled" -> {
                val enabled = activity.getSharedPreferences(
                    MobilePilotAccessibilityService.FLOATING_CONTROLS_PREFS,
                    MODE_PRIVATE,
                ).getBoolean(MobilePilotAccessibilityService.FLOATING_CONTROLS_ENABLED_KEY, false)
                result.success(enabled)
            }

            "setFloatingControlsEnabled" -> {
                val enabled = call.argument<Boolean>("enabled")
                val service = MobilePilotAccessibilityService.activeService
                if (enabled == null) {
                    result.error("INVALID_ARGUMENT", "A floating-controls state is required.", null)
                } else if (service == null) {
                    result.error(
                        "SERVICE_UNAVAILABLE",
                        "Enable MobilePilot Accessibility before showing the floating controls.",
                        null,
                    )
                } else {
                    val toggleResult = service.setFloatingControlsEnabled(enabled)
                    if (toggleResult.success) {
                        result.success(mapOf("enabled" to enabled, "message" to toggleResult.message))
                    } else {
                        result.error(toggleResult.code, toggleResult.message, null)
                    }
                }
            }

            "getUiTree" -> {
                val service = MobilePilotAccessibilityService.activeService
                if (service == null) {
                    result.error(
                        "SERVICE_UNAVAILABLE",
                        "Enable MobilePilot Accessibility before reading the screen.",
                        null,
                    )
                } else {
                    try {
                        result.success(service.readUiTreeForPackage(target))
                    } catch (error: IllegalStateException) {
                        result.error("TARGET_NOT_READY", error.message, null)
                    }
                }
            }

            "armScreenCapture" -> {
                val service = MobilePilotAccessibilityService.activeService
                if (service == null) {
                    result.error(
                        "SERVICE_UNAVAILABLE",
                        "Enable MobilePilot Accessibility before capturing another app.",
                        null,
                    )
                } else {
                    val armResult = service.armExternalScreenCapture(call.argument<String>("targetPackage"))
                    if (armResult.success) {
                        result.success(mapOf("code" to armResult.code, "message" to armResult.message))
                    } else {
                        result.error(armResult.code, armResult.message, null)
                    }
                }
            }

            "cancelScreenCapture" -> {
                MobilePilotAccessibilityService.activeService?.cancelExternalScreenCapture()
                MobilePilotAccessibilityService.takeLastExternalScreenCapture()
                result.success(null)
            }

            "getCapturedScreen" -> {
                val service = MobilePilotAccessibilityService.activeService
                val externalCapture = service?.takeExternalScreenCapture()
                    ?: MobilePilotAccessibilityService.takeLastExternalScreenCapture()
                if (externalCapture == null) {
                    result.success(null)
                } else {
                    val capture = externalCapture.capture
                    if (capture.success && capture.jpeg != null) {
                        result.success(
                            mapOf(
                                "jpeg" to capture.jpeg,
                                "width" to capture.width,
                                "height" to capture.height,
                                "rotation" to capture.rotation,
                                "packageName" to externalCapture.packageName,
                            ),
                        )
                    } else {
                        result.error("SCREEN_CAPTURE_FAILED", capture.error ?: "Could not capture the screen.", null)
                    }
                }
            }

            "queuePointTap", "queueDoubleTap", "queueLongPress", "queueSwipe", "queueDrag", "queuePinch" -> {
                val service = MobilePilotAccessibilityService.activeService
                val x = call.argument<Number>("x")?.toDouble()
                val y = call.argument<Number>("y")?.toDouble()
                val width = call.argument<Int>("width")
                val height = call.argument<Int>("height")
                val rotation = call.argument<Int>("rotation")
                val targetPackage = call.argument<String>("packageName")
                if (service == null) {
                    result.error(
                        "SERVICE_UNAVAILABLE",
                        "Enable MobilePilot Accessibility before queuing a coordinate tap.",
                        null,
                    )
                } else if (x == null || y == null || width == null || height == null || rotation == null || targetPackage == null) {
                    result.error("INVALID_ARGUMENT", "A point and captured app metadata are required.", null)
                } else {
                    val duration = call.argument<Number>("durationMs")
                    val tapResult = if (call.method == "queueDoubleTap") {
                        service.queueDoubleTap(x, y, width, height, rotation, targetPackage)
                    } else if (call.method == "queuePinch") {
                        val span = call.argument<Number>("startSpan")?.toDouble()
                        val scale = call.argument<Number>("scale")?.toDouble()
                        val axis = call.argument<String>("axis")
                        if (span == null || scale == null || axis == null || (duration !is Int && duration !is Long)) {
                            result.error("INVALID_ARGUMENT", "ต้องระบุระยะนิ้ว ระดับซูม แนว และเวลาสองนิ้ว", null)
                            return
                        }
                        service.queuePinch(x, y, width, height, rotation, targetPackage, duration.toLong(), span, scale, axis)
                    } else if (call.method == "queueSwipe" || call.method == "queueDrag") {
                        val endX = call.argument<Number>("endX")?.toDouble()
                        val endY = call.argument<Number>("endY")?.toDouble()
                        if (endX == null || endY == null || (duration !is Int && duration !is Long)) {
                            result.error("INVALID_ARGUMENT", "ต้องระบุจุดปลายและเวลาปัดเป็นจำนวนเต็มมิลลิวินาที", null)
                            return
                        }
                        if (call.method == "queueDrag") {
                            val hold=call.argument<Number>("holdMs")
                            if(hold !is Int && hold !is Long) { result.error("INVALID_DRAG","ต้องระบุเวลากดค้างก่อนลาก",null);return }
                            service.queueDrag(x,y,endX,endY,width,height,rotation,targetPackage,hold.toLong(),duration.toLong())
                        } else service.queueSwipe(x, y, endX, endY, width, height, rotation, targetPackage, duration.toLong())
                    } else if (call.method == "queueLongPress") {
                        if (duration !is Int && duration !is Long) {
                            result.error("INVALID_DURATION", "ต้องระบุเวลากดค้างเป็นจำนวนเต็มมิลลิวินาที", null)
                            return
                        }
                        service.queueLongPress(x, y, width, height, rotation, targetPackage, duration.toLong())
                    } else service.queuePointTap(x, y, width, height, rotation, targetPackage)
                    if (tapResult.success) {
                        result.success(mapOf("code" to tapResult.code, "message" to tapResult.message))
                    } else {
                        result.error(tapResult.code, tapResult.message, null)
                    }
                }
            }

            "cancelScreenActions" -> {
                val service = MobilePilotAccessibilityService.activeService
                if (service == null) {
                    result.error("SERVICE_UNAVAILABLE", "Accessibility service is unavailable.", null)
                } else {
                    service.cancelQueuedActions()
                    result.success(null)
                }
            }

            "getPointTapResult" -> {
                val service = MobilePilotAccessibilityService.activeService
                val tapResult = service?.getPointTapResult()
                result.success(
                    tapResult?.let { mapOf("code" to it.code, "message" to it.message) },
                )
            }

            "queueScreenAction" -> {
                val service = MobilePilotAccessibilityService.activeService
                val action = call.argument<String>("action")
                val targetPackage = call.argument<String>("packageName")
                val width = call.argument<Int>("width")
                val height = call.argument<Int>("height")
                val rotation = call.argument<Int>("rotation")
                val text = call.argument<String>("text")
                if (service == null) {
                    result.error("SERVICE_UNAVAILABLE", "Enable MobilePilot Accessibility before queuing a screen action.", null)
                } else if (action == null || targetPackage == null || width == null || height == null || rotation == null) {
                    result.error("INVALID_ARGUMENT", "A target app and captured-screen metadata are required.", null)
                } else {
                    val actionResult = service.queueUtilityAction(action, targetPackage, width, height, rotation, text)
                    if (actionResult.success) {
                        result.success(mapOf("code" to actionResult.code, "message" to actionResult.message))
                    } else {
                        result.error(actionResult.code, actionResult.message, null)
                    }
                }
            }

            "tapElementByText" -> {
                val text = call.argument<String>("text")
                val service = MobilePilotAccessibilityService.activeService
                if (text == null) {
                    result.error("INVALID_ARGUMENT", "A text target is required.", null)
                } else if (service == null) {
                    result.error(
                        "SERVICE_UNAVAILABLE",
                        "Enable MobilePilot Accessibility before interacting with the screen.",
                        null,
                    )
                } else {
                    val tapResult = service.tapElementForPackage(text, target)
                    if (tapResult.success) {
                        result.success(
                            mapOf("code" to tapResult.code, "message" to tapResult.message),
                        )
                    } else {
                        result.error(tapResult.code, tapResult.message, null)
                    }
                }
            }

            "tapElementByTextWithGesture" -> {
                val text = call.argument<String>("text")
                val service = MobilePilotAccessibilityService.activeService
                if (text == null) {
                    result.error("INVALID_ARGUMENT", "A text target is required.", null)
                } else if (service == null) {
                    result.error(
                        "SERVICE_UNAVAILABLE",
                        "Enable MobilePilot Accessibility before interacting with the screen.",
                        null,
                    )
                } else {
                    service.tapElementWithGestureForPackage(text, target) { tapResult ->
                        if (tapResult.success) {
                            result.success(
                                mapOf("code" to tapResult.code, "message" to tapResult.message),
                            )
                        } else {
                            result.error(tapResult.code, tapResult.message, null)
                        }
                    }
                }
            }

            "startSettingsTapTest" -> {
                val text = call.argument<String>("text")
                val service = MobilePilotAccessibilityService.activeService
                val settingsIntent = Intent(Settings.ACTION_SETTINGS)
                val settingsPackage = settingsIntent.resolveActivity(activity.packageManager)?.packageName
                if (text == null) {
                    result.error("INVALID_ARGUMENT", "A text target is required.", null)
                } else if (service == null) {
                    result.error(
                        "SERVICE_UNAVAILABLE",
                        "Enable MobilePilot Accessibility before testing Settings.",
                        null,
                    )
                } else if (settingsPackage == null) {
                    result.error("SETTINGS_UNAVAILABLE", "Android Settings could not be opened.", null)
                } else {
                    val startResult = service.beginSettingsTapTest(text, settingsPackage)
                    if (!startResult.success) {
                        result.error(startResult.code, startResult.message, null)
                    } else {
                        try {
                            activity.startActivity(settingsIntent)
                            result.success(mapOf("message" to startResult.message))
                        } catch (error: ActivityNotFoundException) {
                            service.cancelSettingsTapTest("เปิด Android Settings ไม่สำเร็จ")
                            result.error("SETTINGS_UNAVAILABLE", error.message, null)
                        }
                    }
                }
            }

            "getSettingsTapTestResult" -> {
                val preferences = activity.getSharedPreferences(
                    MobilePilotAccessibilityService.SETTINGS_TEST_PREFS,
                    MODE_PRIVATE,
                )
                result.success(
                    mapOf(
                        "status" to preferences.getString("status", ""),
                        "message" to preferences.getString("message", ""),
                        "target" to preferences.getString("target", ""),
                    ),
                )
            }

            else -> result.notImplemented()
        }
    }

    private fun findLaunchableApps(query: String): List<LaunchableApp> {
        val normalizedQuery = query.trim()
        return getLaunchableApps()
            .filter { it.label.contains(normalizedQuery, ignoreCase = true) }
            .sortedWith(
                compareByDescending<LaunchableApp> { it.label.equals(normalizedQuery, ignoreCase = true) }
                    .thenBy { it.label.lowercase() },
            )
            .take(15)
    }

    private fun getLaunchableApps(): List<LaunchableApp> {
        val launcherIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        @Suppress("DEPRECATION")
        val activities = activity.packageManager.queryIntentActivities(launcherIntent, 0)
        val uniqueApps = linkedMapOf<String, LaunchableApp>()
        for (resolveInfo in activities) {
            val activityInfo = resolveInfo.activityInfo ?: continue
            val appPackage = activityInfo.packageName ?: continue
            if (appPackage == activity.packageName || !activityInfo.enabled || !activityInfo.applicationInfo.enabled) continue
            val label = activityInfo.loadLabel(activity.packageManager)?.toString()?.trim().orEmpty()
            if (label.isEmpty()) continue
            uniqueApps.putIfAbsent(appPackage, LaunchableApp(label, appPackage))
        }

        return uniqueApps.values
            .sortedBy { it.label.lowercase() }
    }

    private data class LaunchableApp(val label: String, val packageName: String)
}
