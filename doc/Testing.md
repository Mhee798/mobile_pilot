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

After the review fixes, the native suite passes 137 tests with no failures or skips;
the Flutter suite passes 59 tests. The device observations above record one smoke run.

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

### Explicit target-app regression coverage

- Foreground readiness requires a matching root for 500 ms, resets on a different
  app, times out after 10 seconds, and cancels when the target changes or Stop is used.
- Targeted tree reads/text taps/gesture taps reject a root from another package.
- Targeted capture ignores other apps and supports an already foreground target.
- Utility actions can dispatch to an already foreground target without a new
  window event. Text entry preserves its declared target rather than the recent app.
- Flutter forwards the selected target, preserves selection across app searches,
  handles launch timeout, discards old tree results and blocks actions from an old image.

Manual target-app workflow: search for an installed app, select it, arm capture or
read the target tree, then press **Open target app**. Return to inspect the result.
For a point/text/swipe command, queue it and use **Open target app** separately.
Opening an app is never a side effect of a control command.

The target-app build was installed on the connected PTP N49 on 2026-10-26.
Accessibility was disabled on that device at this check, so the new target-app
workflow has not yet been verified on the phone. Enable MobilePilot Accessibility
manually before running the workflow above; previous smoke observations do not
count as verification of this new workflow.

### App-switch point-tap fix (2026-10-26)

Early target-window events followed by an outgoing MobilePilot event could cancel
queued work before the actual foreground root changed. Point/utility queues now
sample the foreground root every 100 ms, require 1.5 seconds of continuous target
presence and retain the original 60-second expiry. Repeated or missing events do
not prevent dispatch. Switching away resets the settling interval; queued work
is cancelled explicitly via **Cancel pending commands** or floating Stop.

Three additional native regressions cover early target/Pilot event ordering,
missing follow-up events and interrupted foreground settling. Existing event
checks now assert actual foreground state rather than trusting event packages.
Flutter also covers the new cancellation channel.

On the connected phone with Accessibility enabled, a fresh Settings screenshot
was selected at normalized (0.500, 0.909). Queuing a point tap and switching to
Settings opened **About phone**, confirmed visually on the device. This verified
coordinate dispatch with screenshot metadata in manual mode; it did not test
posting, purchases or other apps. Screenshot evidence is local build output:
`build/mobilepilot-point-result.png`.

### Wait-for-UI coverage

Native tests cover exact visible text, descriptions, case-sensitive resource IDs,
wrong-app and hidden/partial matches, delayed elements without window events,
root changes during traversal, cancellation, timeout/retry, concurrent waits,
stale cancellation IDs and input validation. Visited child nodes are recycled.

Flutter tests cover typed arguments, explicit target validation, terminal results,
request-scoped cancellation, disposal, stale results after target changes, bounded
missing channel responses and independent status display. Native waits survive
normal app switching; they do not need a Flutter resume callback to complete.

Manual workflow: select an installed app, expand **Wait for screen element**,
choose the selector/value and deadline, press **Start waiting for UI**, then use
**Open target app**. Return to see found/timeout/cancelled status. The wait itself
must not launch the target app or tap anything.

On PTP N49 (2026-10-26), selected Chrome and waited for
`com.android.chrome:id/toolbar_action_button` using the resource-ID selector.
After explicitly opening Chrome, the UI reported found. Staying in MobilePilot
for a 5-second wait reported timeout, and cancelling a new request before its
deadline reported cancelled. All three were confirmed visually. Enabling
`flagReportViewIds` was necessary for native resource IDs to be available.
Evidence is in local build output: `mobilepilot-wait-found.png`,
`mobilepilot-wait-timeout.png` and `mobilepilot-wait-cancel.png`.

### Screen/node reference coverage

Native regression tests cover single-use references, old screen IDs, unknown node
IDs, changed text/bounds, wrong packages, disabled controls, invalidation and two
identically labelled controls resolved by distinct node paths. A Settings test
also verifies that changed reference IDs alone cannot count as a UI change.
Flutter tests cover exact argument forwarding, stale-list clearing and target
mismatch blocking.

Manual workflow: select an app, read its UI tree while explicitly opening it,
then return to MobilePilot. Use the action icon at the end of a clickable row and
open the target within 10 seconds. If the accessible tree changed, read it again.
Do not use UIAutomator dumps between reading a snapshot and acting on it; the
known device harness interruption can restart the service and invalidate IDs.

