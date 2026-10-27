package com.example.mobile_pilot;
import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.GestureDescription;
import android.graphics.Rect;
import android.graphics.RectF;
import org.junit.Test;
import org.mockito.ArgumentCaptor;
import static org.junit.Assert.*;
import static org.mockito.Mockito.*;
import kotlin.Unit;

public class ScrollGestureControllerTest extends NativeControllerTest {
 @Test public void longSwipeUsesEightyPercentOfContainerAndCorrectDirection() {
  when(service.dispatchGesture(any(),any(),isNull())).thenReturn(true);
  assertTrue(new ScrollGestureController(service).dispatch(new Rect(100,200,500,1200),"down",.8, ok -> Unit.INSTANCE));
  ArgumentCaptor<GestureDescription> captor=ArgumentCaptor.forClass(GestureDescription.class);
  verify(service).dispatchGesture(captor.capture(),any(),isNull());
  RectF bounds=new RectF();captor.getValue().getStroke(0).getPath().computeBounds(bounds,true);
  assertEquals(300,bounds.top,.1);assertEquals(1100,bounds.bottom,.1);
  assertEquals(300,bounds.left,.1);assertEquals(600,captor.getValue().getStroke(0).getDuration());
 }
 @Test public void shortSwipeUsesFortyPercentAndPropagatesCancellation() {
  when(service.dispatchGesture(any(),any(),isNull())).thenReturn(true);
  boolean[] completed={true};
  new ScrollGestureController(service).dispatch(new Rect(0,0,500,1000),"up",.4,ok -> {completed[0]=ok;return Unit.INSTANCE;});
  ArgumentCaptor<GestureDescription> gesture=ArgumentCaptor.forClass(GestureDescription.class);
  ArgumentCaptor<AccessibilityService.GestureResultCallback> callback=ArgumentCaptor.forClass(AccessibilityService.GestureResultCallback.class);
  verify(service).dispatchGesture(gesture.capture(),callback.capture(),isNull());
  RectF bounds=new RectF();gesture.getValue().getStroke(0).getPath().computeBounds(bounds,true);
  assertEquals(400,bounds.height(),.1);
  callback.getValue().onCancelled(gesture.getValue());assertFalse(completed[0]);
 }
 @Test public void invalidContainerDoesNotDispatch() {
  assertFalse(new ScrollGestureController(service).dispatch(new Rect(0,0,10,10),"down",.8,ok -> Unit.INSTANCE));
  verify(service,never()).dispatchGesture(any(),any(),any());
 }
}
