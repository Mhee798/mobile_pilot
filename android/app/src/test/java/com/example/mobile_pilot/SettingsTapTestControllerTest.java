package com.example.mobile_pilot;

import android.content.Context;
import android.content.SharedPreferences;
import java.util.Collections;
import org.junit.Before;
import org.junit.Test;
import org.robolectric.RuntimeEnvironment;

import static org.junit.Assert.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

public class SettingsTapTestControllerTest extends NativeControllerTest {
    private SettingsTapTestController settings;
    private UiTreeController tree;
    private SharedPreferences results;

    @Before
    public void createSettingsTest() {
        results = RuntimeEnvironment.getApplication().getSharedPreferences(
            MobilePilotAccessibilityService.SETTINGS_TEST_PREFS, Context.MODE_PRIVATE);
        results.edit().clear().commit();
        when(service.getSharedPreferences(MobilePilotAccessibilityService.SETTINGS_TEST_PREFS, Context.MODE_PRIVATE))
            .thenReturn(results);
        tree = mock(UiTreeController.class);
        settings = new SettingsTapTestController(service, handler, tree);
        foreground(TARGET);
        when(tree.readUiTree()).thenReturn(Collections.singletonList(Collections.singletonMap("text", "Battery")));
    }

    private void begin() {
        assertTrue(settings.beginSettingsTapTest("Battery", TARGET).getSuccess());
    }

    private void assertStatus(String status) {
        assertEquals(status, results.getString("status", ""));
        assertEquals("Battery", results.getString("target", ""));
    }

    @Test
    public void newReferenceIdsAloneDoNotVerifyAUiChange() {
        begin();
        when(tree.tapElementByText("Battery"))
            .thenReturn(new MobilePilotAccessibilityService.TapResult(true, "ACTION_DISPATCHED", "sent"));
        when(tree.readUiTree()).thenReturn(Collections.singletonList(java.util.Map.of("text", "Battery", "screenId", "old", "nodeId", "node-1")));
        settings.onAccessibilityEvent(window(TARGET));
        when(tree.readUiTree()).thenReturn(Collections.singletonList(java.util.Map.of("text", "Battery", "screenId", "new", "nodeId", "node-2")));
        settings.onAccessibilityEvent(window(TARGET));
        assertStatus("running");
        advance(5_000);
        assertStatus("dispatched_unverified");
    }

    @Test
    public void missingTargetExpiresAtTwentySeconds() {
        begin();
        advance(19_999);
        assertTrue(settings.isPending());
        assertStatus("waiting");
        advance(1);
        assertFalse(settings.isPending());
        assertStatus("target_not_found");
    }

    @Test
    public void cancelledTestDoesNotTapWhenTargetAppearsLater() {
        begin();
        settings.cancelPending();
        settings.onAccessibilityEvent(window(TARGET));
        advance(60_000);
        assertFalse(settings.isPending());
        assertStatus("cancelled");
        verifyNoInteractions(tree);
    }

    @Test
    public void outgoingPilotRootIsNotTreatedAsSettings() {
        begin();
        foreground(PILOT);
        settings.onAccessibilityEvent(window(TARGET));
        assertStatus("waiting");
        verifyNoInteractions(tree);
    }

    @Test
    public void changedTreeVerifiesDispatchedTap() {
        begin();
        when(tree.tapElementByText("Battery"))
            .thenReturn(new MobilePilotAccessibilityService.TapResult(true, "ACTION_DISPATCHED", "sent"));
        settings.onAccessibilityEvent(window(TARGET));
        assertStatus("running");
        when(tree.readUiTree()).thenReturn(Collections.singletonList(Collections.singletonMap("text", "Battery detail")));
        settings.onAccessibilityEvent(window(TARGET));
        assertStatus("verified");
        assertFalse(settings.isPending());
        advance(20_000);
        assertStatus("verified");
        verify(tree, times(1)).tapElementByText("Battery");
    }

    @Test
    public void acceptedTapWithoutTreeChangeIsReportedUnverifiedAfterFiveSeconds() {
        begin();
        when(tree.tapElementByText("Battery"))
            .thenReturn(new MobilePilotAccessibilityService.TapResult(true, "ACTION_DISPATCHED", "sent"));
        settings.onAccessibilityEvent(window(TARGET));
        advance(4_999);
        assertStatus("running");
        advance(1);
        assertStatus("dispatched_unverified");
        assertFalse(settings.isPending());
    }

    @Test
    public void retryingMissingTargetDoesNotExtendOriginalDeadline() {
        begin();
        when(tree.tapElementByText("Battery"))
            .thenReturn(new MobilePilotAccessibilityService.TapResult(false, "TARGET_NOT_FOUND", "missing"));
        advance(10_000);
        settings.onAccessibilityEvent(window(TARGET));
        advance(9_000);
        settings.onAccessibilityEvent(window(TARGET));
        advance(1_000);
        assertStatus("target_not_found");
        assertFalse(settings.isPending());
    }

    @Test
    public void disposeRemovesTimerWithoutInventingAResult() {
        begin();
        settings.dispose();
        advance(60_000);
        assertStatus("waiting");
        verifyNoInteractions(tree);
    }
}
