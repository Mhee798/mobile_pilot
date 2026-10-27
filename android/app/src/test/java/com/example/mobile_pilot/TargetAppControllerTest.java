package com.example.mobile_pilot;

import java.util.ArrayList;
import java.util.List;
import kotlin.Unit;
import org.junit.Test;
import static org.junit.Assert.*;

public class TargetAppControllerTest extends NativeControllerTest {
    private final List<Boolean> results = new ArrayList<>();

    private TargetAppController waitForTarget() {
        TargetAppController controller = new TargetAppController(handler);
        controller.awaitReady(TARGET, () -> service, ready -> {
            results.add(ready);
            return Unit.INSTANCE;
        });
        return controller;
    }

    @Test public void requiresStableTargetRootRatherThanAnAppLaunchIntent() {
        foreground(PILOT);
        waitForTarget();
        advance(500);
        assertTrue(results.isEmpty());
        foreground(TARGET);
        advance(500);
        assertTrue(results.isEmpty());
        advance(100);
        assertEquals(java.util.Collections.singletonList(true), results);
    }

    @Test public void shortForegroundAppearanceDoesNotCountAsReady() {
        foreground(TARGET);
        waitForTarget();
        advance(400);
        foreground(PILOT);
        advance(200);
        foreground(TARGET);
        advance(500);
        assertTrue(results.isEmpty());
        advance(100);
        assertEquals(java.util.Collections.singletonList(true), results);
    }

    @Test public void wrongAppTimesOutExactlyOnce() {
        foreground("other.app");
        waitForTarget();
        advance(10_000);
        assertEquals(java.util.Collections.singletonList(false), results);
        foreground(TARGET);
        advance(1_000);
        assertEquals(1, results.size());
    }

    @Test public void targetChangeCancelsPreviousWait() {
        foreground(TARGET);
        TargetAppController controller = waitForTarget();
        advance(200);
        controller.cancelWaiting();
        advance(500);
        assertEquals(java.util.Collections.singletonList(false), results);
    }

    @Test public void missingServiceFailsWithoutWaiting() {
        new TargetAppController(handler).awaitReady(TARGET, () -> null, ready -> {
            results.add(ready);
            return Unit.INSTANCE;
        });
        assertEquals(java.util.Collections.singletonList(false), results);
    }
}
