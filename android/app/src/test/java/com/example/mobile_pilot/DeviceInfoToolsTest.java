package com.example.mobile_pilot;

import static org.junit.Assert.*;
import java.util.Map;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 34, manifest = Config.NONE)
public class DeviceInfoToolsTest {
    @Test public void deviceDataHasVersionAndNonNegativeStorage() {
        Map<String, Object> info = DeviceInfoTools.INSTANCE.read(RuntimeEnvironment.getApplication());
        assertNotNull(info.get("model"));
        assertTrue(((Number) info.get("api_level")).intValue() > 0);
        assertTrue(((Number) info.get("storage_available_bytes")).longValue() >= 0);
        // Robolectric may report zero for its simulated filesystem.
        assertTrue(((Number) info.get("storage_total_bytes")).longValue() >= ((Number) info.get("storage_available_bytes")).longValue());
    }
    @Test public void mediaVolumeHasValidBounds() {
        Map<String, Object> volume = DeviceInfoTools.INSTANCE.volume(RuntimeEnvironment.getApplication());
        assertTrue(((Number) volume.get("current")).intValue() >= 0);
        assertTrue(((Number) volume.get("maximum")).intValue() >= ((Number) volume.get("current")).intValue());
    }
}
