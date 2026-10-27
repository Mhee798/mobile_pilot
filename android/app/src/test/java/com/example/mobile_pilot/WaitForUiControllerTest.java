package com.example.mobile_pilot;

import android.view.accessibility.AccessibilityNodeInfo;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import kotlin.Unit;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import static org.junit.Assert.*;
import static org.mockito.Mockito.*;

public class WaitForUiControllerTest extends NativeControllerTest {
    private WaitForUiController wait;
    private List<Map<String, ?>> results;

    @Before public void createWait() {
        wait = new WaitForUiController(service, handler);
        results = new ArrayList<>();
    }
    @After public void cleanUp() { wait.cancel(null); }

    private void start(String id, String selector, String value, long timeout) {
        wait.start(id, TARGET, selector, value, timeout, response -> {
            results.add(response);
            return Unit.INSTANCE;
        });
    }
    private void start() { start("test-1", "text", "Search", 1000); }
    private void code(String expected) {
        assertEquals(1, results.size());
        assertEquals(expected, results.get(0).get("code"));
    }
    private AccessibilityNodeInfo matchingRoot(String pkg) {
        AccessibilityNodeInfo root = foreground(pkg);
        doAnswer(inv -> { ((android.graphics.Rect) inv.getArgument(0)).set(0,0,100,100); return null; }).when(root).getBoundsInScreen(any());
        when(root.isVisibleToUser()).thenReturn(true);
        when(root.getText()).thenReturn("Search");
        return root;
    }

    @Test public void presenceDoesNotMatchOffscreenVisibleFlag() {
        AccessibilityNodeInfo root=foreground(TARGET);
        doAnswer(inv->{((android.graphics.Rect)inv.getArgument(0)).set(0,0,100,100);return null;}).when(root).getBoundsInScreen(any());
        AccessibilityNodeInfo child=mock(AccessibilityNodeInfo.class);
        when(root.getChildCount()).thenReturn(1);when(root.getChild(0)).thenReturn(child);
        when(child.isVisibleToUser()).thenReturn(true);when(child.getText()).thenReturn("Search");
        doAnswer(inv->{((android.graphics.Rect)inv.getArgument(0)).set(0,200,100,250);return null;}).when(child).getBoundsInScreen(any());
        start();advance(500);assertTrue(results.isEmpty());
        doAnswer(inv->{((android.graphics.Rect)inv.getArgument(0)).set(0,20,100,50);return null;}).when(child).getBoundsInScreen(any());
        advance(250);code("UI_FOUND");
    }
    @Test public void enabledWaitAcceptsLabelInsideEnabledClickableButton() {
        AccessibilityNodeInfo root=foreground(TARGET);
        doAnswer(inv->{((android.graphics.Rect)inv.getArgument(0)).set(0,0,100,100);return null;}).when(root).getBoundsInScreen(any());
        when(root.isEnabled()).thenReturn(true);when(root.isClickable()).thenReturn(true);
        AccessibilityNodeInfo child=mock(AccessibilityNodeInfo.class);
        when(root.getChildCount()).thenReturn(1);when(root.getChild(0)).thenReturn(child);
        when(child.isVisibleToUser()).thenReturn(true);when(child.isEnabled()).thenReturn(true);when(child.getText()).thenReturn("Search");
        doAnswer(inv->{((android.graphics.Rect)inv.getArgument(0)).set(0,20,100,50);return null;}).when(child).getBoundsInScreen(any());
        wait.startCondition("ready-child",TARGET,"text","Search",5000,"enabled",response->{results.add(response);return Unit.INSTANCE;});
        advance(500);code("UI_ENABLED");verify(root,never()).performAction(anyInt());
    }

