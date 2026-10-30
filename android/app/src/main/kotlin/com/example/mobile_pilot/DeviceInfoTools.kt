package com.example.mobile_pilot

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.StatFs

object DeviceInfoTools {
    fun read(context: Context): Map<String, Any?> {
        val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val status = battery?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val storage = StatFs(Environment.getDataDirectory().path)
        return mapOf(
            "manufacturer" to Build.MANUFACTURER, "model" to Build.MODEL,
            "android_version" to Build.VERSION.RELEASE, "api_level" to Build.VERSION.SDK_INT,
            "battery_percent" to if (level >= 0 && scale > 0) level * 100 / scale else null,
            "charging" to when (status) { BatteryManager.BATTERY_STATUS_CHARGING, BatteryManager.BATTERY_STATUS_FULL -> true; BatteryManager.BATTERY_STATUS_DISCHARGING, BatteryManager.BATTERY_STATUS_NOT_CHARGING -> false; else -> null },
            "storage_available_bytes" to storage.availableBytes,
            "storage_total_bytes" to storage.totalBytes,
        )
    }

    fun volume(context: Context): Map<String, Any> {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        return mapOf("current" to audio.getStreamVolume(AudioManager.STREAM_MUSIC),
            "maximum" to audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC))
    }
}
