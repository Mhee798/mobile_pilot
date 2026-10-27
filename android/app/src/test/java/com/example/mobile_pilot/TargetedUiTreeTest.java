package com.example.mobile_pilot;

import org.junit.Test;
import static org.junit.Assert.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

public class TargetedUiTreeTest extends NativeControllerTest {
    @Test public void readRejectsARootFromAnotherApp() {
        foreground(PILOT);
        try {
            new UiTreeController(service).readUiTreeForPackage(TARGET);
            fail("Must reject wrong-package root");
        } catch (IllegalStateException expected) {
            assertTrue(expected.getMessage().contains("foreground"));
        }
    }

    @Test public void textTapRejectsARootFromAnotherApp() {
        foreground(PILOT);
        assertEquals("TARGET_NOT_READY", new UiTreeController(service)
            .tapElementForPackage("Battery", TARGET).getCode());
    }

    @Test public void gestureRejectsARootFromAnotherApp() {
        foreground("other.app");
        new UiTreeController(service).tapElementWithGestureForPackage("Battery", TARGET, result -> {
            assertEquals("TARGET_NOT_READY", result.getCode());
            return kotlin.Unit.INSTANCE;
        });
        verify(service, never()).dispatchGesture(any(), any(), any());
    }
}
