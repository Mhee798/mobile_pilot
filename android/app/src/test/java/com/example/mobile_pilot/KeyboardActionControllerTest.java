package com.example.mobile_pilot;
import android.view.KeyEvent;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.inputmethod.EditorInfo;
import java.util.List;
import org.junit.Before;
import org.junit.Test;
import org.mockito.ArgumentCaptor;
import static org.junit.Assert.*;
import static org.mockito.Mockito.*;

public class KeyboardActionControllerTest extends NativeControllerTest {
 private KeyboardActionController keyboard;private AccessibilityNodeInfo field;
 private KeyboardEditor editor;private EditorInfo info;
 @Before public void setupKeyboard() {
  AccessibilityNodeInfo root=foreground(TARGET);field=mock(AccessibilityNodeInfo.class);
  when(root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)).thenReturn(field);
  when(field.isEditable()).thenReturn(true);when(field.isEnabled()).thenReturn(true);when(field.getPackageName()).thenReturn(TARGET);
  editor=mock(KeyboardEditor.class);info=new EditorInfo();info.packageName=TARGET;info.imeOptions=EditorInfo.IME_ACTION_SEARCH;
  when(editor.info()).thenReturn(info);when(editor.action(anyString(),anyInt())).thenReturn(true);when(editor.enter(anyString())).thenReturn(true);
  keyboard=new KeyboardActionController(service,editor);
 }
 @Test public void searchUsesAdvertisedActionAndRejectsMismatchedNext() {
  assertEquals("IME_DISPATCHED",keyboard.perform(TARGET,"search").getCode());verify(editor).action(TARGET,EditorInfo.IME_ACTION_SEARCH);
  assertEquals("IME_ACTION_MISMATCH",keyboard.perform(TARGET,"next").getCode());verify(editor,never()).action(TARGET,EditorInfo.IME_ACTION_NEXT);
 }
 @Test public void editorConnectionFromOtherAppIsRejected() {
  info.packageName=PILOT;assertEquals("IME_UNAVAILABLE",keyboard.perform(TARGET,"enter").getCode());verify(editor,never()).enter(anyString());verify(editor,never()).action(anyString(),anyInt());
 }
 @Test public void passwordCannotReceiveKeyboardAction() {
  when(field.isPassword()).thenReturn(true);assertEquals("INPUT_NOT_ACTIONABLE",keyboard.perform(TARGET,"search").getCode());verify(editor,never()).enter(anyString());verify(editor,never()).action(anyString(),anyInt());
 }
 @Test public void enterUsesBoundEditorAndPropagatesUnavailableConnection() {
  assertTrue(keyboard.perform(TARGET,"enter").getSuccess());verify(editor).enter(TARGET);
  when(editor.enter(TARGET)).thenReturn(false);assertEquals("IME_UNAVAILABLE",keyboard.perform(TARGET,"enter").getCode());
 }
 @Test public void defaultDoesNotDispatchAfterForegroundChanges() {
  AccessibilityNodeInfo first=service.getRootInActiveWindow();
  AccessibilityNodeInfo other=mock(AccessibilityNodeInfo.class);when(other.getPackageName()).thenReturn(PILOT);
  when(field.getActionList()).thenReturn(List.of(AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER));
  when(service.getRootInActiveWindow()).thenReturn(first,other);
  assertEquals("TARGET_NOT_READY",keyboard.perform(TARGET,"default").getCode());
  verify(field,never()).performAction(anyInt());
 }
 @Test public void defaultUsesOnlyExposedImeNodeAction() {
  assertEquals("IME_UNSUPPORTED",keyboard.perform(TARGET,"default").getCode());
  when(field.getActionList()).thenReturn(List.of(AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER));when(field.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.getId())).thenReturn(true);
  assertTrue(keyboard.perform(TARGET,"default").getSuccess());
 }
}
