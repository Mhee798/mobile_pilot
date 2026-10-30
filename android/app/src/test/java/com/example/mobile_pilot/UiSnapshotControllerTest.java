package com.example.mobile_pilot;

import android.graphics.Rect;
import android.view.accessibility.AccessibilityNodeInfo;
import java.util.List;
import java.util.Map;
import org.junit.Before;
import org.junit.Test;
import static org.junit.Assert.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

public class UiSnapshotControllerTest extends NativeControllerTest {
    private UiSnapshotController snapshots;
    private AccessibilityNodeInfo root;
    @Before public void createSnapshots() {
        snapshots = new UiSnapshotController(service);
        root = foreground(TARGET);
        when(root.getText()).thenReturn("Open");
        when(root.isVisibleToUser()).thenReturn(true);
        when(root.isEnabled()).thenReturn(true);
        when(root.isClickable()).thenReturn(true);
        when(root.performAction(AccessibilityNodeInfo.ACTION_CLICK)).thenReturn(true);
    }
    private Map<String, Object> read() { return snapshots.read(TARGET).get(0); }
    private String tap(Map<String, Object> item) {
        return snapshots.tap((String)item.get("screenId"), (String)item.get("nodeId"), TARGET).getCode();
    }

    @Test public void replaceUsesExactEditableReferenceAndIsSingleUse() {
        when(root.isEditable()).thenReturn(true);
        when(root.performAction(eq(AccessibilityNodeInfo.ACTION_SET_TEXT),any())).thenReturn(true);
        Map<String,Object> item=read();
        assertEquals("INPUT_DISPATCHED",snapshots.edit((String)item.get("screenId"),(String)item.get("nodeId"),TARGET,"replace","new value").getCode());
        org.mockito.ArgumentCaptor<android.os.Bundle> bundle=org.mockito.ArgumentCaptor.forClass(android.os.Bundle.class);
        verify(root).performAction(eq(AccessibilityNodeInfo.ACTION_SET_TEXT),bundle.capture());
        assertEquals("new value",bundle.getValue().getCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE));
        assertEquals("STALE_SCREEN",snapshots.edit((String)item.get("screenId"),(String)item.get("nodeId"),TARGET,"clear","").getCode());
    }
    @Test public void passwordAndChangedTextRejectEditing() {
        when(root.isEditable()).thenReturn(true);when(root.isPassword()).thenReturn(true);
        Map<String,Object> item=read();
        assertEquals("NODE_NOT_ACTIONABLE",snapshots.edit((String)item.get("screenId"),(String)item.get("nodeId"),TARGET,"clear","").getCode());
        when(root.isPassword()).thenReturn(false);item=read();when(root.getText()).thenReturn("Changed");
        assertEquals("STALE_SCREEN",snapshots.edit((String)item.get("screenId"),(String)item.get("nodeId"),TARGET,"replace","x").getCode());
        verify(root,never()).performAction(anyInt(),any());
    }
    @Test public void clearUsesEmptyTextAndFocusUsesInputFocusAction() {
        when(root.isEditable()).thenReturn(true);
        when(root.performAction(eq(AccessibilityNodeInfo.ACTION_SET_TEXT),any())).thenReturn(true);
        when(root.performAction(AccessibilityNodeInfo.ACTION_FOCUS)).thenReturn(true);
        Map<String,Object> item=read();
        snapshots.edit((String)item.get("screenId"),(String)item.get("nodeId"),TARGET,"clear","ignored");
        org.mockito.ArgumentCaptor<android.os.Bundle> bundle=org.mockito.ArgumentCaptor.forClass(android.os.Bundle.class);
        verify(root).performAction(eq(AccessibilityNodeInfo.ACTION_SET_TEXT),bundle.capture());
        assertEquals("",bundle.getValue().getCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE));
        item=read();snapshots.edit((String)item.get("screenId"),(String)item.get("nodeId"),TARGET,"focus","");
        verify(root).performAction(AccessibilityNodeInfo.ACTION_FOCUS);
    }
    @Test public void checkedStateChangeRejectsOldReference() {
        when(root.isCheckable()).thenReturn(true);
        Map<String,Object> item = read();
        when(root.isChecked()).thenReturn(true);
        assertEquals("STALE_SCREEN", tap(item));
        verify(root, never()).performAction(anyInt());
    }
    @Test public void referencesAreSingleUseAndRejectOlderReads() {
        Map<String,Object> old = read();
        Map<String,Object> current = read();
        assertNotEquals(old.get("screenId"), current.get("screenId"));
        assertEquals("STALE_SCREEN", tap(old));
        assertEquals("ACTION_DISPATCHED", tap(current));
        assertEquals("STALE_SCREEN", tap(current));
        verify(root, times(1)).performAction(AccessibilityNodeInfo.ACTION_CLICK);
    }
    @Test public void textChangeRejectsInsteadOfClicking() {
        Map<String,Object> item = read();
        when(root.getText()).thenReturn("Delete");
        assertEquals("STALE_SCREEN", tap(item));
        verify(root, never()).performAction(anyInt());
    }
    @Test public void boundsChangeRejectsInsteadOfClicking() {
        Map<String,Object> item = read();
        doAnswer(inv -> { ((Rect)inv.getArgument(0)).set(10,20,30,40); return null; }).when(root).getBoundsInScreen(any());
        assertEquals("STALE_SCREEN", tap(item));
        verify(root, never()).performAction(anyInt());
    }
    @Test public void nodeCannotTargetAnotherPackage() {
        Map<String,Object> item = read();
        assertEquals("STALE_SCREEN", snapshots.tap((String)item.get("screenId"), (String)item.get("nodeId"), "other.app").getCode());
        verify(root, never()).performAction(anyInt());
    }
    @Test public void hiddenOrDisabledReferenceCannotClick() {
        when(root.isEnabled()).thenReturn(false);
        Map<String,Object> item = read();
        assertEquals("NODE_NOT_ACTIONABLE", tap(item));
        verify(root, never()).performAction(anyInt());
    }
    @Test public void identicalLabelsAreResolvedByNodePath() {
        when(root.getText()).thenReturn(null);
        when(root.isClickable()).thenReturn(false);
        AccessibilityNodeInfo first = mock(AccessibilityNodeInfo.class);
        AccessibilityNodeInfo second = mock(AccessibilityNodeInfo.class);
        for (AccessibilityNodeInfo child : new AccessibilityNodeInfo[]{first,second}) {
            when(child.getText()).thenReturn("Open");
            when(child.isClickable()).thenReturn(true);
            when(child.isEnabled()).thenReturn(true);
            when(child.isVisibleToUser()).thenReturn(true);
            when(child.performAction(AccessibilityNodeInfo.ACTION_CLICK)).thenReturn(true);
        }
        when(root.getChildCount()).thenReturn(2);
        when(root.getChild(0)).thenReturn(first);
        when(root.getChild(1)).thenReturn(second);
        List<Map<String,Object>> items = snapshots.read(TARGET);
        assertEquals(2, items.size());
        assertNotEquals(items.get(0).get("nodeId"), items.get(1).get("nodeId"));
        assertEquals("ACTION_DISPATCHED", tap(items.get(1)));
        verify(first, never()).performAction(anyInt());
        verify(second).performAction(AccessibilityNodeInfo.ACTION_CLICK);
    }
    @Test public void nodeIdMustBelongToTheSnapshot() {
        Map<String,Object> item = read();
        assertEquals("INVALID_NODE", snapshots.tap((String)item.get("screenId"), "node-99", TARGET).getCode());
        verify(root, never()).performAction(anyInt());
    }
    @Test public void explicitInvalidationRejectsPendingReferences() {
        Map<String,Object> item = read();
        snapshots.invalidate();
        assertEquals("STALE_SCREEN", tap(item));
    }
    @Test public void uniqueDescriptionWithStableClassAndBoundsToleratesUnrelatedChanges() {
        AccessibilityNodeInfo child = liveSibling();
        when(root.getViewIdResourceName()).thenReturn(null);
        when(root.getContentDescription()).thenReturn("Search");
        when(root.getClassName()).thenReturn("android.widget.ImageButton");
        doAnswer(inv -> { ((Rect)inv.getArgument(0)).set(10,20,80,90); return null; }).when(root).getBoundsInScreen(any());
        Map<String,Object> item = read();
        when(child.getText()).thenReturn("New ad");
        assertEquals("ACTION_DISPATCHED", tap(item));
        item = read();
        when(child.getText()).thenReturn("Another ad");
        when(child.getContentDescription()).thenReturn("Search");
        assertEquals("STALE_SCREEN", tap(item));
        verify(root, times(1)).performAction(AccessibilityNodeInfo.ACTION_CLICK);
    }

    private AccessibilityNodeInfo liveSibling() {
        AccessibilityNodeInfo child = mock(AccessibilityNodeInfo.class);
        when(child.getText()).thenReturn("Advertisement 1");
        when(root.getChildCount()).thenReturn(1);
        when(root.getChild(0)).thenReturn(child);
        when(root.getViewIdResourceName()).thenReturn("app:id/search");
        return child;
    }
    @Test public void unrelatedLiveContentCanChangeWhileExactUniqueTargetStaysUnchanged() {
        AccessibilityNodeInfo child = liveSibling();
        Map<String,Object> item = read();
        when(child.getText()).thenReturn("Advertisement 2");
        assertEquals("ACTION_DISPATCHED", tap(item));
        assertEquals("STALE_SCREEN", tap(item));
        verify(root, times(1)).performAction(AccessibilityNodeInfo.ACTION_CLICK);
    }
    @Test public void changedTargetOrWindowStillRejectsWithLiveContent() {
        AccessibilityNodeInfo child = liveSibling();
        Map<String,Object> item = read();
        when(child.getText()).thenReturn("Advertisement 2");
        when(root.getText()).thenReturn("Delete");
        assertEquals("STALE_SCREEN", tap(item));
        item = read();
        when(child.getText()).thenReturn("Advertisement 3");
        when(root.getWindowId()).thenReturn(2);
        assertEquals("STALE_SCREEN", tap(item));
        verify(root, never()).performAction(anyInt());
    }
    @Test public void missingOrDuplicateIdentityDoesNotEnableLiveContentFallback() {
        AccessibilityNodeInfo child = liveSibling();
        when(root.getViewIdResourceName()).thenReturn(null);
        Map<String,Object> item = read();
        when(child.getText()).thenReturn("Advertisement 2");
        assertEquals("STALE_SCREEN", tap(item));
        when(root.getViewIdResourceName()).thenReturn("app:id/search");
        item = read();
        when(child.getText()).thenReturn("Open");
        when(child.getViewIdResourceName()).thenReturn("app:id/search");
        assertEquals("STALE_SCREEN", tap(item));
        verify(root, never()).performAction(anyInt());
    }
    @Test public void liveContentFallbackNeverAppliesToTextEditing() {
        AccessibilityNodeInfo child = liveSibling();
        when(root.isEditable()).thenReturn(true);
        Map<String,Object> item = read();
        when(child.getText()).thenReturn("Advertisement 2");
        assertEquals("STALE_SCREEN", snapshots.edit((String)item.get("screenId"),
            (String)item.get("nodeId"), TARGET, "replace", "new text").getCode());
        verify(root, never()).performAction(anyInt(), any());
    }
    @Test public void unchangedToolbarTargetNeedsItsUnlabelledAncestorsUnchangedToo() {
        AccessibilityNodeInfo search = mock(AccessibilityNodeInfo.class);
        AccessibilityNodeInfo ad = mock(AccessibilityNodeInfo.class);
        when(root.getText()).thenReturn(null);
        when(root.isClickable()).thenReturn(false);
        when(root.getChildCount()).thenReturn(2);
        when(root.getChild(0)).thenReturn(search);
        when(root.getChild(1)).thenReturn(ad);
        when(search.getViewIdResourceName()).thenReturn("app:id/menu_item");
        when(search.getContentDescription()).thenReturn("Search");
        when(search.isVisibleToUser()).thenReturn(true);
        when(search.isEnabled()).thenReturn(true);
        when(search.isClickable()).thenReturn(true);
        when(search.performAction(AccessibilityNodeInfo.ACTION_CLICK)).thenReturn(true);
        when(ad.getText()).thenReturn("Ad 1");
        Map<String,Object> item = read();
        when(ad.getText()).thenReturn("Ad 2");
        assertEquals("ACTION_DISPATCHED", tap(item));
        item = read();
        when(ad.getText()).thenReturn("Ad 3");
        when(root.getContentDescription()).thenReturn("Different page");
        assertEquals("STALE_SCREEN", tap(item));
        verify(search, times(1)).performAction(AccessibilityNodeInfo.ACTION_CLICK);
    }
}
