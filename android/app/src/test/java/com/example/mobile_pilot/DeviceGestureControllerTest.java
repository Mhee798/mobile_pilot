package com.example.mobile_pilot;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.GestureDescription;
import android.hardware.display.DisplayManager;
import android.util.DisplayMetrics;
import android.view.Display;
import java.util.ArrayList;
import java.util.List;
import kotlin.Unit;
import org.junit.Before;
import org.junit.Test;
import org.mockito.ArgumentCaptor;

import static org.junit.Assert.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

public class DeviceGestureControllerTest extends NativeControllerTest {
    private DeviceGestureController gestures;
    private final List<MobilePilotAccessibilityService.TapResult> results = new ArrayList<>();

    @Before
    public void configureDisplay() {
        DisplayManager manager = mock(DisplayManager.class);
        Display display = mock(Display.class);
        when(service.getSystemService(DisplayManager.class)).thenReturn(manager);
        when(manager.getDisplay(Display.DEFAULT_DISPLAY)).thenReturn(display);
        when(display.getRotation()).thenReturn(0);
        doAnswer(invocation -> {
            DisplayMetrics metrics = invocation.getArgument(0);
            metrics.widthPixels = 1280;
            metrics.heightPixels = 2800;
            return null;
        }).when(display).getRealMetrics(any());
        gestures = new DeviceGestureController(service);
    }

    private void tap(double x, double y, int width, int height, int rotation) {
        gestures.tapNormalizedPoint(x, y, width, height, rotation, result -> {
            results.add(result);
            return Unit.INSTANCE;
        });
    }

