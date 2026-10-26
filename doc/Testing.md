# Testing MobilePilot

Run these commands from the repository root.

## Flutter

```powershell
flutter analyze
flutter test
```

The Flutter tests cover onboarding, the command screen, Platform Channel argument
contracts and errors, screenshot coordinate selection, shared busy state, and
polling timeout/disposal.

## Android controllers

```powershell
Push-Location android
.\gradlew.bat :app:testDebugUnitTest
Pop-Location
```

The tests use [Robolectric](https://robolectric.org/getting-started/) with Android
14 (API 34) on the JVM. Handler delays and timeouts run with a controlled clock;
they do not wait 30 or 60 real seconds. The first run downloads the test runtime.

| Suite | Behavior checked |
| --- | --- |
| `DeviceActionQueueTest` | Queue exclusion/replacement, 60-second expiry, cancel, foreground settling, stale display rejection, password-field blocking, and disposal. |
| `ScreenCaptureControllerTest` | 30-second expiry, 700-ms settling, cancellation, stale callbacks, rearming, and consuming results once. |
| `SettingsTapTestControllerTest` | Settings foreground checks, cancel, 20-second target timeout, five-second verification timeout, changed-tree verification, and disposal. |
| `DeviceGestureControllerTest` | Invalid coordinates, changed dimensions/rotation, Android rejection, and completion callbacks. |

HTML results: `build/app/reports/tests/testDebugUnitTest/index.html`.
JUnit XML results: `build/app/test-results/testDebugUnitTest/`.

## Android build

```powershell
flutter build apk --debug
```

## Device checks

These local tests mock device interfaces. They do not prove that another app
accepts a gesture, that screenshot pixels are correct, or that HONOR/other Android
devices deliver Accessibility events in the expected order. Repeat the real-device
capture, tap, scroll, text-entry and cancel checks after changes to these paths.

### Keep the service running during device checks

Do not run a stock `uiautomator dump` while a MobilePilot command is pending.
On the PTP N49, this interrupted Accessibility, recreated the floating overlay and
cleared a pending capture, producing false failures. Use `adb shell screencap`
and visible app feedback while an action is running.

An instrumentation harness should obtain UiAutomation with
[`FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES`](https://developer.android.com/reference/android/app/UiAutomation#FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES)
so its own connection does not suppress the service being tested.

### Regression found on the PTP N49 — 2026-10-26

A point tap could be cancelled by a MobilePilot window event even while the
target app's root was active. The queue now checks the actual foreground root
before interpreting that event as a return to MobilePilot. Two native tests
cover the outgoing/overlay event and a genuine return before dispatch.

The rebuilt APK opened Settings search through a selected screenshot coordinate
and inserted `MP_SAFE_REFACTOR_42` into the focused search field without pressing
the keyboard's submit button. The test text was cleared afterwards.

Post-refactor smoke run on PTP N49 (Android 16 / API 36):

| Check | Observed result |
| --- | --- |
| Accessibility and local tap button | Command page opened; tap counter changed from 0 to 1. |
| App search and launch | `Chrome` returned multiple candidates; selecting Chrome opened `com.android.chrome`. |
| UI tree | Exported 21 elements in the manual command screen. |
| Floating gestures | Settings scrolled in both directions, Home switched left/right and returned to the original page, and Back returned from device information to Settings. |
| Capture and point tap | Captured 1280×2800; the selected search-field point opened Settings search after the queue fix. |
| Focused text entry | The exact test string appeared in Settings search through MobilePilot's text command. |
| Cancel | Settings test changed from `waiting` to `cancelled`; opening the TalkBack list afterwards did not tap it. |
| Capture expiry and retry | Waiting over 30 seconds before switching apps produced the timeout message; a new capture then succeeded. |

After the review fixes, the native suite passes 40 tests with no failures or skips;
the Flutter suite passes 16 tests. The device observations above record one smoke run.

### Review regressions covered

- Utility actions recheck the foreground root when their settling delay ends.
  A stale target event cannot send Back or a swipe to a different app; the request
  keeps waiting within its original timeout.
- Capture excludes MobilePilot even if the package predicate accepts it. Results
  arriving after the foreground package changes are discarded.
- Flutter starts its capture deadline when arming succeeds. At 30 seconds it
  retrieves an already completed image, or clears the wait and permits retry.
  Channel reads/cancellation are bounded, overlapping polls are avoided, and late
  responses cannot update a newer local request.
- Controller tests cover deadline/disposal without app lifecycle events, as well
  as delayed responses and retry during cancellation.

On the connected PTP N49, remaining in MobilePilot for 31 seconds after arming
showed the timeout message and re-enabled capture without leaving the app. A new
request then captured Settings successfully.
