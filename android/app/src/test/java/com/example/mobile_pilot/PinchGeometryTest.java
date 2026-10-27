package com.example.mobile_pilot;

import org.junit.Test;
import static org.junit.Assert.*;

public class PinchGeometryTest extends NativeControllerTest {
    @Test public void strongPresetsTravelSixtyPercentOfShortSideWithoutLeavingScreen() {
        PinchGeometry expand=PinchGeometry.Companion.create(.5,.5,1280,2800,new PinchOptions(.2,4,"horizontal"));
        PinchGeometry shrink=PinchGeometry.Companion.create(.5,.5,1280,2800,new PinchOptions(.8,.25,"horizontal"));
        assertNotNull(expand);assertNotNull(shrink);
        assertEquals(expand.getFirstStart().x,shrink.getFirstEnd().x,.01);
        assertEquals(expand.getFirstEnd().x,shrink.getFirstStart().x,.01);
        assertEquals(384,expand.getFirstStart().x-expand.getFirstEnd().x,.01);
        assertEquals(384,shrink.getSecondStart().x-shrink.getSecondEnd().x,.01);
    }
    @Test public void expandingMovesBothFingersAwayFromCenter() {
        PinchGeometry g=PinchGeometry.Companion.create(.5,.5,1280,2800,new PinchOptions(.25,2,"horizontal"));
        assertNotNull(g);
        assertEquals(480,g.getFirstStart().x,.01);
        assertEquals(320,g.getFirstEnd().x,.01);
        assertEquals(800,g.getSecondStart().x,.01);
        assertEquals(960,g.getSecondEnd().x,.01);
        assertEquals(1400,g.getFirstEnd().y,.01);
    }
    @Test public void shrinkingMovesFingersTowardCenter() {
        PinchGeometry g=PinchGeometry.Companion.create(.5,.5,1280,2800,new PinchOptions(.25,.5,"horizontal"));
        assertNotNull(g);
        assertEquals(560,g.getFirstEnd().x,.01);
        assertEquals(720,g.getSecondEnd().x,.01);
    }
    @Test public void verticalSpanUsesShorterSideRatherThanHeight() {
        PinchGeometry g=PinchGeometry.Companion.create(.5,.5,1280,2800,new PinchOptions(.25,2,"vertical"));
        assertNotNull(g);
        assertEquals(1240,g.getFirstStart().y,.01);
        assertEquals(1080,g.getFirstEnd().y,.01);
        assertEquals(640,g.getSecondEnd().x,.01);
    }
    @Test public void outOfBoundsStartOrEndIsRejectedWithoutClamping() {
        assertNull(PinchGeometry.Companion.create(.1,.5,1280,2800,new PinchOptions(.25,2,"horizontal")));
        assertNull(PinchGeometry.Companion.create(.1,.5,1280,2800,new PinchOptions(.15,1.5,"horizontal")));
    }
    @Test public void invalidScaleSpanAxisOrCenterIsRejected() {
        assertNull(PinchGeometry.Companion.create(Double.NaN,.5,1280,2800,new PinchOptions(.25,2,"horizontal")));
        for(PinchOptions o:new PinchOptions[]{new PinchOptions(.25,1,"horizontal"),new PinchOptions(.01,2,"horizontal"),
            new PinchOptions(.25,Double.NaN,"horizontal"),new PinchOptions(.25,2,"diagonal")}) {
            assertNull(PinchGeometry.Companion.create(.5,.5,1280,2800,o));
        }
    }
}
