package com.example.mobile_pilot

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.os.Build

/** Only documented settings destinations are exposed to the model. */
object SystemSettingsShortcuts {
    private val actions = mapOf(
        "general" to Settings.ACTION_SETTINGS,
        "wifi" to Settings.ACTION_WIFI_SETTINGS,
        "bluetooth" to Settings.ACTION_BLUETOOTH_SETTINGS,
        "display" to Settings.ACTION_DISPLAY_SETTINGS,
        "sound" to Settings.ACTION_SOUND_SETTINGS,
        "location" to Settings.ACTION_LOCATION_SOURCE_SETTINGS,
        "accessibility" to Settings.ACTION_ACCESSIBILITY_SETTINGS,
        "apps" to Settings.ACTION_APPLICATION_SETTINGS,
        "battery_saver" to Settings.ACTION_BATTERY_SAVER_SETTINGS,
        "cast" to Settings.ACTION_CAST_SETTINGS,
        "nfc" to Settings.ACTION_NFC_SETTINGS,
        "nfc_payment" to Settings.ACTION_NFC_PAYMENT_SETTINGS,
        "wireless" to Settings.ACTION_WIRELESS_SETTINGS,
        "airplane_mode" to Settings.ACTION_AIRPLANE_MODE_SETTINGS,
        "mobile_network" to Settings.ACTION_DATA_ROAMING_SETTINGS,
        "network_operator" to Settings.ACTION_NETWORK_OPERATOR_SETTINGS,
        "apn" to Settings.ACTION_APN_SETTINGS,
        "data_usage" to Settings.ACTION_DATA_USAGE_SETTINGS,
        "vpn" to Settings.ACTION_VPN_SETTINGS,
        "date_time" to Settings.ACTION_DATE_SETTINGS,
        "language" to Settings.ACTION_LOCALE_SETTINGS,
        "keyboard" to Settings.ACTION_INPUT_METHOD_SETTINGS,
        "physical_keyboard" to Settings.ACTION_HARD_KEYBOARD_SETTINGS,
        "voice_input" to Settings.ACTION_VOICE_INPUT_SETTINGS,
        "user_dictionary" to Settings.ACTION_USER_DICTIONARY_SETTINGS,
        "storage" to Settings.ACTION_INTERNAL_STORAGE_SETTINGS,
        "memory_card" to Settings.ACTION_MEMORY_CARD_SETTINGS,
        "device_info" to Settings.ACTION_DEVICE_INFO_SETTINGS,
        "security" to Settings.ACTION_SECURITY_SETTINGS,
        "privacy" to Settings.ACTION_PRIVACY_SETTINGS,
        "printing" to Settings.ACTION_PRINT_SETTINGS,
        "captioning" to Settings.ACTION_CAPTIONING_SETTINGS,
        "screensaver" to Settings.ACTION_DREAM_SETTINGS,
        "night_display" to Settings.ACTION_NIGHT_DISPLAY_SETTINGS,
        "home_app" to Settings.ACTION_HOME_SETTINGS,
        "accounts_sync" to Settings.ACTION_SYNC_SETTINGS,
        "search" to Settings.ACTION_SEARCH_SETTINGS,
        "developer_options" to Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS,
        "battery_optimization" to Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS,
        "all_apps" to Settings.ACTION_MANAGE_ALL_APPLICATIONS_SETTINGS,
    )

    @JvmOverloads
    fun intent(destination: String, packageName: String?, sdkInt: Int = Build.VERSION.SDK_INT): Intent? {
        if (destination == "notifications") {
            return if (sdkInt >= 33) Intent(Settings.ACTION_ALL_APPS_NOTIFICATION_SETTINGS) else null
        }
        if (destination == "app_details") {
            if (packageName.isNullOrBlank()) return null
            return Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).setData(Uri.fromParts("package", packageName, null))
        }
        return actions[destination]?.let(::Intent)
    }
}
