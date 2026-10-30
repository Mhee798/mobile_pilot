package com.example.mobile_pilot;

import static org.junit.Assert.*;
import android.content.Intent;
import android.provider.Settings;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 34, manifest = Config.NONE)
public class SystemSettingsShortcutsTest {
    @Test public void acceptsOnlyKnownDestinations() {
        Intent wifi = SystemSettingsShortcuts.INSTANCE.intent("wifi", null);
        assertEquals(Settings.ACTION_WIFI_SETTINGS, wifi.getAction());
        assertNull(SystemSettingsShortcuts.INSTANCE.intent("unrecognized", null));
        assertNull(SystemSettingsShortcuts.INSTANCE.intent("app_details", null));
    }

    @Test public void appDetailsTargetsTheSelectedPackage() {
        Intent intent = SystemSettingsShortcuts.INSTANCE.intent("app_details", "com.example.app");
        assertEquals(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, intent.getAction());
        assertEquals("package:com.example.app", intent.getData().toString());
    }

    @Test public void commonDestinationsHaveTheExpectedIntents() {
        assertEquals(Settings.ACTION_CAST_SETTINGS, SystemSettingsShortcuts.INSTANCE.intent("cast", null).getAction());
        assertEquals(Settings.ACTION_NFC_SETTINGS, SystemSettingsShortcuts.INSTANCE.intent("nfc", null).getAction());
        assertEquals(Settings.ACTION_LOCALE_SETTINGS, SystemSettingsShortcuts.INSTANCE.intent("language", null).getAction());
        assertEquals(Settings.ACTION_VPN_SETTINGS, SystemSettingsShortcuts.INSTANCE.intent("vpn", null).getAction());
        assertEquals(Settings.ACTION_ALL_APPS_NOTIFICATION_SETTINGS, SystemSettingsShortcuts.INSTANCE.intent("notifications", null).getAction());
    }

    @Test
    public void notificationsRequiresAndroid13() {
        assertNull(SystemSettingsShortcuts.INSTANCE.intent("notifications", null, 30));
        assertNotNull(SystemSettingsShortcuts.INSTANCE.intent("notifications", null, 33));
        assertNotNull(SystemSettingsShortcuts.INSTANCE.intent("cast", null, 30));
    }
}
