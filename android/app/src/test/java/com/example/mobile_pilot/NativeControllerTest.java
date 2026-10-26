package com.example.mobile_pilot;

import android.accessibilityservice.AccessibilityService;
import android.os.Handler;
import android.os.Looper;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;
import java.time.Duration;
import org.junit.Before;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.Shadows;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.LooperMode;

import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 34, manifest = Config.NONE)
@LooperMode(LooperMode.Mode.PAUSED)
public abstract class NativeControllerTest {
    protected static final String PILOT = "com.example.mobile_pilot";
    protected static final String TARGET = "com.android.settings";
    protected AccessibilityService service;
    protected Handler handler;

    @Before
    public void prepareAndroidRuntime() {
        service = mock(AccessibilityService.class);
        when(service.getPackageName()).thenReturn(PILOT);
        handler = new Handler(Looper.getMainLooper());
    }

    protected void advance(long milliseconds) {
        Shadows.shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(milliseconds));
    }

    protected AccessibilityEvent window(String packageName) {
        AccessibilityEvent event = AccessibilityEvent.obtain(AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED);
        event.setPackageName(packageName);
        return event;
    }

    protected AccessibilityNodeInfo foreground(String packageName) {
        AccessibilityNodeInfo root = mock(AccessibilityNodeInfo.class);
        when(root.getPackageName()).thenReturn(packageName);
        when(service.getRootInActiveWindow()).thenReturn(root);
        return root;
    }
}
