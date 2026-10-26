package com.example.mobile_pilot;

import android.accessibilityservice.AccessibilityService;
import java.util.ArrayList;
import java.util.List;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;

import static org.junit.Assert.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

public class ScreenCaptureControllerTest extends NativeControllerTest {
    private ScreenCaptureController capture;
    private final List<AccessibilityService.TakeScreenshotCallback> callbacks = new ArrayList<>();

    @Before
    public void createCapture() {
        ScreenCaptureController.Companion.takeLastExternalScreenCapture();
        capture = new ScreenCaptureController(service, handler, pkg -> true);
        foreground(TARGET);
        when(service.getMainExecutor()).thenReturn(Runnable::run);
        doAnswer(invocation -> {
            callbacks.add(invocation.getArgument(2));
            return null;
        }).when(service).takeScreenshot(anyInt(), any(), any());
    }

    @After
    public void clearCapture() {
        capture.cancelExternalScreenCapture();
    }

    @Test
    public void expiredCaptureIgnoresLaterAppSwitch() {
        capture.armExternalScreenCapture();
        advance(29_999);
        assertTrue(capture.isArmed());
        advance(1);
        assertFalse(capture.isArmed());
        capture.onAccessibilityEvent(window(TARGET));
        advance(1_000);
        verify(service, never()).takeScreenshot(anyInt(), any(), any());
        assertNull(capture.takeExternalScreenCapture());
    }

    @Test
    public void cancelRemovesScheduledScreenshot() {
        capture.armExternalScreenCapture();
        capture.onAccessibilityEvent(window(TARGET));
        advance(699);
        capture.cancelExternalScreenCapture();
        advance(30_000);
        assertFalse(capture.isArmed());
        verify(service, never()).takeScreenshot(anyInt(), any(), any());
    }

    @Test
    public void cancelDiscardsInFlightScreenshotCallback() {
        capture.armExternalScreenCapture();
        capture.onAccessibilityEvent(window(TARGET));
        advance(700);
        assertEquals(1, callbacks.size());
        capture.cancelExternalScreenCapture();
        callbacks.get(0).onFailure(AccessibilityService.ERROR_TAKE_SCREENSHOT_INTERNAL_ERROR);
        assertNull(capture.takeExternalScreenCapture());
        assertFalse(capture.isArmed());
    }

    @Test
    public void expiredInFlightScreenshotCannotPublishLater() {
        capture.armExternalScreenCapture();
        capture.onAccessibilityEvent(window(TARGET));
        advance(700);
        advance(29_300);
        callbacks.get(0).onFailure(AccessibilityService.ERROR_TAKE_SCREENSHOT_INTERNAL_ERROR);
        assertNull(capture.takeExternalScreenCapture());
        assertFalse(capture.isArmed());
    }

    @Test
    public void rearmIgnoresOldCallbackAndKeepsNewRequestAlive() {
        capture.armExternalScreenCapture();
        capture.onAccessibilityEvent(window(TARGET));
        advance(700);
        capture.armExternalScreenCapture();
        callbacks.get(0).onFailure(AccessibilityService.ERROR_TAKE_SCREENSHOT_INTERNAL_ERROR);
        assertTrue(capture.isArmed());
        assertNull(capture.takeExternalScreenCapture());
        capture.onAccessibilityEvent(window(TARGET));
        advance(700);
        callbacks.get(1).onFailure(AccessibilityService.ERROR_TAKE_SCREENSHOT_INTERNAL_ERROR);
        assertFalse(capture.isArmed());
        MobilePilotAccessibilityService.ExternalScreenCapture result = capture.takeExternalScreenCapture();
        assertNotNull(result);
        assertEquals(TARGET, result.getPackageName());
        assertFalse(result.getCapture().getSuccess());
        assertTrue(result.getCapture().getError().contains("code 1"));
        assertNull(capture.takeExternalScreenCapture());
    }

    @Test
    public void repeatedWindowEventsWaitForSevenHundredMillisecondsOfQuiet() {
        capture.armExternalScreenCapture();
        capture.onAccessibilityEvent(window(TARGET));
        advance(500);
        capture.onAccessibilityEvent(window(TARGET));
        advance(699);
        assertTrue(callbacks.isEmpty());
        advance(1);
        assertEquals(1, callbacks.size());
    }

    @Test
    public void ownWindowDoesNotTriggerCapture() {
        capture.armExternalScreenCapture();
        capture.onAccessibilityEvent(window(PILOT));
        advance(1_000);
        assertTrue(capture.isArmed());
        assertTrue(callbacks.isEmpty());
    }

    @Test
    public void returningToPilotBeforeDelayCannotCaptureItsScreen() {
        capture.armExternalScreenCapture();
        capture.onAccessibilityEvent(window(TARGET));
        advance(500);
        foreground(PILOT);
        capture.onAccessibilityEvent(window(PILOT));
        advance(200);
        assertTrue(callbacks.isEmpty());
        assertNull(capture.takeExternalScreenCapture());
        assertTrue(capture.isArmed());
        foreground(TARGET);
        capture.onAccessibilityEvent(window(TARGET));
        advance(700);
        assertEquals(1, callbacks.size());
    }

    @Test
    public void returningToPilotWhileCaptureIsInFlightDiscardsTheResult() {
        capture.armExternalScreenCapture();
        capture.onAccessibilityEvent(window(TARGET));
        advance(700);
        foreground(PILOT);
        callbacks.get(0).onFailure(AccessibilityService.ERROR_TAKE_SCREENSHOT_INTERNAL_ERROR);
        assertNull(capture.takeExternalScreenCapture());
        assertTrue(capture.isArmed());
    }

    @Test
    public void switchingToAnotherExternalAppDiscardsMismatchedCapture() {
        capture.armExternalScreenCapture();
        capture.onAccessibilityEvent(window(TARGET));
        advance(700);
        foreground("other.app");
        callbacks.get(0).onFailure(AccessibilityService.ERROR_TAKE_SCREENSHOT_INTERNAL_ERROR);
        assertNull(capture.takeExternalScreenCapture());
        assertTrue(capture.isArmed());
    }

    @Test
    public void completedResultSurvivesOriginalExpiryAndIsConsumedOnce() {
        capture.armExternalScreenCapture();
        capture.onAccessibilityEvent(window(TARGET));
        advance(700);
        callbacks.get(0).onFailure(AccessibilityService.ERROR_TAKE_SCREENSHOT_INTERNAL_ERROR);
        advance(30_000);
        assertNotNull(MobilePilotAccessibilityService.Companion.takeLastExternalScreenCapture());
        assertNull(MobilePilotAccessibilityService.Companion.takeLastExternalScreenCapture());
    }
}