A device smoke run on PTP N49 read Chrome's tab overview, returned to MobilePilot,
and pressed the reference action icon for `com.android.chrome:id/menu_button`.
After explicitly reopening Chrome, its tab-management menu opened, confirming a
real exact-node click. No tabs were closed or submitted. Screenshot evidence is
local build output `build/mobilepilot-node-result.png`. Checked/selected-state
changes are additionally covered by native stale-reference regression testing.

### Deterministic sequence test coverage

Native tests cover package-bound sessions, concurrent-session rejection, Stop,
old-session cleanup, exactly-once lease expiry, manual tool exclusion and a
foreground-ready callback arriving after Stop (must not click).

Flutter tests cover all five steps, run-ID propagation, ambiguous buttons,
already-present result rejection, wait failure, stale-reference no-retry,
Stop during a delayed read, floating Stop and late results from an older run.

Manual Chrome example (Resource ID selector): before/button =
`com.android.chrome:id/menu_button`; new result =
`com.android.chrome:id/new_tab_menu_id`. Start from Chrome's tab overview with
its menu closed. The runner should explicitly open Chrome, open its menu once,
and report success after finding the new-tab menu entry; it must not activate
that entry. Close the menu before repeating the test.

On the connected PTP N49, one press of **Start sequence test** opened Chrome,
waited for its menu button, read a fresh snapshot, clicked that menu button once,
and found `new_tab_menu_id`. Returning to MobilePilot showed all five steps and
success. No intermediate control button was pressed. Local screenshot evidence:
`build/mobilepilot-sequence-chrome.png` and `build/mobilepilot-sequence-result.png`.
The demonstration opens the menu only; it does not create or close a tab.

### Long-press coverage

Native tests check exact stroke duration, invalid-duration rejection, stale display
rejection, target waiting, queued cancellation, in-flight exclusion, callback
timeout and isolation from a late callback belonging to an older gesture.
Flutter checks coordinate/display/duration forwarding, target mismatch and missing
point rejection. Existing 100 ms tap tests continue to pass.

On PTP N49, a 1000 ms long press at normalized (0.809, 0.086) on Chrome's tab
switcher opened its tab context menu, confirmed visually. No menu item was chosen.
Evidence: `build/mobilepilot-long-press-result.png`. A warm-up capture included an
app-switch animation; a fresh capture was taken before choosing the test point.
Capture readiness remains package-based rather than visual-content stabilization.

Manual workflow: capture the target, select a point, choose duration, press
**Prepare long press at this point**, then open the target and wait for foreground
settling plus the chosen press duration. **Cancel pending commands** cancels only
work not yet dispatched to Android.

### Custom coordinate swipe coverage

Native tests inspect scaled line geometry and stroke duration, reject invalid or
identical endpoints and invalid timing, reject display rotation changes, preserve
endpoints while waiting for the target, cancel queued swipes, and confirm a 100 ms
swipe never dispatches via the tap path. The path test uses bounds because the
legacy Robolectric PathMeasure does not populate getPosTan coordinates.

Flutter tests cover argument forwarding, independent endpoint selection, clearing
both points on target change, missing/identical endpoints and wrong-app images.

Manual workflow: capture an app, choose **Start point** and tap the image, choose
**End point** and tap again, select duration, queue the custom swipe, then reopen
the target. The red pin is the start and the blue flag is the end. Observe the
actual app response; a completed Android gesture does not itself verify scrolling.

On the connected PTP N49, the two-point controls selected start (0.750, 0.302)
and end (0.750, 0.802), duration 400 ms, from a Settings screenshot. Queuing the
swipe and explicitly reopening Settings scrolled its list from the lower settings
section to the top section, confirmed visually. No setting was changed. Evidence:
`build/mobilepilot-custom-swipe-before.png` and `build/mobilepilot-custom-swipe-result.png`.

### Two-finger zoom coverage

Geometry tests cover expansion, contraction, shorter-side normalization, vertical
axis and rejection of invalid or out-of-bounds starts/ends without clamping.
Native dispatch tests verify two strokes with equal durations and simultaneous
starts, their path bounds, stale displays and Android rejection. Queue tests cover
target waiting, cancellation and invalid input; a 100 ms pinch cannot use the tap
path. Existing shared in-flight/timeout isolation tests still apply.

Flutter tests cover center/display/span/scale/axis/duration forwarding, error
messages, wrong-app captures, missing center and selecting the red center point.

Manual workflow: capture an app that supports pinch zoom, place the red pin near
the center of its content, expand **Two-finger enlarge/shrink**, choose parameters,
queue the gesture and explicitly reopen the target. A completed gesture is not
an assertion that the target app supports zoom or reached a verified scale.