    @Test public void enabledWaitInspectsActualButtonStateWithoutClicking() {
        AccessibilityNodeInfo root=matchingRoot(TARGET);when(root.isClickable()).thenReturn(true);when(root.isEnabled()).thenReturn(false);
        wait.startCondition("ready-1",TARGET,"text","Search",5000,"enabled",response->{results.add(response);return Unit.INSTANCE;});
        advance(500);assertTrue(results.isEmpty());when(root.isEnabled()).thenReturn(true);advance(750);code("UI_ENABLED");verify(root,never()).performAction(anyInt());
    }
    @Test public void changedTextUsesStableResourceLocatorAndReturnsBothValues() {
        AccessibilityNodeInfo root=matchingRoot(TARGET);when(root.getViewIdResourceName()).thenReturn("app:id/status");
        wait.startCondition("changed-1",TARGET,"resourceId","app:id/status",5000,"textChanged",response->{results.add(response);return Unit.INSTANCE;});
        advance(250);when(root.getText()).thenReturn("Ready");advance(750);code("UI_TEXT_CHANGED");assertEquals("Search",results.get(0).get("beforeText"));
    }
    @Test public void textSelectorCannotBeUsedToTrackChangingText() {
        wait.startCondition("changed-1",TARGET,"text","Search",5000,"textChanged",response->{results.add(response);return Unit.INSTANCE;});code("INVALID_ARGUMENT");
    }

    private void disappear() {
        wait.startCondition("gone-1",TARGET,"text","Search",5000,"disappeared", response -> {results.add(response);return Unit.INSTANCE;});
    }
    @Test public void disappearanceRequiresPreviouslyObservedMatch() {
        foreground(TARGET);disappear();advance(5000);code("UI_TIMEOUT");
        assertEquals(false,results.get(0).get("matchSeen"));
    }
    @Test public void disappearanceRequiresContinuousAbsenceAndDoesNotClick() {
        AccessibilityNodeInfo root=matchingRoot(TARGET);disappear();advance(0);
        assertTrue(results.isEmpty());when(root.getText()).thenReturn("Other");
        advance(250);advance(499);assertTrue(results.isEmpty());advance(1);code("UI_DISAPPEARED");
        verify(root,never()).performAction(anyInt());
    }
    @Test public void switchingAppsCannotCountAsDisappearance() {
        matchingRoot(TARGET);disappear();advance(0);foreground(PILOT);advance(1000);
        assertTrue(results.isEmpty());AccessibilityNodeInfo root=matchingRoot(TARGET);
        when(root.getText()).thenReturn("Other");advance(250);advance(500);code("UI_DISAPPEARED");
    }
    @Test public void reappearingMatchResetsAbsenceTimer() {
        AccessibilityNodeInfo root=matchingRoot(TARGET);disappear();advance(0);
        when(root.getText()).thenReturn("Other");advance(500);
        when(root.getText()).thenReturn("Search");advance(250);
        when(root.getText()).thenReturn("Other");advance(500);assertTrue(results.isEmpty());
        advance(250);code("UI_DISAPPEARED");
    }
    @Test public void emptyWindowBoundsCannotProveDisappearance() {
        AccessibilityNodeInfo root=matchingRoot(TARGET);disappear();advance(0);
        when(root.getText()).thenReturn("Other");
        doAnswer(inv -> { ((android.graphics.Rect) inv.getArgument(0)).setEmpty(); return null; }).when(root).getBoundsInScreen(any());
        advance(5000);code("UI_TIMEOUT");
    }
    @Test public void unreadableChildCannotProveAbsence() {
        AccessibilityNodeInfo root=matchingRoot(TARGET);disappear();advance(0);
        when(root.getText()).thenReturn("Other");when(root.getChildCount()).thenReturn(1);
        advance(5000);code("UI_TIMEOUT");
    }

