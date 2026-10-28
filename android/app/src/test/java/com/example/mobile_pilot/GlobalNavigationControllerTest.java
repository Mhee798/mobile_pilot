package com.example.mobile_pilot;
import android.accessibilityservice.AccessibilityService;
import org.junit.Test;
import static org.junit.Assert.*;
import static org.mockito.Mockito.*;

public class GlobalNavigationControllerTest extends NativeControllerTest {
    @Test public void backOnlyDispatchesInSelectedApp() {
        foreground(TARGET);
        when(service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK)).thenReturn(true);
        assertEquals("BACK_DISPATCHED", new GlobalNavigationController(service).back(TARGET).getCode());
        verify(service).performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK);
    }
    @Test public void backRejectsAnotherForegroundApp() {
        foreground("other.app");
        assertEquals("TARGET_NOT_READY", new GlobalNavigationController(service).back(TARGET).getCode());
        verify(service, never()).performGlobalAction(anyInt());
    }
    @Test public void backRejectsMobilePilotItself() {
        foreground(PILOT);
        assertEquals("TARGET_NOT_READY", new GlobalNavigationController(service).back(PILOT).getCode());
        verify(service, never()).performGlobalAction(anyInt());
    }
    @Test public void homeWorksWithoutForegroundRoot() {
        when(service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_HOME)).thenReturn(true);
        assertTrue(new GlobalNavigationController(service).navigate("home").getSuccess());
        verify(service).performGlobalAction(AccessibilityService.GLOBAL_ACTION_HOME);
        verify(service, never()).getRootInActiveWindow();
    }
    @Test public void recentsUsesSystemAction() {
        when(service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_RECENTS)).thenReturn(true);
        assertEquals("NAVIGATION_DISPATCHED", new GlobalNavigationController(service).navigate("recents").getCode());
        verify(service).performGlobalAction(AccessibilityService.GLOBAL_ACTION_RECENTS);
    }
    @Test public void rejectionIsNotReportedAsSuccess() {
        assertEquals("NAVIGATION_REJECTED", new GlobalNavigationController(service).navigate("home").getCode());
    }
    @Test public void invalidActionCannotNavigate() {
        assertEquals("INVALID_ARGUMENT", new GlobalNavigationController(service).navigate("unknown").getCode());
        verify(service, never()).performGlobalAction(anyInt());
    }
}