On PTP N49, Android completed both expansion and contraction gestures. The native
Chrome PDF viewer did not provide a clear contraction result, so a local,
zoom-enabled browser fixture with `visualViewport.scale` reporting was used for
verification. The reported scale changed from 1.00 to 1.70 after outward strokes,
then to 1.38 after inward strokes (500 ms, 25% starting span, horizontal axis,
center approximately (0.500, 0.502)). These are measured browser effects, not an
assertion that gesture scale 2 or 0.5 produces those exact content multipliers.
Evidence: `build/mobilepilot-pinch-scale-up.png` and
`build/mobilepilot-pinch-scale-down.png`; the local fixture is in
`build/pinch-fixture/index.html`. The temporary local server/USB port forwarding
were stopped after the test.

### Strong pinch correction — 2026-10-27

The original 25% span / scale 0.5 contraction moved each finger only 6.25% of the
short display side. Added explicit strong profiles: expand 20%→80% and shrink
80%→20%, both over 1000 ms. Advanced controls retain weaker settings. Presets
update visible form values and payloads together; they do not queue automatically.
Native tests verify reversed geometry and 384 px travel per finger on a 1280 px
short side. A Flutter widget test verifies that the shrink preset displays and
sends scale 0.25, span 0.8 and duration 1000.

On PTP N49, the zoom-enabled local fixture changed from scale 1.00 to 3.28 with
strong expansion and back to 1.00 with strong contraction. The previous profile
had produced only 1.70 and 1.38 in that fixture. Strong expansion also visibly
enlarged the actual Chrome document, and strong contraction restored its full-page
view. This confirms visible effects, without claiming exact content multipliers.
Evidence: `build/mobilepilot-strong-pinch-up.png`,
`build/mobilepilot-strong-pinch-down.png`, `build/mobilepilot-strong-pdf-expand.png`
and `build/mobilepilot-strong-pdf-shrink.png`. The temporary fixture server and
USB forwarding were removed after testing; the original document was left open.


### Home / Recents navigation (2026-10-27)

- Added immediate Home and Recents buttons to the command test page and floating controls.
- Uses Accessibility global actions; no target package, screenshot, or launcher-name assumption is required.
- Navigation cancels waiting commands and the active command session first. Already dispatched gestures may still finish.
- Reports Android acceptance/rejection separately from actual screen verification.
- Verified on the connected HONOR: Home opened the launcher and Recents displayed the task cards. Native suite: 137 tests; Flutter suite: 59 tests; analysis and debug build passed.


### Bounded scroll until UI match (2026-10-27)

- The wait-for-UI test section now has an opt-in scroll mode: exact text/content-description/resource-ID selector, up/down direction, 1–40 accepted scroll actions, and a 1–60 second deadline.
- Start in MobilePilot, then open the selected target app explicitly. The target must remain foreground for 1 second before the first scroll; leaving it afterwards stops the request.
- Searches visible nodes before scrolling and after each step; returns matched metadata and scrollCount without clicking. Inspects at most 500 nodes / depth 30.
- Uses the first visible accessibility scroll container in tree order and ACTION_SCROLL_FORWARD/BACKWARD, with 1 second between accepted actions. Multiple panes are not automatically disambiguated; apps without exposed UI/scroll containers return an explicit unsupported/rejected result. No gesture fallback is implied.
- Stops on match, action rejection/no container, count limit, deadline, cancellation, target change, Home/Recents, page disposal, or service destruction. Stop cannot undo an already dispatched scroll.
- Conflicting manual actions are rejected during the search; explicit app launch remains available to bring the target forward. Existing queued gestures/capture/settings tests must finish or be cancelled first.
- Automated coverage: native 137 tests, Flutter 59 tests; analysis and debug build passed.

- Scroll lookup additionally requires a nonempty node rectangle intersecting the root viewport and enclosing scroll containers. This prevents Chrome offscreen DOM nodes marked visible from prematurely completing the search.

- Device verification (HONOR, Chrome local fixture): a target initially below the viewport was found after 5 accepted scrolls on the final run; screenshot confirmed the target on screen. An earlier run returned to MobilePilot mid-search and correctly stopped with SCROLL_TARGET_CHANGED after 7 scrolls. Chrome offscreen-visible regression is covered by a native test.


### Adjustable search swipe distance (2026-10-27)

