package com.example.mobile_pilot

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityService.TakeScreenshotCallback
import android.accessibilityservice.AccessibilityService.ScreenshotResult
import android.graphics.Bitmap
import android.graphics.ColorSpace
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Handler
import android.os.SystemClock
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import java.io.ByteArrayOutputStream
import com.example.mobile_pilot.MobilePilotAccessibilityService.TapResult
import com.example.mobile_pilot.MobilePilotAccessibilityService.ScreenCaptureResult
import com.example.mobile_pilot.MobilePilotAccessibilityService.ExternalScreenCapture

class ScreenCaptureController(
    private val service: AccessibilityService,
    private val mainHandler: Handler,
    private val isLikelyTargetAppPackage: (String) -> Boolean,
) {
    private var externalCaptureArmed = false
    private var externalCaptureCandidatePackage: String? = null
    private var externalCaptureTimeout: Runnable? = null
    private var externalCaptureExpiry: Runnable? = null
    private var externalCaptureDeadline = 0L
    private var externalCaptureSequence = 0

    val isArmed: Boolean get() = externalCaptureArmed

    fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val eventPackage = event?.packageName?.toString()
        if (event?.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED && externalCaptureArmed) {
            if (SystemClock.elapsedRealtime() >= externalCaptureDeadline) cancelExternalScreenCapture()
        }
        if (event?.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED && externalCaptureArmed) {
            if (eventPackage != null && eventPackage != service.packageName) {
                externalCaptureCandidatePackage = eventPackage
                externalCaptureTimeout?.let(mainHandler::removeCallbacks)
                val sequence = ++externalCaptureSequence
                val captureTimeout = Runnable {
                    if (externalCaptureArmed && SystemClock.elapsedRealtime() >= externalCaptureDeadline) {
                        cancelExternalScreenCapture()
                        return@Runnable
                    }
                    val candidate = externalCaptureCandidatePackage
                    if (externalCaptureArmed && sequence == externalCaptureSequence && candidate == eventPackage) {
                        val capturePackage = activeCapturePackage()
                        if (capturePackage != null) {
                            captureScreen { capture ->
                                if (externalCaptureArmed && sequence == externalCaptureSequence &&
                                    SystemClock.elapsedRealtime() < externalCaptureDeadline &&
                                    activeCapturePackage() == capturePackage
                                ) {
                                    cancelExternalScreenCapture()
                                    lastExternalCapture = ExternalScreenCapture(capture, capturePackage)
                                }
                            }
                        }
                    }
                    externalCaptureTimeout = null
                }
                externalCaptureTimeout = captureTimeout
                mainHandler.postDelayed(captureTimeout, 700)
            }
        }

    }

    private fun activeCapturePackage(): String? {
        val root = service.rootInActiveWindow
        val activePackage = try {
            root?.packageName?.toString()
        } finally {
            root?.recycle()
        }
        return activePackage?.takeIf {
            it != service.packageName && isLikelyTargetAppPackage(it)
        }
    }

    fun captureScreen(callback: (ScreenCaptureResult) -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            callback(ScreenCaptureResult(false, null, 0, 0, 0, "Screenshot requires Android 11 or later."))
            return
        }

        service.takeScreenshot(
            Display.DEFAULT_DISPLAY,
            service.mainExecutor,
            object : TakeScreenshotCallback {
                override fun onSuccess(screenshot: ScreenshotResult) {
                    val hardwareBuffer = screenshot.hardwareBuffer
                    try {
                        val hardwareBitmap = Bitmap.wrapHardwareBuffer(
                            hardwareBuffer,
                            screenshot.colorSpace ?: ColorSpace.get(ColorSpace.Named.SRGB),
                        ) ?: run {
                            callback(ScreenCaptureResult(false, null, 0, 0, 0, "Could not decode the screenshot."))
                            return
                        }
                        val bitmap = hardwareBitmap.copy(Bitmap.Config.ARGB_8888, false)
                        hardwareBitmap.recycle()
                        if (bitmap == null) {
                            callback(ScreenCaptureResult(false, null, 0, 0, 0, "Could not copy the screenshot."))
                            return
                        }

                        val output = ByteArrayOutputStream()
                        val encoded = bitmap.compress(Bitmap.CompressFormat.JPEG, 88, output)
                        val width = bitmap.width
                        val height = bitmap.height
                        bitmap.recycle()
                        if (!encoded) {
                            callback(ScreenCaptureResult(false, null, 0, 0, 0, "Could not encode the screenshot."))
                            return
                        }

                        val display = service.getSystemService(DisplayManager::class.java)
                            .getDisplay(Display.DEFAULT_DISPLAY)
                        callback(
                            ScreenCaptureResult(
                                true,
                                output.toByteArray(),
                                width,
                                height,
                                display?.rotation ?: 0,
                                null,
                            ),
                        )
                    } catch (error: Exception) {
                        callback(ScreenCaptureResult(false, null, 0, 0, 0, error.message ?: "Screenshot failed."))
                    } finally {
                        hardwareBuffer.close()
                    }
                }

                override fun onFailure(errorCode: Int) {
                    callback(
                        ScreenCaptureResult(
                            false,
                            null,
                            0,
                            0,
                            0,
                            "Android screenshot failed (code $errorCode). Secure or unsupported screens cannot be captured.",
                        ),
                    )
                }
            },
        )
    }

    fun armExternalScreenCapture(): TapResult {
        cancelExternalScreenCapture()
        externalCaptureArmed = true
        externalCaptureDeadline = SystemClock.elapsedRealtime() + EXTERNAL_CAPTURE_TIMEOUT_MS
        val expiry = Runnable { cancelExternalScreenCapture() }
        externalCaptureExpiry = expiry
        mainHandler.postDelayed(expiry, EXTERNAL_CAPTURE_TIMEOUT_MS)
        return TapResult(true, "CAPTURE_ARMED", "Switch to the target app within 30 seconds. MobilePilot will capture its screen when it appears.")
    }

    fun cancelExternalScreenCapture() {
        externalCaptureArmed = false
        externalCaptureDeadline = 0L
        externalCaptureCandidatePackage = null
        externalCaptureTimeout?.let(mainHandler::removeCallbacks)
        externalCaptureTimeout = null
        externalCaptureExpiry?.let(mainHandler::removeCallbacks)
        externalCaptureExpiry = null
        // Ignore screenshot callbacks from a cancelled or expired request.
        externalCaptureSequence++
        lastExternalCapture = null
    }

    fun takeExternalScreenCapture(): ExternalScreenCapture? = takeLastExternalScreenCapture()

    companion object {
        private const val EXTERNAL_CAPTURE_TIMEOUT_MS = 30_000L
        @Volatile
        private var lastExternalCapture: ExternalScreenCapture? = null

        fun takeLastExternalScreenCapture(): ExternalScreenCapture? {
            val capture = lastExternalCapture
            lastExternalCapture = null
            return capture
        }
    }
}
