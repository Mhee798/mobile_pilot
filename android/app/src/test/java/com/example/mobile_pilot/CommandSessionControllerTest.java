package com.example.mobile_pilot;

import kotlin.Unit;
import org.junit.Test;
import static org.junit.Assert.*;

public class CommandSessionControllerTest extends NativeControllerTest {
    @Test public void sessionBindsIdAndTarget() {
        CommandSessionController sessions = new CommandSessionController(handler, () -> Unit.INSTANCE);
        assertTrue(sessions.begin("run-1", TARGET));
        assertTrue(sessions.allows("run-1", TARGET));
        assertFalse(sessions.allows("run-1", PILOT));
        assertFalse(sessions.allows("old", TARGET));
        assertFalse(sessions.begin("run-2", TARGET));
    }
    @Test public void stopRevokesEveryLaterTool() {
        CommandSessionController sessions = new CommandSessionController(handler, () -> Unit.INSTANCE);
        sessions.begin("run-1", TARGET);
        sessions.cancel();
        assertFalse(sessions.allows("run-1", TARGET));
        assertFalse(sessions.isRunning());
    }
    @Test public void oldFinishCannotRevokeNewSession() {
        CommandSessionController sessions = new CommandSessionController(handler, () -> Unit.INSTANCE);
        sessions.begin("run-1", TARGET);
        sessions.finish("run-1");
        sessions.begin("run-2", TARGET);
        assertFalse(sessions.finish("run-1"));
        assertTrue(sessions.allows("run-2", TARGET));
    }
    @Test public void expiryRevokesAndStopsPendingToolsExactlyOnce() {
        int[] stops = {0};
        CommandSessionController sessions = new CommandSessionController(handler, () -> { stops[0]++; return Unit.INSTANCE; });
        sessions.begin("run-1", TARGET);
        advance(119_999);
        assertTrue(sessions.isRunning());
        advance(1);
        assertFalse(sessions.isRunning());
        assertEquals(1, stops[0]);
        advance(120_000);
        assertEquals(1, stops[0]);
    }
    @Test public void finishedSessionDoesNotExpireLater() {
        int[] stops = {0};
        CommandSessionController sessions = new CommandSessionController(handler, () -> { stops[0]++; return Unit.INSTANCE; });
        sessions.begin("run-1", TARGET);
        assertTrue(sessions.finish("run-1"));
        advance(120_000);
        assertEquals(0, stops[0]);
    }
}
