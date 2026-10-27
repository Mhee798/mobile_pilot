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
        queue = new DeviceActionQueue(service, handler, overlay, gestures);
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

    @Test public void dragContinuationIsRevokedAfterTimeoutOrDisposal() {
        foreground(TARGET);
        @SuppressWarnings("unchecked") kotlin.jvm.functions.Function0<Boolean>[] allowed = new kotlin.jvm.functions.Function0[1];
        doAnswer(inv -> { allowed[0]=inv.getArgument(10); return null; }).when(gestures)
            .dragNormalizedPoints(anyDouble(),anyDouble(),anyDouble(),anyDouble(),anyInt(),anyInt(),anyInt(),anyLong(),anyLong(),anyString(),any(),any());
        queue.queueDrag(.3,.3,.7,.7,1280,2800,0,TARGET,750,800);advance(1600);
        assertTrue(allowed[0].invoke());advance(3550);assertNull(allowed[0].invoke());
        queue.queueDrag(.3,.3,.7,.7,1280,2800,0,TARGET,750,800);advance(1600);
        assertTrue(allowed[0].invoke());queue.dispose();assertNull(allowed[0].invoke());
    }
    @Test public void stopDuringDragHoldRevokesContinuation() {
        foreground(TARGET);
        @SuppressWarnings("unchecked") kotlin.jvm.functions.Function0<Boolean>[] allowed = new kotlin.jvm.functions.Function0[1];
        doAnswer(inv -> { allowed[0]=inv.getArgument(10); return null; }).when(gestures)
            .dragNormalizedPoints(anyDouble(),anyDouble(),anyDouble(),anyDouble(),anyInt(),anyInt(),anyInt(),anyLong(),anyLong(),anyString(),any(),any());
        queue.queueDrag(.3,.3,.7,.7,1280,2800,0,TARGET,750,800);advance(1600);
        assertNotNull(allowed[0]);assertTrue(allowed[0].invoke());
        queue.cancelPendingActions();assertFalse(allowed[0].invoke());
    }
    @Test public void doubleTapWaitsForTargetAndCancelPreventsDispatch() {
        foreground(PILOT);queue.queueDoubleTap(.5,.5,1280,2800,0,TARGET);advance(2000);
        verify(gestures,never()).doubleTapNormalizedPoint(anyDouble(),anyDouble(),anyInt(),anyInt(),anyInt(),any());
        queue.cancelPendingActions();foreground(TARGET);advance(2000);
        verify(gestures,never()).doubleTapNormalizedPoint(anyDouble(),anyDouble(),anyInt(),anyInt(),anyInt(),any());
        queue.queueDoubleTap(.5,.5,1280,2800,0,TARGET);advance(1600);
        verify(gestures).doubleTapNormalizedPoint(eq(.5),eq(.5),eq(1280),eq(2800),eq(0),any());
    }
    @Test
    public void pinchWaitsForTargetAndNeverUsesSingleFingerTap() {
        foreground(PILOT);
        assertTrue(queue.queuePinch(.5,.5,1280,2800,0,TARGET,100,.25,2,"horizontal").getSuccess());
        advance(2000);
        verify(gestures,never()).pinchNormalizedPoint(anyDouble(),anyDouble(),anyInt(),anyInt(),anyInt(),anyLong(),anyDouble(),anyDouble(),anyString(),any());
        foreground(TARGET);advance(1600);
        verify(gestures).pinchNormalizedPoint(eq(.5),eq(.5),eq(1280),eq(2800),eq(0),eq(100L),eq(.25),eq(2.0),eq("horizontal"),any());
        verify(gestures,never()).tapNormalizedPoint(anyDouble(),anyDouble(),anyInt(),anyInt(),anyInt(),any());
    }
    @Test
    public void queuedPinchCanBeCancelledBeforeDispatch() {
        queue.queuePinch(.5,.5,1280,2800,0,TARGET,500,.25,2,"horizontal");
        queue.cancelPendingActions();foreground(TARGET);advance(60000);
        verify(gestures,never()).pinchNormalizedPoint(anyDouble(),anyDouble(),anyInt(),anyInt(),anyInt(),anyLong(),anyDouble(),anyDouble(),anyString(),any());
        assertCode("TAP_CANCELLED");
    }
    @Test
    public void invalidPinchNeverEntersQueue() {
        assertEquals("INVALID_PINCH",queue.queuePinch(.02,.5,1280,2800,0,TARGET,500,.25,2,"horizontal").getCode());
        assertEquals("INVALID_DURATION",queue.queuePinch(.5,.5,1280,2800,0,TARGET,1,.25,2,"horizontal").getCode());
        assertFalse(queue.getHasPendingActions());
    }

    @Test
    public void customSwipeWaitsForTargetAndRetainsBothEndpoints() {
        foreground(PILOT);
        assertTrue(queue.queueSwipe(.2,.8,.8,.2,1280,2800,0,TARGET,100).getSuccess());
        advance(2000);
        verify(gestures,never()).swipeNormalizedPoints(anyDouble(),anyDouble(),anyDouble(),anyDouble(),anyInt(),anyInt(),anyInt(),anyLong(),any());
        foreground(TARGET);
        advance(1600);
        verify(gestures).swipeNormalizedPoints(eq(.2),eq(.8),eq(.8),eq(.2),eq(1280),eq(2800),eq(0),eq(100L),any());
        verify(gestures,never()).tapNormalizedPoint(anyDouble(),anyDouble(),anyInt(),anyInt(),anyInt(),any());
    }

    @Test
    public void cancelledCustomSwipeCannotDispatch() {
        queue.queueSwipe(.2,.8,.8,.2,1280,2800,0,TARGET,400);
        queue.cancelPendingActions();
        foreground(TARGET);
        advance(60000);
        verify(gestures,never()).swipeNormalizedPoints(anyDouble(),anyDouble(),anyDouble(),anyDouble(),anyInt(),anyInt(),anyInt(),anyLong(),any());
        assertCode("TAP_CANCELLED");
    }

    @Test
    public void identicalSwipeEndpointsCannotEnterQueue() {
        assertEquals("INVALID_COORDINATE",queue.queueSwipe(.2,.8,.2,.8,1280,2800,0,TARGET,400).getCode());
        assertEquals("INVALID_DURATION",queue.queueSwipe(.2,.8,.8,.2,1280,2800,0,TARGET,3001).getCode());
        assertFalse(queue.getHasPendingActions());
    }

    @Test
    public void missingCallbackExpiresAndOldCallbackCannotReleaseANewPress() {
        foreground(TARGET);
        queue.queueLongPress(.3,.4,1280,2800,0,TARGET,1000);
        advance(4500);
        assertCode("GESTURE_TIMEOUT");
        assertFalse(queue.getHasPendingActions());
        queue.queueLongPress(.3,.4,1280,2800,0,TARGET,1000);
        advance(1500);
        @SuppressWarnings("unchecked") org.mockito.ArgumentCaptor<Function1<MobilePilotAccessibilityService.TapResult, Unit>> callbacks = org.mockito.ArgumentCaptor.forClass(Function1.class);
        verify(gestures,times(2)).longPressNormalizedPoint(anyDouble(), anyDouble(), anyInt(), anyInt(), anyInt(), anyLong(), callbacks.capture());
        callbacks.getAllValues().get(0).invoke(new MobilePilotAccessibilityService.TapResult(true,"GESTURE_COMPLETED","old"));
        assertTrue(queue.getHasPendingActions());
        assertCode("TAP_SENDING");
        callbacks.getAllValues().get(1).invoke(new MobilePilotAccessibilityService.TapResult(true,"GESTURE_COMPLETED","new"));
        assertFalse(queue.getHasPendingActions());
    }

    @Test
    public void longPressWaitsForTargetAndPreservesDuration() {
        foreground(PILOT);
        assertTrue(queue.queueLongPress(.3, .4, 1280, 2800, 0, TARGET, 1500).getSuccess());
        advance(2000);
        verify(gestures, never()).longPressNormalizedPoint(anyDouble(), anyDouble(), anyInt(), anyInt(), anyInt(), anyLong(), any());
        foreground(TARGET);
        advance(1600);
        verify(gestures).longPressNormalizedPoint(eq(.3), eq(.4), eq(1280), eq(2800), eq(0), eq(1500L), any());
    }

    @Test
    public void cancelBeforeLongPressCannotDispatchLater() {
        queue.queueLongPress(.3, .4, 1280, 2800, 0, TARGET, 1000);
        queue.cancelPendingActions();
        foreground(TARGET);
        advance(60000);
        verify(gestures, never()).longPressNormalizedPoint(anyDouble(), anyDouble(), anyInt(), anyInt(), anyInt(), anyLong(), any());
        assertCode("TAP_CANCELLED");
    }

    @Test
    public void activeLongPressBlocksNewCommandsUntilItsCallback() {
        foreground(TARGET);
        queue.queueLongPress(.3, .4, 1280, 2800, 0, TARGET, 2000);
        advance(1500);
        assertEquals("ACTION_IN_PROGRESS", queue.queuePointTap(.5,.5,1280,2800,0,TARGET).getCode());
        assertEquals("ACTION_IN_PROGRESS", queue.queueUtilityAction("back",TARGET,1280,2800,0,null).getCode());
        @SuppressWarnings("unchecked") org.mockito.ArgumentCaptor<Function1<MobilePilotAccessibilityService.TapResult, Unit>> callback = org.mockito.ArgumentCaptor.forClass(Function1.class);
        verify(gestures).longPressNormalizedPoint(anyDouble(), anyDouble(), anyInt(), anyInt(), anyInt(), anyLong(), callback.capture());
        callback.getValue().invoke(new MobilePilotAccessibilityService.TapResult(true,"GESTURE_COMPLETED","done"));
        assertFalse(queue.getHasPendingActions());
        assertTrue(queue.queuePointTap(.5,.5,1280,2800,0,TARGET).getSuccess());
    }

    @Test
    public void invalidLongPressDoesNotEnterTheQueue() {
        assertEquals("INVALID_DURATION", queue.queueLongPress(.5,.5,1280,2800,0,TARGET,10).getCode());
        assertEquals("INVALID_TARGET", queue.queueLongPress(.5,.5,0,2800,0,TARGET,1000).getCode());
        assertFalse(queue.getHasPendingActions());
    }

    @Test
    public void earlyTargetAndOutgoingPilotEventsCannotCancelTapWhileRootStillPilot() {
        foreground(PILOT);
        enqueuePoint();
        queue.onAccessibilityEvent(window(TARGET));
        queue.onAccessibilityEvent(window(PILOT));
        advance(2_000);
        assertCode("TAP_WAITING_FOR_TARGET");
        assertTrue(queue.getHasPendingActions());
        foreground(TARGET);
        // No new window event: foreground polling must still find the app.
        advance(1_600);
        assertCode("GESTURE_COMPLETED");
        verify(gestures, times(1)).tapNormalizedPoint(anyDouble(), anyDouble(), anyInt(), anyInt(), anyInt(), any());
    }

    @Test
    public void interruptedPointForegroundMustSettleAgain() {
        foreground(TARGET);
        enqueuePoint();
        advance(1_000);
        foreground(PILOT);
        advance(200);
        foreground(TARGET);
        advance(1_500);
        verifyNoInteractions(gestures);
        advance(100);
        assertCode("GESTURE_COMPLETED");
    }

    @Test
    public void earlyTargetAndPilotEventsCannotCancelUtilityBeforeRootBecomesTarget() {
        enqueueAction("back");
        foreground(PILOT);
        queue.onAccessibilityEvent(window(TARGET));
        queue.onAccessibilityEvent(window(PILOT));
        advance(2_000);
        assertTrue(queue.getHasPendingActions());
        verify(service, never()).performGlobalAction(anyInt());
        foreground(TARGET);
        when(service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK)).thenReturn(true);
        advance(1_600);
        assertCode("BACK_DISPATCHED");
    }

    @Test
    public void openingTargetAfterQueueDoesNotCancelOnPilotOutgoingEvent() {
        foreground(PILOT);
        enqueuePoint();
        queue.onAccessibilityEvent(window(PILOT));
        advance(1_500);
        assertTrue(queue.getHasPendingActions());
        foreground(TARGET);
        queue.onAccessibilityEvent(window(TARGET));
        advance(1_500);
        assertCode("GESTURE_COMPLETED");
    }

    @Test
    public void textNeverSubstitutesTheMostRecentAppForTheDeclaredTarget() {
        foreground(TARGET);
        queue.onAccessibilityEvent(window("other.app"));
        assertTrue(queue.queueUtilityAction("type_text", TARGET, 1280, 2800, 0, "test").getSuccess());
        assertEquals(TARGET, queue.getQueuedUtilityTargetPackage());
    }

    @Test
    public void alreadyForegroundTargetDispatchesBackWithoutANewWindowEvent() {
        foreground(TARGET);
        when(service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK)).thenReturn(true);
        assertTrue(queue.queueUtilityAction("back", TARGET, 1280, 2800, 0, null).getSuccess());
        advance(1_500);
        verify(service).performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK);
        assertCode("BACK_DISPATCHED");
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
        foreground(PILOT);
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
        assertCode("TAP_WAITING_FOR_TARGET");
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
    public void repeatedTargetEventsCannotPostponeStableForegroundTap() {
        enqueuePoint();
        foreground(TARGET);
        queue.onAccessibilityEvent(window(TARGET));
        advance(1_000);
        queue.onAccessibilityEvent(window(TARGET));
        advance(499);
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
    public void returningToPilotKeepsTapWaitingWithoutDispatchUntilExpiry() {
        enqueuePoint();
        foreground(TARGET);
        queue.onAccessibilityEvent(window(TARGET));
        advance(500);
        foreground(PILOT);
        queue.onAccessibilityEvent(window(PILOT));
        advance(60_000);
        assertCode("TAP_EXPIRED");
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
        foreground("other.app");
        queue.onAccessibilityEvent(window("other.app"));
        advance(2_000);
        verify(service, never()).performGlobalAction(anyInt());
        assertTrue(queue.getHasPendingActions());
        foreground(TARGET);
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
