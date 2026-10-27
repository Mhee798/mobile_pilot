package com.example.mobile_pilot;

import android.app.Activity;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.lang.reflect.Field;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;
import kotlin.Unit;
import kotlin.jvm.functions.Function1;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

public class CommandSessionGateTest extends NativeControllerTest {
    private Field activeField;
    private Object previous;
    private MobilePilotAccessibilityService active;
    private MobilePilotMethodCallHandler bridge;
    private final AtomicBoolean live = new AtomicBoolean(true);

    @Before public void setActiveService() throws Exception {
        activeField = MobilePilotAccessibilityService.class.getDeclaredField("activeService");
        activeField.setAccessible(true);
        previous = activeField.get(null);
        active = mock(MobilePilotAccessibilityService.class);
        activeField.set(null, active);
        when(active.allowsCommandSession(eq("run-1"), nullable(String.class))).thenAnswer(inv -> live.get());
        when(active.hasCommandSession()).thenReturn(true);
        Activity activity = mock(Activity.class);
        when(activity.getPackageName()).thenReturn(PILOT);
        bridge = new MobilePilotMethodCallHandler(activity);
    }
    @After public void restoreService() throws Exception { activeField.set(null, previous); }

    @Test public void stopWhileAwaitingForegroundPreventsDelayedClick() {
        @SuppressWarnings("unchecked") Function1<Boolean, Unit>[] callback = new Function1[1];
        doAnswer(inv -> { callback[0] = inv.getArgument(1); return Unit.INSTANCE; })
            .when(active).awaitTargetReady(eq(TARGET), any());
        MethodChannel.Result result = mock(MethodChannel.Result.class);
        bridge.onMethodCall(new MethodCall("tapElementById", Map.of("runId","run-1", "targetPackage",TARGET,
            "screenId","screen-1", "nodeId","node-1")), result);
        live.set(false);
        callback[0].invoke(true);
        verify(active, never()).tapElementById(anyString(), anyString(), anyString());
        verify(result).error(eq("SEQUENCE_CANCELLED"), anyString(), isNull());
    }
    @Test public void manualToolCannotInterfereWithActiveRun() {
        MethodChannel.Result result = mock(MethodChannel.Result.class);
        bridge.onMethodCall(new MethodCall("getUiTree", Map.of("targetPackage",TARGET)), result);
        verify(active, never()).awaitTargetReady(anyString(), any());
        verify(result).error(eq("SEQUENCE_BUSY"), anyString(), isNull());
    }
}
