package com.example.mobile_pilot;

import android.accessibilityservice.AccessibilityService;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;
import kotlin.Unit;
import kotlin.jvm.functions.Function1;
import org.junit.Before;
import org.junit.Test;

import static org.junit.Assert.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

public class DeviceActionQueueTest extends NativeControllerTest {
    private DeviceActionQueue queue;
    private DeviceGestureController gestures;
    private FloatingControlsController overlay;

    @Before
    public void createQueue() {
        gestures = mock(DeviceGestureController.class);
        overlay = mock(FloatingControlsController.class);
        queue = new DeviceActionQueue(service, handler, overlay, gestures, pkg -> true);
        doAnswer(invocation -> {
            Function1<MobilePilotAccessibilityService.TapResult, Unit> callback = invocation.getArgument(5);
            callback.invoke(new MobilePilotAccessibilityService.TapResult(true, "GESTURE_COMPLETED", "done"));
            return null;
        }).when(gestures).tapNormalizedPoint(anyDouble(), anyDouble(), anyInt(), anyInt(), anyInt(), any());
    }

    private void enqueuePoint() {
        assertTrue(queue.queuePointTap(0.25, 0.75, 1280, 2800, 0, TARGET).getSuccess());
    }

    private void enqueueAction(String action) {
        foreground(TARGET);
        assertTrue(queue.queueUtilityAction(action, TARGET, 1280, 2800, 0, null).getSuccess());
    }

    private void assertCode(String code) {
        assertNotNull(queue.getPointTapResult());
        assertEquals(code, queue.getPointTapResult().getCode());
    }

    @Test
    public void pointExpiresAtSixtySecondsWithoutDispatch() {
        enqueuePoint();
        advance(59_999);
        assertTrue(queue.getHasPendingActions());
        advance(1);
        assertFalse(queue.getHasPendingActions());
        assertCode("TAP_EXPIRED");
        verifyNoInteractions(gestures);
    }

    @Test
    public void utilityExpiresAtSixtySecondsWithoutDispatch() {
        enqueueAction("back");
        advance(59_999);
        assertTrue(queue.getHasPendingActions());
        advance(1);
        assertFalse(queue.getHasPendingActions());
        assertCode("ACTION_EXPIRED");
        verify(service, never()).performGlobalAction(anyInt());
    }

    @Test
    public void replacementPointDoesNotInheritPreviousDeadline() {
        enqueuePoint();
        advance(30_000);
        assertTrue(queue.queuePointTap(0.8, 0.2, 1280, 2800, 0, TARGET).getSuccess());
        advance(30_000);
        assertTrue(queue.getHasPendingActions());
        assertCode("TAP_QUEUED");
        advance(30_000);
        assertCode("TAP_EXPIRED");
    }

    @Test
    public void pointAndUtilityCannotOverlap() {
        enqueuePoint();
        assertEquals("ACTION_IN_PROGRESS", queue.queueUtilityAction("back", TARGET, 1280, 2800, 0, null).getCode());
        queue.cancelPendingActions();
        enqueueAction("back");
        assertEquals("ACTION_IN_PROGRESS", queue.queuePointTap(0.5, 0.5, 1280, 2800, 0, TARGET).getCode());
        assertEquals("ACTION_IN_PROGRESS", queue.queueUtilityAction("back", TARGET, 1280, 2800, 0, null).getCode());
    }

    @Test
    public void cancelledPointCannotDispatchAfterTargetAppears() {
        enqueuePoint();
        foreground(TARGET);
        queue.onAccessibilityEvent(window(TARGET));
        advance(500);
        queue.cancelPendingActions();
        queue.onAccessibilityEvent(window(TARGET));
        advance(60_000);
        assertFalse(queue.getHasPendingActions());
        assertCode("TAP_CANCELLED");
        verifyNoInteractions(gestures);
    }

    @Test
    public void cancelledUtilityCannotDispatchOrExpireLater() {
        enqueueAction("back");
        queue.onAccessibilityEvent(window(TARGET));
        advance(500);
        queue.cancelPendingActions();
        queue.onAccessibilityEvent(window(TARGET));
        advance(60_000);
        assertFalse(queue.getHasPendingActions());
        assertCode("ACTION_CANCELLED");
        verify(service, never()).performGlobalAction(anyInt());
    }

    @Test
    public void pointWaitsForActualForegroundRootBeforeDispatch() {
        enqueuePoint();
        foreground("other.app");
        queue.onAccessibilityEvent(window(TARGET));
        advance(1_500);
        assertCode("TAP_WAITING_FOR_TARGET");
        verifyNoInteractions(gestures);
        foreground(TARGET);
        queue.onAccessibilityEvent(window(TARGET));
        advance(1_500);
        assertCode("GESTURE_COMPLETED");
        assertFalse(queue.getHasPendingActions());
        verify(gestures).tapNormalizedPoint(eq(0.25), eq(0.75), eq(1280), eq(2800), eq(0), any());
    }

    @Test
    public void anotherTargetWindowEventRestartsPointSettling() {
        enqueuePoint();
        foreground(TARGET);
        queue.onAccessibilityEvent(window(TARGET));
        advance(1_000);
        queue.onAccessibilityEvent(window(TARGET));
        advance(1_499);
        verifyNoInteractions(gestures);
        advance(1);
        assertCode("GESTURE_COMPLETED");
        verify(gestures, times(1)).tapNormalizedPoint(anyDouble(), anyDouble(), anyInt(), anyInt(), anyInt(), any());
    }

