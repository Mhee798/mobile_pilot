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
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
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
                            result.success(mapOf("label" to app.label, "packageName" to app.packageName))
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
                    result.success(service.readUiTree())
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
                    val armResult = service.armExternalScreenCapture()
                    result.success(mapOf("code" to armResult.code, "message" to armResult.message))
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

            "queuePointTap" -> {
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
                    val tapResult = service.queuePointTap(x, y, width, height, rotation, targetPackage)
                    if (tapResult.success) {
                        result.success(mapOf("code" to tapResult.code, "message" to tapResult.message))
                    } else {
                        result.error(tapResult.code, tapResult.message, null)
                    }
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
                        val executionTargetPackage = service.getQueuedUtilityTargetPackage() ?: targetPackage
                        val launchIntent = activity.packageManager.getLaunchIntentForPackage(executionTargetPackage)
                        if (launchIntent == null) {
                            val failure = service.failQueuedUtilityActionToLaunch()
                            result.error(failure.code, failure.message, null)
                        } else {
                            try {
                                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
                                activity.startActivity(launchIntent)
                                result.success(mapOf("code" to actionResult.code, "message" to actionResult.message))
                            } catch (error: ActivityNotFoundException) {
                                val failure = service.failQueuedUtilityActionToLaunch()
                                result.error(failure.code, error.message ?: failure.message, null)
                            } catch (error: SecurityException) {
                                val failure = service.failQueuedUtilityActionToLaunch()
                                result.error(failure.code, error.message ?: failure.message, null)
                            }
                        }
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
                    val tapResult = service.tapElementByText(text)
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
                    service.tapElementByTextWithGesture(text) { tapResult ->
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