    private void scroll(int max, String direction) {
        wait.startScroll("scroll-1", TARGET, "text", "Search", 5000, direction, max, response -> {
            results.add(response); return Unit.INSTANCE;
        });
    }
    private AccessibilityNodeInfo scrollRoot() {
        AccessibilityNodeInfo root=foreground(TARGET);
        doAnswer(inv -> { ((android.graphics.Rect) inv.getArgument(0)).set(0,0,100,100); return null; }).when(root).getBoundsInScreen(any());
        when(root.isVisibleToUser()).thenReturn(true);
        when(root.isScrollable()).thenReturn(true);
        when(root.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)).thenReturn(true);
        return root;
    }
    @Test public void scrollWaitsForSettlingAndStopsBeforeClickingMatch() {
        AccessibilityNodeInfo root=scrollRoot();
        scroll(3,"down");advance(999);
        verify(root,never()).performAction(anyInt());
        advance(1);
        verify(root).performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD);
        when(root.getText()).thenReturn("Search");advance(250);
        code("UI_FOUND");assertEquals(1, results.get(0).get("scrollCount"));
        advance(3000);verify(root, times(1)).performAction(anyInt());
    }
    @Test public void longScrollWaitsForGestureCompletionBeforeNextSwipe() {
        AccessibilityNodeInfo root=scrollRoot();
        ScrollGestureController gestures=mock(ScrollGestureController.class);
        @SuppressWarnings("unchecked") kotlin.jvm.functions.Function1<Boolean, Unit>[] completion=new kotlin.jvm.functions.Function1[1];
        when(gestures.dispatch(any(),eq("down"),eq(.8),any())).thenAnswer(inv -> { completion[0]=inv.getArgument(3);return true; });
        wait=new WaitForUiController(service,handler,gestures);
        wait.startScrollWithDistance("long-1",TARGET,"text","Search",5000,"down",3,"long",response -> {results.add(response);return Unit.INSTANCE;});
        advance(3000);verify(gestures,times(1)).dispatch(any(),anyString(),anyDouble(),any());
        when(root.getText()).thenReturn("Search");advance(250);assertTrue(results.isEmpty());
        completion[0].invoke(true);advance(250);code("UI_FOUND");
        verify(root,never()).performAction(anyInt());
    }
    @Test public void cancelledLongSwipeStopsLookup() {
        scrollRoot();ScrollGestureController gestures=mock(ScrollGestureController.class);
        @SuppressWarnings("unchecked") kotlin.jvm.functions.Function1<Boolean, Unit>[] completion=new kotlin.jvm.functions.Function1[1];
        when(gestures.dispatch(any(),anyString(),anyDouble(),any())).thenAnswer(inv -> {completion[0]=inv.getArgument(3);return true;});
        wait=new WaitForUiController(service,handler,gestures);
        wait.startScrollWithDistance("long-1",TARGET,"text","Search",5000,"down",3,"long",response -> {results.add(response);return Unit.INSTANCE;});
        advance(1000);completion[0].invoke(false);advance(4000);code("SCROLL_CANCELLED");
        verify(gestures,times(1)).dispatch(any(),anyString(),anyDouble(),any());
    }
    @Test public void offscreenMatchDoesNotFinishBeforeScrollingIntoView() {
        AccessibilityNodeInfo root=scrollRoot();
        AccessibilityNodeInfo child=mock(AccessibilityNodeInfo.class);
        when(root.getChildCount()).thenReturn(1);when(root.getChild(0)).thenReturn(child);
        when(child.isVisibleToUser()).thenReturn(true);when(child.getText()).thenReturn("Search");
        doAnswer(inv -> { ((android.graphics.Rect) inv.getArgument(0)).set(0,200,100,240); return null; }).when(child).getBoundsInScreen(any());
        scroll(3,"down");advance(1000);assertTrue(results.isEmpty());
        doAnswer(inv -> { ((android.graphics.Rect) inv.getArgument(0)).set(0,50,100,90); return null; }).when(child).getBoundsInScreen(any());
        advance(250);code("UI_FOUND");assertEquals(1,results.get(0).get("scrollCount"));
    }
    @Test public void matchingInitialScreenDoesNotScroll() {
        AccessibilityNodeInfo root=matchingRoot(TARGET);
        scroll(3,"down");advance(0);code("UI_FOUND");
        verify(root,never()).performAction(anyInt());
    }
    @Test public void scrollLimitIncludesFinalScreenInspection() {
        AccessibilityNodeInfo root=scrollRoot();scroll(2,"down");advance(3000);
        code("SCROLL_LIMIT");verify(root,times(2)).performAction(anyInt());
    }
    @Test public void wrongAppNeverReceivesScrollAndLeavingTargetStops() {
        AccessibilityNodeInfo other=foreground(PILOT);
        scroll(3,"down");advance(500);verify(other,never()).performAction(anyInt());
        AccessibilityNodeInfo root=scrollRoot();advance(1000);
        foreground(PILOT);advance(250);code("SCROLL_TARGET_CHANGED");
        advance(2000);verify(root,never()).performAction(anyInt());
    }
    @Test public void cancelPreventsFurtherScrolling() {
        AccessibilityNodeInfo root=scrollRoot();scroll(3,"down");advance(1000);
        wait.cancel("scroll-1");advance(4000);code("UI_CANCELLED");
        verify(root,times(1)).performAction(anyInt());
    }
    @Test public void upwardScrollUsesBackwardAndReportsRejection() {
        AccessibilityNodeInfo root=scrollRoot();scroll(3,"up");advance(1000);
        code("SCROLL_UNAVAILABLE");verify(root).performAction(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD);
    }
    @Test public void missingScrollContainerIsExplicit() {
        foreground(TARGET);scroll(3,"down");advance(1000);code("SCROLL_UNAVAILABLE");
    }
    @Test public void invalidScrollBoundsDoNotAct() {
        AccessibilityNodeInfo root=scrollRoot();scroll(41,"down");advance(5000);
        code("INVALID_ARGUMENT");verify(root,never()).performAction(anyInt());
    }

    @Test public void visibleExactTextReturnsMetadataWithoutAnAction() {
        AccessibilityNodeInfo root = matchingRoot(TARGET);
        start("test-1", "text", " search ", 1000);
        advance(0);
        code("UI_FOUND");
        assertEquals(TARGET, results.get(0).get("targetPackage"));
        assertNotNull(results.get(0).get("element"));
        verify(root, never()).performAction(org.mockito.ArgumentMatchers.anyInt());
    }

    @Test public void hiddenOrPartialTextDoesNotMatch() {
        AccessibilityNodeInfo root = matchingRoot(TARGET);
        when(root.isVisibleToUser()).thenReturn(false);
        start();
        advance(250);
        doAnswer(inv -> { ((android.graphics.Rect) inv.getArgument(0)).set(0,0,100,100); return null; }).when(root).getBoundsInScreen(any());
        when(root.isVisibleToUser()).thenReturn(true);
        when(root.getText()).thenReturn("Search results");
        advance(750);
        code("UI_TIMEOUT");
    }

    @Test public void matchingTextInAnotherAppIsIgnored() {
        matchingRoot(PILOT);
        start();
        advance(500);
        assertTrue(results.isEmpty());
        matchingRoot(TARGET);
        advance(250);
        code("UI_FOUND");
    }

    @Test public void elementCanAppearWithoutAWindowEvent() {
        AccessibilityNodeInfo root = matchingRoot(TARGET);
        when(root.getText()).thenReturn("Loading");
        start();
        advance(500);
        assertTrue(wait.isWaiting());
        when(root.getText()).thenReturn("Search");
        advance(250);
        code("UI_FOUND");
    }

    @Test public void descriptionCanMatchWithoutText() {
        AccessibilityNodeInfo root = matchingRoot(TARGET);
        when(root.getText()).thenReturn(null);
        when(root.getContentDescription()).thenReturn("Search");
        start("test-1", "contentDescription", "Search", 1000);
        advance(0);
        code("UI_FOUND");
    }

    @Test public void resourceIdIsCaseSensitiveAndExact() {
        AccessibilityNodeInfo root = matchingRoot(TARGET);
        when(root.getViewIdResourceName()).thenReturn("app:id/Search");
        start("test-1", "resourceId", "app:id/search", 1000);
        advance(1000);
        code("UI_TIMEOUT");
        results.clear();
        start("test-2", "resourceId", "app:id/Search", 1000);
        advance(0);
        code("UI_FOUND");
    }

    @Test public void timeoutIsBoundedAndCanRetry() {
        foreground(PILOT);
        start();
        advance(999);
        assertTrue(results.isEmpty());
        advance(1);
        code("UI_TIMEOUT");
        assertEquals(1000L, results.get(0).get("elapsedMs"));
        assertFalse(wait.isWaiting());
        advance(5000);
        assertEquals(1, results.size());
        results.clear();
        matchingRoot(TARGET);
        start("test-2", "text", "Search", 1000);
        advance(0);
        code("UI_FOUND");
    }

    @Test public void cancelFinishesOnceAndPreventsLaterSuccess() {
        foreground(PILOT);
        start();
        advance(250);
        wait.cancel("test-1");
        matchingRoot(TARGET);
        advance(2000);
        code("UI_CANCELLED");
        assertFalse(wait.isWaiting());
    }

    @Test public void lateCancellationCannotCancelNewRequest() {
        foreground(PILOT);
        start();
        wait.cancel("test-1");
        results.clear();
        start("test-2", "text", "Search", 1000);
        wait.cancel("test-1");
        assertTrue(wait.isWaiting());
        matchingRoot(TARGET);
        advance(0);
        code("UI_FOUND");
        assertEquals("test-2", results.get(0).get("requestId"));
    }

    @Test public void concurrentWaitDoesNotReplaceFirstRequest() {
        foreground(PILOT);
        start();
        start("test-2", "text", "Other", 1000);
        code("UI_WAIT_IN_PROGRESS");
        results.clear();
        matchingRoot(TARGET);
        advance(0);
        code("UI_FOUND");
        assertEquals("test-1", results.get(0).get("requestId"));
    }

    @Test public void mismatchedRootAfterTraversalCannotPublishFound() {
        AccessibilityNodeInfo matching = matchingRoot(TARGET);
        AccessibilityNodeInfo other = mock(AccessibilityNodeInfo.class);
        when(other.getPackageName()).thenReturn(PILOT);
        when(service.getRootInActiveWindow()).thenReturn(matching, other);
        start();
        advance(1000);
        code("UI_TIMEOUT");
    }

    @Test public void descendantMatchRecyclesVisitedNodes() {
        AccessibilityNodeInfo root = foreground(TARGET);
        AccessibilityNodeInfo child = mock(AccessibilityNodeInfo.class);
        doAnswer(inv -> { ((android.graphics.Rect)inv.getArgument(0)).set(0,0,100,100); return null; }).when(root).getBoundsInScreen(any());
        doAnswer(inv -> { ((android.graphics.Rect)inv.getArgument(0)).set(0,10,100,50); return null; }).when(child).getBoundsInScreen(any());
        when(root.getChildCount()).thenReturn(1);
        when(root.getChild(0)).thenReturn(child);
        when(child.isVisibleToUser()).thenReturn(true);
        when(child.getText()).thenReturn("Search");
        start();
        advance(0);
        code("UI_FOUND");
        verify(child).recycle();
    }

    @Test public void invalidSelectorOrDeadlineDoesNotStartWork() {
        start("test-1", "regex", "Search", 1000);
        code("INVALID_ARGUMENT");
        results.clear();
        start("test-2", "text", "Search", 60_001);
        code("INVALID_ARGUMENT");
        assertFalse(wait.isWaiting());
        verify(service, never()).getRootInActiveWindow();
    }
}
