package com.example.mobile_pilot;
import java.util.Map;
import org.junit.Test;
import static org.junit.Assert.*;
public class UiConditionTrackerTest {
 @Test public void enabledRequiresClickableAndStableForeground() {
  UiConditionTracker tracker=new UiConditionTracker("enabled");Map<String,Object> ready=Map.of("enabled",true,"clickable",true);
  assertNull(tracker.evaluate(0,true,Map.of("enabled",true,"clickable",false),true,false));
  assertNull(tracker.evaluate(100,true,ready,true,false));assertNull(tracker.evaluate(500,false,ready,true,false));
  assertNull(tracker.evaluate(600,true,ready,true,false));assertEquals("UI_ENABLED",tracker.evaluate(1100,true,ready,true,false).getCode());
 }
 @Test public void textChangeCapturesBaselineBeforeAcceptingNewText() {
  UiConditionTracker tracker=new UiConditionTracker("textChanged");
  assertNull(tracker.evaluate(0,true,Map.of("text","old"),true,false));
  assertNull(tracker.evaluate(250,true,Map.of("text","new"),true,false));
  assertEquals("UI_TEXT_CHANGED",tracker.evaluate(750,true,Map.of("text","new"),true,false).getCode());assertEquals("old",tracker.getBeforeText());
 }
 @Test public void changedTextMustKeepTheSameNewValue() {
  UiConditionTracker tracker=new UiConditionTracker("textChanged");tracker.evaluate(0,true,Map.of("text","A"),true,false);
  tracker.evaluate(250,true,Map.of("text","B"),true,false);assertNull(tracker.evaluate(500,true,Map.of("text","C"),true,false));
  assertNull(tracker.evaluate(750,true,Map.of("text","C"),true,false));assertNotNull(tracker.evaluate(1000,true,Map.of("text","C"),true,false));
 }
 @Test public void missingElementAndIncompleteScanCannotProveTextChanged() {
  UiConditionTracker tracker=new UiConditionTracker("textChanged");tracker.evaluate(0,true,Map.of("text","old"),true,false);
  assertNull(tracker.evaluate(1000,true,null,true,false));assertNull(tracker.evaluate(2000,true,Map.of("text","new"),false,false));
 }
 @Test public void duplicateLocatorIsExplicitlyAmbiguous() {
  assertEquals("UI_AMBIGUOUS",new UiConditionTracker("textChanged").evaluate(0,true,null,true,true).getCode());
 }
 @Test public void returningToOriginalTextResetsChangeTimer() {
  UiConditionTracker tracker=new UiConditionTracker("textChanged");tracker.evaluate(0,true,Map.of("text","A"),true,false);tracker.evaluate(250,true,Map.of("text","B"),true,false);
  tracker.evaluate(500,true,Map.of("text","A"),true,false);assertNull(tracker.evaluate(1000,true,Map.of("text","B"),true,false));
 }
}
