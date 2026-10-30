package com.example.mobile_pilot;

import android.Manifest;
import android.app.Application;
import android.app.Notification;
import android.app.NotificationManager;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.Shadows;
import org.robolectric.annotation.Config;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
// Host JDK 17 supports Robolectric's API 34 runtime; promotion is checked on device.
@Config(sdk = 34)
public class AiTaskNotificationTest {
    private Application app;
    private NotificationManager manager;
    private AiTaskNotification publisher;
    @Before public void setUp() {
        app = RuntimeEnvironment.getApplication();
        Shadows.shadowOf(app).grantPermissions(Manifest.permission.POST_NOTIFICATIONS);
        manager = app.getSystemService(NotificationManager.class);
        publisher = new AiTaskNotification(app);
    }
    @Test public void updatesOneNotificationAndPreservesStartTimeUntilStopped() {
        publisher.publish("อ่านหน้าจอ", true);
        Notification first = manager.getActiveNotifications()[0].getNotification();
        assertFalse(first.extras.getBoolean("android.requestPromotedOngoing"));
        assertNotEquals(0, first.flags & Notification.FLAG_ONGOING_EVENT);
        assertNotNull(first.actions[0].actionIntent);
        publisher.publish("กำลังแตะ", true);
        assertEquals(1, manager.getActiveNotifications().length);
        Notification updated = manager.getActiveNotifications()[0].getNotification();
        assertEquals(first.when, updated.when);
        assertEquals("กำลังแตะ", updated.extras.getCharSequence(Notification.EXTRA_TEXT));
        publisher.publish("หยุด", false);
        assertEquals(0, manager.getActiveNotifications().length);
    }
    @Test public void permissionDenialNeverPostsAndDismissalDoesNotRepost() {
        Shadows.shadowOf(app).denyPermissions(Manifest.permission.POST_NOTIFICATIONS);
        publisher.publish("คิด", true);
        assertEquals(0, manager.getActiveNotifications().length);
        Shadows.shadowOf(app).grantPermissions(Manifest.permission.POST_NOTIFICATIONS);
        publisher.publish("อ่าน", true);
        manager.cancel(AiTaskNotification.ID);
        publisher.dismiss();
        publisher.publish("แตะ", true);
        assertEquals(0, manager.getActiveNotifications().length);
        publisher.publish("จบ", false);
        publisher.publish("งานใหม่", true);
        assertEquals(1, manager.getActiveNotifications().length);
    }
}