    @Test public void dragContinuesHeldContactThenReleasesAtDestination() {
        foreground(TARGET);when(service.dispatchGesture(any(),any(),any())).thenReturn(true);
        gestures.dragNormalizedPoints(.3,.3,.7,.7,1280,2800,0,750,800,TARGET,()->true,r->{results.add(r);return Unit.INSTANCE;});
        ArgumentCaptor<GestureDescription> gesture=ArgumentCaptor.forClass(GestureDescription.class);
        ArgumentCaptor<AccessibilityService.GestureResultCallback> callback=ArgumentCaptor.forClass(AccessibilityService.GestureResultCallback.class);
        verify(service).dispatchGesture(gesture.capture(),callback.capture(),isNull());
        assertTrue(gesture.getValue().getStroke(0).willContinue());assertEquals(750,gesture.getValue().getStroke(0).getDuration());
        callback.getValue().onCompleted(gesture.getValue());
        verify(service,times(2)).dispatchGesture(gesture.capture(),callback.capture(),isNull());
        assertFalse(gesture.getValue().getStroke(0).willContinue());assertEquals(800,gesture.getValue().getStroke(0).getDuration());
        assertTrue(results.isEmpty());callback.getValue().onCompleted(gesture.getValue());
        assertEquals("GESTURE_COMPLETED",results.get(0).getCode());
    }
    @Test public void staleDragHoldCallbackDoesNotDispatchAnotherGesture() {
        foreground(TARGET);when(service.dispatchGesture(any(),any(),any())).thenReturn(true);
        gestures.dragNormalizedPoints(.3,.3,.7,.7,1280,2800,0,750,800,TARGET,()->null,r->{results.add(r);return Unit.INSTANCE;});
        ArgumentCaptor<GestureDescription> gesture=ArgumentCaptor.forClass(GestureDescription.class);
        ArgumentCaptor<AccessibilityService.GestureResultCallback> callback=ArgumentCaptor.forClass(AccessibilityService.GestureResultCallback.class);
        verify(service).dispatchGesture(gesture.capture(),callback.capture(),isNull());
        callback.getValue().onCompleted(gesture.getValue());
        verify(service,times(1)).dispatchGesture(any(),any(),isNull());assertTrue(results.isEmpty());
    }
    @Test public void cancelledHoldReleasesWithoutDragging() {
        foreground(TARGET);when(service.dispatchGesture(any(),any(),any())).thenReturn(true);
        boolean[] allowed={true};
        gestures.dragNormalizedPoints(.3,.3,.7,.7,1280,2800,0,750,800,TARGET,()->allowed[0],r->{results.add(r);return Unit.INSTANCE;});
        ArgumentCaptor<GestureDescription> gesture=ArgumentCaptor.forClass(GestureDescription.class);
        ArgumentCaptor<AccessibilityService.GestureResultCallback> callback=ArgumentCaptor.forClass(AccessibilityService.GestureResultCallback.class);
        verify(service).dispatchGesture(gesture.capture(),callback.capture(),isNull());allowed[0]=false;
        callback.getValue().onCompleted(gesture.getValue());verify(service,times(2)).dispatchGesture(gesture.capture(),callback.capture(),isNull());
        assertEquals(1,gesture.getValue().getStroke(0).getDuration());callback.getValue().onCompleted(gesture.getValue());
        assertEquals("DRAG_CANCELLED",results.get(0).getCode());
    }
    @Test public void changedForegroundReleasesHoldWithoutDragging() {
        foreground(TARGET);when(service.dispatchGesture(any(),any(),any())).thenReturn(true);
        gestures.dragNormalizedPoints(.3,.3,.7,.7,1280,2800,0,750,800,TARGET,()->true,r->{results.add(r);return Unit.INSTANCE;});
        ArgumentCaptor<GestureDescription> gesture=ArgumentCaptor.forClass(GestureDescription.class);
        ArgumentCaptor<AccessibilityService.GestureResultCallback> callback=ArgumentCaptor.forClass(AccessibilityService.GestureResultCallback.class);
        verify(service).dispatchGesture(gesture.capture(),callback.capture(),isNull());foreground(PILOT);
        callback.getValue().onCompleted(gesture.getValue());verify(service,times(2)).dispatchGesture(gesture.capture(),callback.capture(),isNull());
        assertEquals(1,gesture.getValue().getStroke(0).getDuration());callback.getValue().onCompleted(gesture.getValue());
        assertEquals("DRAG_TARGET_CHANGED",results.get(0).getCode());
    }
    @Test public void doubleTapHasTwoSeparatedContactsAndReportsCompletion() {
        when(service.dispatchGesture(any(),any(),any())).thenReturn(true);
        gestures.doubleTapNormalizedPoint(.5,.5,1280,2800,0,r->{results.add(r);return Unit.INSTANCE;});
        ArgumentCaptor<GestureDescription> gesture=ArgumentCaptor.forClass(GestureDescription.class);
        ArgumentCaptor<AccessibilityService.GestureResultCallback> callback=ArgumentCaptor.forClass(AccessibilityService.GestureResultCallback.class);
        verify(service).dispatchGesture(gesture.capture(),callback.capture(),isNull());
        assertEquals(2,gesture.getValue().getStrokeCount());
        assertEquals(60,gesture.getValue().getStroke(0).getDuration());
        assertEquals(140,gesture.getValue().getStroke(1).getStartTime());
        callback.getValue().onCompleted(gesture.getValue());
        assertEquals("GESTURE_COMPLETED",results.get(0).getCode());
    }