    @Test
    public void pilotWindowEventDoesNotCancelPointWhileTargetRootIsForeground() {
        enqueuePoint();
        foreground(TARGET);
        queue.onAccessibilityEvent(window(TARGET));
        advance(500);
        queue.onAccessibilityEvent(window(PILOT));
        advance(1_000);
        assertCode("GESTURE_COMPLETED");
        verify(gestures, times(1)).tapNormalizedPoint(anyDouble(), anyDouble(), anyInt(), anyInt(), anyInt(), any());
    }

    @Test
    public void genuinelyReturningToPilotCancelsPointBeforeDispatch() {
        enqueuePoint();
        foreground(TARGET);
        queue.onAccessibilityEvent(window(TARGET));
        advance(500);
        foreground(PILOT);
        queue.onAccessibilityEvent(window(PILOT));
        advance(60_000);
        assertCode("TAP_CANCELLED");
        assertFalse(queue.getHasPendingActions());
        verifyNoInteractions(gestures);
    }

    @Test
    public void contentEventsDoNotKeepPostponingUtilityDispatch() {
        enqueueAction("back");
        foreground(TARGET);
        when(service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK)).thenReturn(true);
        queue.onAccessibilityEvent(window(TARGET));
        advance(1_000);
        AccessibilityEvent content = AccessibilityEvent.obtain(AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED);
        content.setPackageName(TARGET);
        queue.onAccessibilityEvent(content);
        advance(500);
        assertCode("BACK_DISPATCHED");
        verify(service, times(1)).performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK);
    }

    @Test
    public void delayedTargetEventCannotSendBackToAnotherForegroundApp() {
        enqueueAction("back");
        when(service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK)).thenReturn(true);
        foreground("other.app");
        queue.onAccessibilityEvent(window(TARGET));
        advance(1_500);
        assertCode("ACTION_WAITING_FOR_TARGET");
        assertTrue(queue.getHasPendingActions());
        verify(service, never()).performGlobalAction(anyInt());
        foreground(TARGET);
        queue.onAccessibilityEvent(window(TARGET));
        advance(1_500);
        assertCode("BACK_DISPATCHED");
        verify(service, times(1)).performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK);
    }

    @Test
    public void foregroundChangeWithoutWindowEventBlocksSwipe() {
        enqueueAction("swipe_left");
        queue.onAccessibilityEvent(window(TARGET));
        advance(1_000);
        foreground("other.app");
        advance(500);
        assertCode("ACTION_WAITING_FOR_TARGET");
        verifyNoInteractions(gestures, overlay);
        advance(58_500);
        assertCode("ACTION_EXPIRED");
        verifyNoInteractions(gestures, overlay);
    }

    @Test
    public void unavailableForegroundRootDefersBackInsteadOfDispatching() {
        enqueueAction("back");
        when(service.getRootInActiveWindow()).thenReturn(null);
        queue.onAccessibilityEvent(window(TARGET));
        advance(1_500);
        assertCode("ACTION_WAITING_FOR_TARGET");
        verify(service, never()).performGlobalAction(anyInt());
    }

    @Test
    public void switchingAwayDuringSettlingDefersUtilityUntilTargetReturns() {
        enqueueAction("back");
        when(service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK)).thenReturn(true);
        queue.onAccessibilityEvent(window(TARGET));
        advance(500);
        queue.onAccessibilityEvent(window("other.app"));
        advance(2_000);
        verify(service, never()).performGlobalAction(anyInt());
        assertTrue(queue.getHasPendingActions());
        queue.onAccessibilityEvent(window(TARGET));
        advance(1_500);
        assertCode("BACK_DISPATCHED");
    }

    @Test
    public void staleCapturedDisplayRejectsUtilityGesture() {
        enqueueAction("scroll_down");
        when(gestures.isCapturedDisplayCurrent(1280, 2800, 0)).thenReturn(false);
        queue.onAccessibilityEvent(window(TARGET));
        advance(1_500);
        assertCode("STALE_SCREEN");
        verifyNoInteractions(overlay);
        verify(service, never()).dispatchGesture(any(), any(), any());
    }

    @Test
    public void passwordFieldNeverReceivesText() {
        AccessibilityNodeInfo root = foreground(TARGET);
        AccessibilityNodeInfo input = mock(AccessibilityNodeInfo.class);
        when(root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)).thenReturn(input);
        when(input.isEditable()).thenReturn(true);
        when(input.isPassword()).thenReturn(true);
        assertTrue(queue.queueUtilityAction("type_text", TARGET, 1280, 2800, 0, "safe test").getSuccess());
        queue.onAccessibilityEvent(window(TARGET));
        advance(1_500);
        assertCode("PASSWORD_FIELD_BLOCKED");
        verify(input, never()).performAction(anyInt(), any());
        verify(input).recycle();
    }

    @Test
    public void disposeRemovesScheduledDispatchAndExpiry() {
        enqueuePoint();
        foreground(TARGET);
        queue.onAccessibilityEvent(window(TARGET));
        queue.dispose();
        advance(60_000);
        assertCode("TAP_QUEUED");
        verifyNoInteractions(gestures);
    }
}