- Added `distance` to scrollUntilUi: `long` (80% visible scroll-container height, UI default), `short` (40%), and `app` (original accessibility scroll action). Older native callers without the field retain `app` behavior.
- Gesture modes use a 600 ms swipe inside the first visible scroll container clipped to the root viewport, with overlay touch interception disabled during dispatch. Finger travel is configurable; actual content displacement remains app-dependent.
- The next search waits for gesture completion; cancellation/rejection is surfaced, overlap is prevented, and all original count/time/foreground limits remain. Long swipes retain 20% overlap, but app animation/inertia can still affect coverage.
- The timeout includes the time spent switching apps: use 30 or 60 seconds for longer searches. UI selection never automatically extends the user's chosen deadline.
- Verified analysis, debug build, native 137 tests and Flutter 59 tests.

- Connected HONOR verification: default long mode found MobilePilotTarget from the top of the Chrome fixture after 4 swipes; screenshot confirmed the target on screen. Updated APK installed.


### Wait for previously seen UI to disappear (2026-10-27)

- `waitForUi` accepts `condition: present | disappeared`, default `present` for existing callers and deterministic sequences.
- Disappearance requires observing the visible exact match in the selected foreground app first, followed by at least 500 ms of consecutive complete negative scans. Never-seen selectors time out; this is not an immediate absence assertion.
- A different app, missing root, unreadable children, or bounded traversal truncation resets/blocks absence confirmation. Reappearance resets the 500 ms timer. The original deadline and cancellation/disposal behavior still apply.
- UI exposes the condition selector; scroll mode explicitly uses presence only. This tool never clicks or launches an app. A vanished loading label is evidence of UI disappearance, not proof of loading/transaction success.
- Analysis, debug build, native 137 tests and Flutter 59 tests passed.

- Device verification on connected HONOR / Chrome: observed Loading, removed it via the fixture button, then received UI_DISAPPEARED; screenshot confirmed Loading gone and Done displayed. Empty root bounds are also rejected as absence evidence (regression test).


### Additional tool device suite

`integration_test/device_tools_test.dart` tests actual DOM effects through the Android accessibility/gesture tools. `integration_test/fixtures/index.html` is a dedicated test page; it must be opened fresh on every run (a different query string is enough). The setup checks the fixture marker before allowing the tests to run.

1. Serve `integration_test/fixtures` from the repository root with `python -m http.server 8768 --bind 127.0.0.1 --directory integration_test/fixtures`.
2. Connect and unlock the Android phone, enable MobilePilot Accessibility, and run `adb reverse tcp:8768 tcp:8768`.
3. Open `http://127.0.0.1:8768/index.html?run=NEW_ID` in Chrome.
4. Run `flutter test integration_test/device_tools_test.dart -d DEVICE_SERIAL`. Reinstalling the test APK may disable Accessibility on the HONOR: re-enable it while setup is waiting (up to 60 seconds). Keep the screen unlocked.
5. Stop the local server, remove `adb reverse`, and rebuild/install the regular `lib/main.dart` application after testing. The integration APK is a test harness, not the normal app UI.

Do not run Flutter device builds and standalone Gradle builds concurrently: on Windows they can contend for the same intermediate files. Never use a UIAutomator dump while a queued action or snapshot reference is in use; the dump may restart Accessibility.

Final combined device run passed all five tests: double tap; hold-then-drag; exact field focus/replace/clear; Search, Next/Tab and Enter; enabled-button and stable text-change waits. Earlier fixture/setup failures and a locked-screen attempt were resolved before this final run.


### Latest verification — 2026-10-27

- `flutter analyze`: no issues.
- Native unit/controller tests: 158, zero failures/errors.
- Flutter unit/widget tests: 63 passed.
- Connected HONOR integration tests: 5 passed in the final combined run; each checks an actual fixture UI effect. Enabled wait was tested against a disabled button enabled later; text-change wait used the fixture's `inputtarget` resource ID and an actual field replacement.
- Regular app debug build is restored after integration testing; the integration entrypoint is not left installed for normal use.
- The phone's original `stay_on_while_plugged_in` value was 0; USB stay-awake was used temporarily during testing and is restored at the end.
- Keyboard named actions use the official accessibility input-method APIs: https://developer.android.com/reference/android/accessibilityservice/InputMethod.AccessibilityInputConnection . These calls dispatch asynchronously; always verify the expected application result separately. The UI labels Next as Next/Tab and does not silently substitute it for Search or Enter.


### Refactor and review verification — 2026-10-27

After the tool simplification, the native suite passed 165 tests, Flutter passed 63 tests, `flutter analyze` reported no issues, and the regular Android debug build succeeded. A review identified and prompted fixes for stopping a drag during its hold (including stale callbacks after timeout/disposal), clipping offscreen nodes in presence waits, checking foreground again before the default keyboard action, and recognizing a label inside an enabled clickable ancestor. Regression tests cover these scenarios. The five-device integration run recorded above predates these changes; it was not repeated after this review.