    @Test
    public void pinchDispatchesTwoSimultaneousStrokesWithEqualDuration() {
        when(service.dispatchGesture(any(),any(),any())).thenReturn(true);
        gestures.pinchNormalizedPoint(.5,.5,1280,2800,0,500,.25,2,"horizontal",r->{results.add(r);return Unit.INSTANCE;});
        ArgumentCaptor<GestureDescription> gesture=ArgumentCaptor.forClass(GestureDescription.class);
        ArgumentCaptor<AccessibilityService.GestureResultCallback> callback=ArgumentCaptor.forClass(AccessibilityService.GestureResultCallback.class);
        verify(service).dispatchGesture(gesture.capture(),callback.capture(),isNull());
        assertEquals(2,gesture.getValue().getStrokeCount());
        for(int i=0;i<2;i++) {
            assertEquals(0,gesture.getValue().getStroke(i).getStartTime());
            assertEquals(500,gesture.getValue().getStroke(i).getDuration());
        }
        android.graphics.RectF first=new android.graphics.RectF();
        android.graphics.RectF second=new android.graphics.RectF();
        gesture.getValue().getStroke(0).getPath().computeBounds(first,true);
        gesture.getValue().getStroke(1).getPath().computeBounds(second,true);
        assertEquals(320,first.left,.1);assertEquals(480,first.right,.1);
        assertEquals(800,second.left,.1);assertEquals(960,second.right,.1);
        assertTrue(results.isEmpty());
        callback.getValue().onCompleted(gesture.getValue());
        assertEquals("GESTURE_COMPLETED",results.get(0).getCode());
    }

    @Test
    public void pinchNeverDispatchesOutsideScreenOrOnStaleDisplay() {
        gestures.pinchNormalizedPoint(.1,.5,1280,2800,0,500,.25,2,"horizontal",r->{results.add(r);return Unit.INSTANCE;});
        gestures.pinchNormalizedPoint(.5,.5,1280,2800,1,500,.25,2,"horizontal",r->{results.add(r);return Unit.INSTANCE;});
        assertEquals("INVALID_PINCH",results.get(0).getCode());
        assertEquals("STALE_SCREEN",results.get(1).getCode());
        verify(service,never()).dispatchGesture(any(),any(),any());
    }

    @Test
    public void pinchReportsAndroidRejection() {
        when(service.dispatchGesture(any(),any(),any())).thenReturn(false);
        gestures.pinchNormalizedPoint(.5,.5,1280,2800,0,500,.25,.5,"vertical",r->{results.add(r);return Unit.INSTANCE;});
        assertEquals("GESTURE_REJECTED",results.get(0).getCode());
    }

    @Test
    public void customSwipeUsesBothEndpointsAndRequestedDuration() {
        when(service.dispatchGesture(any(),any(),any())).thenReturn(true);
        gestures.swipeNormalizedPoints(.2,.8,.8,.2,1280,2800,0,750,result -> {results.add(result); return Unit.INSTANCE;});
        ArgumentCaptor<GestureDescription> captured = ArgumentCaptor.forClass(GestureDescription.class);
        verify(service).dispatchGesture(captured.capture(),any(),isNull());
        assertEquals(750,captured.getValue().getStroke(0).getDuration());
        // Robolectric's legacy PathMeasure does not populate getPosTan; inspect path geometry directly.
        android.graphics.RectF bounds = new android.graphics.RectF();
        captured.getValue().getStroke(0).getPath().computeBounds(bounds, true);
        assertEquals(256, bounds.left, .1);
        assertEquals(560, bounds.top, .1);
        assertEquals(1024, bounds.right, .1);
        assertEquals(2240, bounds.bottom, .1);
    }

    @Test
    public void invalidSwipeNeverDispatches() {
        gestures.swipeNormalizedPoints(.5,.5,.5,.5,1280,2800,0,400,r -> {results.add(r);return Unit.INSTANCE;});
        gestures.swipeNormalizedPoints(.5,.5,Double.NaN,.2,1280,2800,0,400,r -> {results.add(r);return Unit.INSTANCE;});
        gestures.swipeNormalizedPoints(.5,.5,.8,.2,1280,2800,0,99,r -> {results.add(r);return Unit.INSTANCE;});
        assertEquals(3,results.size());
        verify(service,never()).dispatchGesture(any(),any(),any());
    }

    @Test
    public void swipeRejectsRotatedDisplay() {
        gestures.swipeNormalizedPoints(.5,.8,.5,.2,1280,2800,1,400,r -> {results.add(r);return Unit.INSTANCE;});
        assertEquals("STALE_SCREEN",results.get(0).getCode());
        verify(service,never()).dispatchGesture(any(),any(),any());
    }

