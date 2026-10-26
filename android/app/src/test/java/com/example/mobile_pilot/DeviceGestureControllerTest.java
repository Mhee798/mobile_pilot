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