    @Test
    public void longPressPreservesRequestedDurationAndWaitsForCallback() {
        when(service.dispatchGesture(any(), any(), any())).thenReturn(true);
        gestures.longPressNormalizedPoint(0.5, 0.4, 1280, 2800, 0, 1500, result -> { results.add(result); return Unit.INSTANCE; });
        ArgumentCaptor<GestureDescription> gesture = ArgumentCaptor.forClass(GestureDescription.class);
        ArgumentCaptor<AccessibilityService.GestureResultCallback> callback = ArgumentCaptor.forClass(AccessibilityService.GestureResultCallback.class);
        verify(service).dispatchGesture(gesture.capture(), callback.capture(), isNull());
        assertEquals(1500, gesture.getValue().getStroke(0).getDuration());
        assertTrue(results.isEmpty());
        callback.getValue().onCancelled(gesture.getValue());
        assertEquals("GESTURE_CANCELLED", results.get(0).getCode());
    }

    @Test
    public void invalidLongPressDurationsNeverDispatch() {
        for (long ms : new long[]{499, 3001}) {
            gestures.longPressNormalizedPoint(0.5, 0.5, 1280, 2800, 0, ms, result -> { results.add(result); return Unit.INSTANCE; });
        }
        assertEquals(2, results.size());
        assertEquals("INVALID_DURATION", results.get(0).getCode());
        verify(service, never()).dispatchGesture(any(), any(), any());
    }

    @Test
    public void longPressRejectsStaleDisplay() {
        gestures.longPressNormalizedPoint(0.5, 0.5, 2800, 1280, 0, 1000, result -> { results.add(result); return Unit.INSTANCE; });
        assertEquals("STALE_SCREEN", results.get(0).getCode());
        verify(service, never()).dispatchGesture(any(), any(), any());
    }

    @Test
    public void invalidCoordinatesNeverDispatchGesture() {
        tap(Double.NaN, 0.5, 1280, 2800, 0);
        tap(0.5, 1.1, 1280, 2800, 0);
        assertEquals(2, results.size());
        assertEquals("INVALID_COORDINATE", results.get(0).getCode());
        assertEquals("INVALID_COORDINATE", results.get(1).getCode());
        verify(service, never()).dispatchGesture(any(), any(), any());
    }

    @Test
    public void changedDimensionsOrRotationNeverDispatchGesture() {
        tap(0.5, 0.5, 2800, 1280, 0);
        tap(0.5, 0.5, 1280, 2800, 1);
        assertEquals(2, results.size());
        for (MobilePilotAccessibilityService.TapResult result : results) {
            assertEquals("STALE_SCREEN", result.getCode());
        }
        verify(service, never()).dispatchGesture(any(), any(), any());
    }

    @Test
    public void successfulDispatchWaitsForCompletionCallback() {
        when(service.dispatchGesture(any(), any(), any())).thenReturn(true);
        tap(0.25, 0.75, 1280, 2800, 0);
        assertTrue(results.isEmpty());
        ArgumentCaptor<GestureDescription> gesture = ArgumentCaptor.forClass(GestureDescription.class);
        ArgumentCaptor<AccessibilityService.GestureResultCallback> callback =
            ArgumentCaptor.forClass(AccessibilityService.GestureResultCallback.class);
        verify(service).dispatchGesture(gesture.capture(), callback.capture(), isNull());
        assertEquals(100, gesture.getValue().getStroke(0).getDuration());
        callback.getValue().onCompleted(gesture.getValue());
        assertEquals("GESTURE_COMPLETED", results.get(0).getCode());
    }

    @Test
    public void androidRejectionIsReportedAsFailure() {
        when(service.dispatchGesture(any(), any(), any())).thenReturn(false);
        tap(0.25, 0.75, 1280, 2800, 0);
        assertEquals(1, results.size());
        assertFalse(results.get(0).getSuccess());
        assertEquals("GESTURE_REJECTED", results.get(0).getCode());
    }
}
