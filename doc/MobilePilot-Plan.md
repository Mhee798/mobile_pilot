# MobilePilot --- AI Mobile Use for Android

> Latest update (2026-10-30, Bangkok): Gemini Cloud through Firebase AI Logic
> now has a separate test chat, the existing device tools, app-choice UI,
> diagnostic history/export and Live Updates. Real-device examples include
> opening Settings/Wi-Fi and searching Shopee with newly entered text. These
> examples do not establish broad reliability. The system-settings shortcut
> and revised screenshot point validation have passed automated checks but
> still need real-device verification. Next: repeatable device tests and a
> saved, deterministic tool workflow; see the current status below.

> AI device-test update (2026-10-28): Thai and English requests can open Settings
> and tap into Wi-Fi using exact, unique UI labels. End-to-end completion is
> still inconsistent: goal-evidence selection can be missing/ambiguous, so the
> controller stops instead of claiming success. One Thai run verified the
> destination; later runs still failed verification. Latest Flutter suite:
> 148 tests passed; analysis/debug build passed. See `Testing.md` for evidence.
> This is a historical result; current priorities are listed below.

> Run-history update (2026-10-28): Added private, expandable diagnostic history
> with tool arguments/results, timing, model identity, stop reason and clearing.
> Refactored task-state and result presentation; reviewed and tested (157 Flutter,
> 168 Android app tests, analysis/build passed). Phone smoke test confirmed a
> real app-search step was persisted and displayed. Goal verification remains
> inconsistent and has not been disabled by this change.

## 1. Project Overview

MobilePilot is an Android AI agent app that lets users give
natural-language instructions and have an AI interact with apps on the
same Android device.

The product should support two modes:

-   **Background Agent:** the user submits a task, minimizes
    MobilePilot, and the task continues when Android allows it.
-   **Live Control:** the user can observe the AI's progress and the
    latest available screen view while the AI operates the device.

Both modes should use the same Agent Orchestrator and Hybrid Control
Engine.

> Important: minimizing an app does not guarantee that accessibility
> actions or screen capture will continue in every Android state. Device
> behavior, permissions, OS version, and app restrictions must be tested
> on real devices.

## Current Implementation Status — 2026-10-30 (Bangkok)

The project has manual controls, an on-device Gemma/LiteRT-LM chat and a
separate Gemini Cloud test chat via Firebase AI Logic. The cloud chat uses a
separate tool loop, not yet the same orchestrator as local inference. Users have
confirmed several multi-step cloud tasks; device compatibility, background
execution and reliable end-to-end completion still require more testing. The
configured Firebase files are local and ignored by Git; a fresh checkout needs
its own Firebase configuration.

| Area | Status | Evidence / limit |
| --- | --- | --- |
| Accessibility onboarding and service status | Done | Opens Android Accessibility settings, checks status on return, and opens the command screen when enabled. |
| UI tree and element actions | Done, basic | Exports screenId/nodeId references and supports exact-node click after validating the current bounded tree against its snapshot. Text tap/gesture fallback remains available. References are single-use for exact-node click. |
| App search, target selection and launch | Implemented, basic | Stores the selected app label/package for this command page. Launch is explicit and confirms a matching foreground root stable for 500 ms, with a 10-second deadline. |
| Screenshot and coordinate control | Done, basic | Captures another app, previews it, selects a point, and queues tap, scroll, horizontal swipe, Back, or text entry. Capture is event-driven and device behavior still needs broader testing. |
| Wait for UI conditions | Implemented and device-tested | Exact presence, previously seen disappearance, enabled/clickable buttons, and text changes using a unique stable locator. Bounded polling, cancellation and selected-app checks; no automatic tap. |
| Two-finger zoom | Implemented and device-tested | Sends simultaneous symmetric finger strokes around a captured center; configurable separation, span ratio, axis and duration, with strict screen-bound checks. |
| Custom coordinate swipe | Implemented and device-tested | Selects normalized start/end points and 100–3000 ms duration; supports vertical, horizontal and diagonal straight-line swipes using the shared captured-screen queue. |
| Coordinate long press | Implemented and device-tested | Queues a stationary 500–3000 ms gesture using captured app/display metadata; shares target settling, cancellation and expiry with point taps. |
| Focused text entry | Verified on device | On 2026-10-26, `MP_SAFE_TEST_42` was inserted into Chrome's focused address field on a PTP N49. It was not submitted. Password fields are blocked. |
| Floating controls | Implemented, basic | Accessibility service can show a draggable bubble and action panel, including cancel. Overlay behavior needs more device/app testing. |
| Deterministic command sequence | Implemented, basic | Explicitly launches one selected app, waits, reads a fresh tree, clicks one unique node and waits for a new result. Stops on failure, cancellation or stale references; no AI or persistent recovery. |
| Local AI chat, tools and Vision | Prototype connected | Gemma model selection/download; 8K, 12K and 16K context settings and an experimental longer-context policy. Task context can be summarized and rotated; the runtime may also trim it. Local multi-step reliability remains inconsistent. |
| Gemini Nano | Experimental; foreground only | AICore through ML Kit blocks inference when MobilePilot is not the top foreground app, including with a foreground service. The user observed `LocalAiGenerationException(30)` during a test. Continuous control after opening another app is therefore not supported by this integration; an overlay alone does not make MobilePilot the top app. Split-screen behavior is unverified. Add a clear in-app warning and handle this error explicitly. See [ML Kit GenAI background usage](https://developers.google.com/ml-kit/genai#background-usage). |
| Gemini Cloud chat and tools | Prototype connected | Firebase AI Logic chat, app-choice continuation and typed tools, including separately opted-in screenshot delivery. On-device tests demonstrated Settings/Wi-Fi, YouTube and a new Shopee search, not all tools or app states. The current cloud loop has a 12-round bound. |
| System settings shortcuts | Implemented; device verification pending | `open_system_settings` supports common Android settings pages including Cast and selected app details. A launch must confirm the foreground package; unsupported or unconfirmed destinations are reported. |
| Additional Android tools | Prototype; device verification pending | Read device/battery/storage data, read/set media volume, dispatch media keys, open user-supplied HTTP(S) links, map searches and alarm UI. Gemini can read a user-selected small UTF-8 text file; custom-scheme deep links, file editing and creation are not yet supported. Intent dispatch does not prove task completion. |
| Screen-change handling | Implemented; device verification pending | For point actions, the revised image check compares the area around the point and relevant UI nodes; changed target content is rejected. Gemini stops after repeated screen-change failures. Animated-banner behavior needs a repeatable real-device fixture. |
| Diagnostic history and export | Implemented | Retains recent requests, model labels, tool arguments/results, timing and status; supports JSON export. History is diagnostic, may be truncated, can contain private UI data, and is not a replay queue. |
| Live Updates and task lifecycle | Partial | Local and cloud test chats publish progress and Stop through the shared overlay/notification. Presentation depends on OS, device and notification permission; background execution and process-death recovery are not guaranteed. A model response or dispatched action alone does not prove task completion. |
| Saved tool workflows | Planned | No saved workflow editor or persistent replay runner yet. The existing deterministic command sequence and AI diagnostic history do not provide this feature. |

Recent scoped Flutter tests, Android shortcut unit tests, analysis and debug
build passed; the settings-shortcut build was installed on the phone. The last
real-device result for the new shortcut was not verified in this session.
Automated image-change tests passed; actual animated-banner behavior remains
unverified. These checks do not prove broad app compatibility.

Historical result: after the controller refactor, a PTP N49 smoke run on 2026-10-26 verified app
launch, UI-tree reading, capture/point tap, floating gestures, focused text entry,
cancellation and capture expiry/retry. A point-tap window-event cancellation bug
found during that run was fixed and covered by two regression tests. The native
suite now passes 158 tests and the Flutter suite passes 63; see
[Testing](Testing.md) for commands, device observations and harness limitations.

### Explicit target-app controls

- Selecting a launcher result establishes the target without opening it. It cancels
  previous pending native work and invalidates the old screenshot/tree in the UI.
- The separate **Open target app** button launches the selected package and waits
  for foreground confirmation. This confirms window presence, not completion of
  the app's network requests or loading screens.
- UI-tree reads and text taps carry `targetPackage`, wait at most 10 seconds, and
  reject a mismatched root. Screenshot requests carry the selected package, wait
  up to 30 seconds, and can capture an already foreground target without a new
  window event.
- Point, swipe, Back and focused text actions remain tied to captured app metadata.
  A screenshot from another selected target is rejected. Queued actions wait up
  to 60 seconds and do not launch apps; text never substitutes the most recent app.
  Pending actions sample the active root every 100 ms and dispatch only after the
  target package remains foreground for 1.5 seconds. Window events cannot cancel
  or indefinitely postpone them. Returning to MobilePilot pauses the wait rather
  than cancelling it; use **Cancel pending commands**, Stop, or wait for expiry.
- With no selection, existing local-screen/manual test controls remain available.
  Selection is held for this command page only; it is not persistent task state.
- `wait_for_ui` supports presence, enabled, disappearance and text changes.
  AI tools now include UI actions, capture/gestures, scroll search and navigation;
  see [AI tool guide](AI-Tool-Guide.md) for schemas and limits.

### Planned: saved tool workflows / shortcuts

**Goal:** a user can review and save a sequence of MobilePilot tool operations,
then tap a named shortcut to run that sequence later without asking an AI to
plan it again. This is a structured, deterministic workflow, not arbitrary
Python, JavaScript, shell code or executable code downloaded from elsewhere.
Nothing in this section is implemented yet.

Example: **Open Wi-Fi and read status**

1. Open the Android Wi-Fi settings destination.
2. Wait until the expected target is available.
3. Read the current UI and show the observed result.

The example opens and reads a page; it does not toggle Wi-Fi. Actual available
UI and direct settings destinations vary by device.

**Creation and management**

- [ ] Define a versioned workflow record: name, ordered typed steps, arguments,
  expected outcomes and optional input parameters. Store it separately from
  the existing diagnostic history in private app storage.
- [ ] Allow AI to propose a workflow from a completed task or a user request;
  show the proposed steps and arguments for review, editing and explicit save.
  A diagnostic trace is evidence for a proposal, not an executable replay.
- [ ] Provide a list with create/edit, rename, delete and run controls. Decide
  how parameters such as a search term are supplied before each run; never
  infer missing values from an old task.
- [ ] Specify version migration, malformed-record handling and limits on saved
  workflows and steps. Failed or interrupted runs must not silently resume.

**Runner and correctness**

- [ ] Build an app-owned runner that executes allowed, typed tools sequentially,
  waits for each result and shows progress, Stop, the failed step and reason.
  Keep this separate from the AI planner and reuse existing tool validation,
  cancellation and target-app/foreground checks.
- [ ] Resolve targets again on each run: do not persist or replay old UI refs,
  native node IDs, screenshot IDs or raw coordinates as proof of a target.
  Prefer a fresh UI read and a sufficiently specific selector; verify that the
  match is unique and usable. If no safe match exists, stop and ask the user.
  Vision-based steps require a new capture and target decision each run; a
  deterministic first version may explicitly mark these steps unsupported.
- [ ] Treat dispatched actions as dispatched, not proof of the desired outcome.
  Re-read or check a step-specific observable condition where appropriate;
  distinguish success, unverified, failed, cancelled and interrupted states.
- [ ] Preserve existing user control for consequential actions and disclose
  when a workflow uses screenshots or cloud inference. Replaying a saved
  workflow does not imply approval of a changed or ambiguous target.
- [ ] Save each run to diagnostic history with workflow identity, step results
  and reason for stopping; retain existing export and avoid saving images by
  default. Workflow storage and execution history have different lifetimes.

**Delivery and checks**

1. [ ] Implement typed workflow records, persistence and validation; test
   round-trip, invalid versions and unsupported steps.
2. [ ] Add a runner and test success, ambiguous/missing target, wrong app,
   tool failure, cancellation and interruption without replaying stale refs.
3. [ ] Add creation from a reviewed task proposal and a minimal management UI;
   test editing, explicit saving and running again after reopening the app.
4. [ ] Test on a real phone with a harmless Wi-Fi settings/read workflow, then
   repeat under changed layouts and missing targets. Verify that a saved
   workflow runs without an AI request when all its steps are deterministic.

### Near-term priorities

1. Test the settings shortcut on the connected phone, including unsupported
   destinations, foreground confirmation and a subsequent UI read. Expand
   version-specific or parameterized destinations only with their required inputs.
2. Make a deterministic screen-change fixture: an animated region outside the
   target, a changed target, a changed page and ambiguous/missing UI targets.
   Validate image-point safety and retry stopping on a real device.
3. Test remaining Gemini-connected actions on device, including typing, wait,
   scroll and gestures, and distinguish model responses from verified outcomes.
4. Implement the reviewed, saved workflow feature above; do not build a generic
   code execution runtime as part of this scope.

See [Model testing results](Model-Testing-Results.md) for observed Gemma and
Gemini behavior and [AI tool guide](AI-Tool-Guide.md) for the tool catalog.

## 2. Product Experience

### 2.1 Chat Mode --- Control Center

The main MobilePilot screen provides:

-   Natural-language chat
-   Task plans and progress
-   A visible Stop/Cancel control
-   Results and task history
-   Permission setup and troubleshooting

Example prompt:

> Open Settings and tell me the Android version on this device.

### 2.2 Live Control --- Observe the AI

The user can inspect the latest screen view and follow each action.

-   Show the latest screen capture available to the app
-   Show the current action and verification status
-   Show whether UI-tree matching or Vision fallback was used
-   Provide an immediately accessible Stop control

The current prototype has a manual in-app screenshot preview and a basic
floating bubble/action panel. The preview is a single capture, not a live
stream. The floating panel now displays AI status and has a task Stop button.
Keep the in-app view as the primary observation surface while hardening the
floating controls.

### 2.3 Background Agent --- Continue After Minimizing

The user can submit a task and leave the chat screen.

-   Show ongoing task status in a notification where supported
-   Allow the user to return to the app for results or approvals
-   Recover saved task metadata after reopening the app
-   Clearly report if the task paused or stopped because Android denied
    access or stopped a service

Background execution must not be presented as guaranteed. Screen
capture, device interaction, and service lifecycle behavior depend on
Android restrictions and the permissions granted.

## 3. Architecture

``` text
MobilePilot Flutter App
  ├── Chat
  ├── Live View
  ├── Task History
  └── Stop / Approval UI
          |
          v
Agent Orchestrator
  ├── Task planning
  ├── Tool calling
  ├── Action lifecycle
  ├── Verification loop
  └── Approval policy
          |
          v
Hybrid Control Engine
  ├── Accessibility UI Tree (primary)
  └── AI Vision + normalized coordinates (fallback)
          |
          v
Android Runtime
  ├── AccessibilityService
  ├── UI Tree Reader
  ├── Gesture Controller
  ├── Screenshot Controller
  └── Task / Notification handling
          |
          v
Other Android Apps
```

### Recommended stack

  -----------------------------------------------------------------------
  Area                    Technology              Responsibility
  ----------------------- ----------------------- -----------------------
  Main app                Flutter + BLoC/Cubit    Chat, task status,
                                                  history, settings

  Android integration     Kotlin + Android SDK    Accessibility and
                                                  Android-specific
                                                  actions

  UI understanding        AccessibilityNodeInfo   Read accessible UI
                                                  structure and perform
                                                  supported actions

  Visual understanding    AI Vision API           Interpret screenshots
                                                  when the UI tree is
                                                  insufficient

  Agent                   Tool/function calling   Select tools and
                                                  sequence actions

  Flutter--native bridge  Platform Channels       Connect Flutter and
                                                  Kotlin

  Optional backend        TypeScript              AI API proxy, task
                                                  coordination, and later
                                                  MCP integration

  Later external          MCP Server / API        Allow external agents
  integration             Gateway                 to request device
                                                  actions securely
  -----------------------------------------------------------------------

For the first MVP, keep the agent flow as simple as possible. Add an
external MCP server after the on-device control loop is reliable.

## 4. Hybrid Control Strategy

The engine should prefer structured UI information and use visual
coordinates only when necessary.

### 4.1 Decision flow

1.  Receive a target from the agent, such as "tap Battery."
2.  Read the current Accessibility UI tree.
3.  Match the target using text, content description, resource ID, and
    available actions.
4.  If a unique, actionable target is found, act through the UI node.
5.  If the target cannot be found or the node action fails, obtain a
    permitted screenshot.
6.  Ask the Vision model to identify the target and return normalized
    coordinates.
7.  Validate the target and coordinate bounds before performing a
    gesture.
8.  Read the UI tree or capture a new screenshot after the action.
9.  Verify the expected state change.
10. If verification fails, retry safely, ask for clarification, or stop.
    Never repeatedly tap blindly.

### 4.2 UI-tree matching rules

Prefer targets in this order:

1.  Stable resource ID, when available
2.  Exact text or content description
3.  A unique semantic match in the current screen
4.  Vision fallback when structured matching is insufficient

Every node reference should be associated with a screen
snapshot/version. If the screen changes, discard stale node references
and read the UI tree again.

### 4.3 Vision fallback

Vision should return structured data, for example:

``` json
{
  "target": "Battery menu",
  "x": 0.52,
  "y": 0.41,
  "confidence": 0.94
}
```

Coordinates are normalized from `0.0` to `1.0` relative to the image
dimensions. Convert them to device coordinates only after accounting for
image scaling, system bars, display rotation, and any cropping.

The model's confidence is an estimate, not proof of correctness.
Validate the target and verify the resulting screen state.

### 4.4 Example workflow

User prompt: "Open Settings and tell me the Android version."

1.  The agent interprets the request and chooses an allowed action
    sequence.
2.  It opens Settings using an appropriate supported route.
3.  The engine reads the UI tree and looks for the relevant
    device-information menu.
4.  It uses a UI-node action when a suitable target is found.
5.  If the target is missing or not actionable, it uses Vision fallback.
6.  It re-reads the current screen and confirms that the expected page
    opened.
7.  It finds and reads the Android version.
8.  It returns the result with a concise summary of actions performed.

## 5. Device Tools

Start with a small, typed set of tools.

  -----------------------------------------------------------------------
  Tool                                Purpose
  ----------------------------------- -----------------------------------
  `get_ui_tree`                       Read the accessible UI structure of
                                      the current window

  `get_screen`                        Obtain a screenshot through an
                                      available, permitted capture
                                      mechanism

  `find_apps`                         Search launcher-visible apps by
                                      display name and return matching
                                      candidates for disambiguation

  `launch_app`                        Launch a candidate returned by
                                      `find_apps`; do not guess an
                                      unknown package name

  `tap_element`                       Tap a UI element identified by
                                      text, resource ID, or a current
                                      node reference

  `tap_point`                         Perform a coordinate-based gesture
                                      when structured targeting is
                                      insufficient

  `swipe`                             Swipe between points

  `type_text`                         Enter text into a supported focused
                                      input

  `press_back`                        Invoke the supported Back action

  `wait_for_ui`                       Wait for a specified UI condition
                                      or timeout

  `stop_task`                         Cancel pending work and stop
                                      further actions where possible
  -----------------------------------------------------------------------

Keep tool schemas explicit and validate every argument. Do not allow
arbitrary shell commands or unrestricted code execution from the model.

### Two-finger zoom

`queuePinch` accepts normalized center `x`/`y`, captured display/package metadata,
`durationMs` (100–3000), `startSpan` (0.05–0.8 of the shorter display side), `scale`
(0.25–4, excluding 1) and `axis` (`horizontal` or `vertical`). `scale` means final
finger separation divided by initial separation; the app's actual zoom response
must be observed independently.

The geometry uses pixels based on the shorter display side, so portrait/landscape
aspect ratio does not distort finger separation. Both strokes start at time zero
and have the same duration. All four start/end points must remain inside the
screen; invalid geometry is rejected without clamping or moving the center.

The red preview pin is the center. The test controls offer enlarge/shrink presets,
15/20/25/35/50/70/80% starting separation, horizontal/vertical axes and gesture duration. The
shared captured-screen queue provides target settling, cancellation before dispatch,
expiry, in-flight exclusion and callback timeout/late-result isolation. It does
not launch apps or claim that successful dispatch proves a particular zoom level.

Strong presets are available to avoid the small motion of the original defaults:
**Strong expand** uses 20% initial separation and scale 4 (ending at 80%);
**Strong shrink** uses 80% initial separation and scale 0.25 (ending at 20%).
Both use 1000 ms. The preset buttons configure the fields; the user still queues
the gesture explicitly. The default is the strong expansion profile. Boundary
validation is unchanged and the center is never silently moved.

### Custom coordinate swipe

`queueSwipe` uses `x`/`y` as the start point and `endX`/`endY` as the end point,
plus captured `width`, `height`, `rotation`, `packageName` and integer `durationMs`
(100–3000). Coordinates must be finite, normalized to 0–1 and distinct. A 100 ms
swipe remains a line gesture, not a tap.

The preview can select either the red start pin or the blue end flag and draws
its line. Start/end selection does not overwrite the other point. Fresh captures
and target changes clear both. Tap/long press continue to use the red start pin.

The tool shares target settling, 60-second queue expiry, cancellation, in-flight
exclusion and completion timeout with coordinate taps/long presses. It validates
the captured display before dispatch and does not automatically open the app.
This is a single-finger straight-line swipe, not pinch or multi-touch.

### Coordinate long press

`queueLongPress` accepts normalized `x`/`y`, captured `width`, `height`, `rotation`,
`packageName` and integer `durationMs` (500–3000). The manual controls offer a
separate long-press button and duration selector after a screenshot point is
selected. It does not launch the target app automatically.

The shared point queue waits for 1.5 seconds of target foreground presence, expires
after 60 seconds if not dispatched, and validates captured display geometry before
sending the gesture. New queued controls are blocked while a point gesture is in
flight. A missing Android completion callback times out after duration + 2 seconds;
late callbacks cannot release a newer gesture or replace its status.

Cancel stops queued work. An already dispatched gesture may finish on Android;
completion is reported as dispatch evidence, not proof of the requested UI effect.
Coordinate targeting checks package/display metadata, not a UI-tree fingerprint.

### Implemented `wait_for_ui` subset

The Flutter/native channel method is `waitForUi`. Required arguments are
`requestId`, `targetPackage`, `selector` (`text`, `contentDescription`, or
`resourceId`), `value` and `timeoutMs` (1,000–60,000 ms). The test UI offers
5, 15, 30 and 60 seconds; a target app must be selected first.

The tool polls every 250 ms, inspects only the target foreground root, and matches
only elements reported as visible. Text/description use trimmed, case-insensitive
exact equality; resource IDs use case-sensitive exact equality. Value length is
limited to 200 characters and traversal to 500 nodes / 30 levels. Android's
`flagReportViewIds` enables native resource-ID reporting where apps expose it.

Terminal codes are `UI_FOUND`, `UI_TIMEOUT` and `UI_CANCELLED`, with request ID,
target package, elapsed milliseconds and matched metadata on success. Invalid
arguments return `INVALID_ARGUMENT`; a second concurrent wait is rejected with
`UI_WAIT_IN_PROGRESS`. No node reference is retained for a later action.

Cancellation is scoped to the request ID. Changing target, floating Stop, page
disposal or service destruction cancels the wait. The UI ignores stale responses
and bounds missing channel responses independently of app lifecycle events.
Presence does not prove that an element is clickable or that all loading is done.
This tool does not open apps, interact with elements or start the next command.

### Screen and node references

Each `get_ui_tree` entry now includes `screenId`, `nodeId`, `packageName`,
`visible` and `enabled`, in addition to the existing properties. A read replaces
all previous references. IDs describe paths within that particular snapshot;
they are not persistent app identifiers. Android node objects are not retained
between requests.

`tapElementById` requires all three of `screenId`, `nodeId` and `targetPackage`.
It waits for the specified app, then compares the fresh bounded tree with the
saved tree (structure, text, descriptions, resource IDs, bounds and action state).
A mismatch returns `STALE_SCREEN`; it does not guess another matching label or
fall back to a coordinate. A successful dispatch consumes the snapshot.

Only visible, enabled, clickable non-input nodes can be clicked this way. The
button at the end of each exported UI row uses these references. Selecting the
row text still fills the existing text-target field. The UI clears consumed or
stale lists, prompting a fresh read.

Validation covers the accessible tree up to 500 visited nodes and depth 30;
it does not detect changes that Android does not expose. Returning to an
identical accessible tree is accepted if the reference is still from the latest
read. Package/window transitions alone do not make identical content stale.

### Example UI-tree response

``` json
{
  "screenId": "screen-12",
  "elements": [
    {
      "nodeId": "node-0.2",
      "text": "Battery",
      "resourceId": "com.android.settings:id/title",
      "clickable": true,
      "bounds": {
        "left": 20,
        "top": 340,
        "right": 420,
        "bottom": 420
      }
    }
  ]
}
```

The response illustrates screen and node references. The implementation generates
fresh identifiers for each read and rejects tree mismatches before exact-node clicks.

## 6. Task Lifecycle

Use a task lifecycle independent of the Flutter screen lifecycle.

Recommended states:

-   `queued`
-   `running`
-   `waiting_for_approval`
-   `paused`
-   `completed`
-   `failed`
-   `cancelled`

Each action should record:

-   Action ID and task ID
-   Requested target and method used (`ui_tree` or `vision`)
-   Start/end timestamps
-   Execution status
-   Verification outcome
-   Error information when relevant

Distinguish between "action dispatched" and "action verified." A
successful API call does not prove that the intended result occurred.

### Current deterministic sequence test

The command screen now has a five-step test runner: launch the selected app,
wait for a configured condition, read a fresh tree and uniquely resolve a button,
click its screen/node reference once, then wait for a configured result. All
three conditions use the selected text/description/resource-ID selector; waits
are fixed at 15 seconds each. No next-step click is generated automatically.

The result condition must be absent in the fresh pre-click tree, so an already
present label cannot falsely verify the click. Missing or ambiguous buttons,
stale snapshots, rejected clicks and timeouts stop the run; clicks are not retried.

Every tool call carries a run ID bound to the selected package. Android checks
this lease both before accepting a tool and after foreground waits. Floating Stop,
the runner Stop button, target changes and service destruction revoke the lease.
A native 120-second lease expiry bounds abandoned runs. Late responses cannot
restart a stopped run or overwrite a newer one. Manual tool controls are blocked
while a run owns the device; the Stop control remains available.

This is an in-memory test runner with status and step messages. It does not
implement persistent task history, process-death recovery, a general script
language or the AI agent loop. Normal app switching needs no intermediate user
button presses; background execution remains subject to Android/service limits.

## 7. Safety and Permission Boundaries

See [Action Risk Policy](Action-Risk-Policy.md) for the action classification,
approval, ambiguity, and verification rules.

-   Provide a visible Stop control in the main UI and, where possible,
    the notification or floating panel.
-   Require user confirmation for sensitive actions such as purchases,
    sending messages, deleting data, or confirming transactions.
-   Do not interpret a broad instruction as unlimited authorization for
    every subsequent action.
-   Never attempt to bypass Android security controls, protected
    screens, or permission prompts.
-   Treat screen contents as untrusted input. Text found in apps must
    not override the agent's policies or user intent.
-   Minimize sensitive data sent to an external AI service; explain when
    screenshots or UI text are transmitted.
-   Handle timeouts, lost permissions, service termination, and device
    lock states explicitly.
-   Keep logs useful for debugging while avoiding unnecessary storage of
    private screen content.

## 8. Repository Structure

``` text
mobilepilot/
├── lib/
│   ├── core/
│   │   ├── platform/
│   │   └── models/
│   └── features/
│       ├── chat/
│       ├── agent/
│       ├── device/
│       └── activity/
├── android/app/src/main/
│   ├── kotlin/.../
│   │   ├── MobilePilotPlugin.kt
│   │   ├── MobilePilotAccessibilityService.kt
│   │   ├── AccessibilityTreeReader.kt
│   │   ├── GestureController.kt
│   │   └── ScreenshotController.kt
│   └── res/xml/
│       └── mobilepilot_accessibility_service.xml
├── services/
│   └── agent-api/
├── test/
│   ├── agent/
│   └── device/
└── docs/
    ├── architecture.md
    ├── threat-model.md
    └── demo-script.md
```

This is a starting structure, not a requirement to create every folder
on day one.

## 9. Delivery Roadmap

### Phase 1 --- MVP (Target: 4 weeks)

Goal: prove that an AI can control a real Android phone and that users
can follow and stop the task.

-   [x] Set up Accessibility Service and a permission onboarding screen.
-   [x] Read the UI tree and act on supported UI elements (basic manual controls).
-   [x] Search launchable apps by display name and resolve ambiguous
        matches before launching.
-   [x] Add manual screenshot preview and normalized coordinate selection.
-   [ ] Add AI Vision fallback and validate model-provided coordinates.
-   [ ] Build the Flutter chat UI and tool-calling flow.
-   [ ] Show task status and verify the expected result after each action.
-   [x] Add a basic in-app screenshot preview using Android Accessibility
    screenshot capture.
-   [x] Add action timeouts, cancellation for pending actions, and basic
    error states. A user-visible task-wide Stop flow remains to be built.
-   [ ] Establish a repeatable end-to-end demo and measure reliability across
    repeated real-device runs.

### Phase 2 --- Background Agent

Goal: keep task management independent from the visible chat screen.

-   [ ] Add a task lifecycle independent of the chat widget/screen.
-   [ ] Add an ongoing-task notification where supported.
-   [ ] Test minimizing the app, screen-off behavior, and app lifecycle
    changes.
-   [ ] Persist task metadata and restore it after reopening.
-   [ ] Handle service termination, revoked permissions, and required
    user intervention.
-   [ ] Clearly report when a task cannot continue.

### Phase 3 --- Floating Control

Goal: let users observe and manage a task while using other apps.

-   [x] Add a draggable floating bubble and compact action panel through
    AccessibilityService windows. This implementation does not request a
    separate overlay permission.
-   [x] Add basic action controls and cancellation for pending actions.
-   [ ] Show task-wide status, approvals, and the latest verified result.
-   [ ] Allow switching between Live View and Chat Mode.
-   [ ] Complete overlay behavior, touch handling, and accessibility testing
    across supported devices and apps.

### Phase 4 --- External AI Agents

Goal: allow external agents to request actions securely.

-   [ ] Add an MCP Server or API Gateway.
-   [ ] Pair and authenticate external agents with the device.
-   [ ] Define per-tool permissions and task limits.
-   [ ] Add audit logs, rate limits, and remote cancellation.
-   [ ] Review network security and the handling of private screen data.

## 10. MVP Acceptance Criteria

The MVP is successful when:

-   A natural-language request can trigger a real-device workflow.
-   UI-tree targeting is attempted before Vision fallback.
-   The system verifies the result after each important action.
-   The same demo workflow succeeds in at least 9 out of 10 test
    attempts on the selected test device.
-   The user can stop the task and see meaningful error states.
-   Minimizing the app never causes the UI to falsely claim that a
    stopped task is still running.
-   A demo video shows the real device, the agent's actions, and the
    verification loop.
-   The README explains architecture, limitations, permission
    requirements, and design decisions.

## 11. Risks and Platform Constraints

1.  **Android version differences:** Accessibility and screenshot
    capabilities depend on OS version, service configuration, and device
    behavior.
2.  **Apps that expose limited UI:** Games, custom-rendered screens, and
    protected content may not expose useful Accessibility nodes.
3.  **Screen capture restrictions:** Capture may require a specific API
    and permission flow. It must not be assumed to work continuously in
    every background state.
4.  **Background execution:** Minimizing the app does not guarantee
    uninterrupted service or screen access.
5.  **Google Play policy:** Accessibility API usage intended to
    autonomously plan and execute actions across apps may be restricted.
    Review current Play policies and the exact product category before
    planning a public release.
6.  **Privacy and security:** Screenshots and UI text may contain
    sensitive information. Design data minimization and user consent
    into the system.

## 12. Recommended Implementation Order

1.  [x] Build a Kotlin/Flutter device-control spike: read the UI tree,
    interact with elements, and expose the controls in the app.
2.  [x] Add screenshot capture through Android Accessibility and a manual
    in-app preview.
3.  [ ] Implement Vision fallback and coordinate validation.
4.  [x] Build a bounded prototype agent loop and typed AI tools; validate
    model-driven workflows separately before calling them reliable.
5.  [x] Connect the current device controls to Flutter using Platform
    Channels.
6.  [ ] Add persistent task state, task-wide Stop, and recovery.
7.  [ ] Establish a repeatable real-device workflow and measure its
    reliability.
8.  [ ] Harden background execution and floating controls, then add external
    MCP access.

The most important design principle is to keep the Agent Orchestrator
separate from the Android Control Engine. That lets MobilePilot evolve
from an on-device portfolio MVP into a tool that external AI agents can
use, without replacing the core control logic.


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


### Additional tool completion order

1. Double tap: implemented; native/Flutter checks and real-device fixture passed.
2. Hold then drag: native/Flutter checks and connected Chrome drop-target test passed; two continuous stroke phases, API 26+.
3. Select editable field and replace/clear text: native/Flutter checks and connected Chrome focus/replace/clear test passed.
4. Keyboard editor actions: native/Flutter checks and device Search, Next/Tab, Enter tests passed.
5. Wait for enabled/text-change states: native/Flutter checks and connected-device state-change tests passed.

The connected-device integration suite lives in `integration_test/device_tools_test.dart` and uses a dedicated local Chrome fixture. It tests actual UI effects rather than treating dispatch acceptance as proof.


### Additional manual tools completed — 2026-10-27

All five tools above were implemented and verified sequentially, with a final combined run of five connected-device integration tests passing on the HONOR / Chrome fixture. The native suite passes 158 tests and Flutter unit/widget suite passes 63. This establishes the tested fixture behavior, not universal app compatibility. AI integration remains out of scope.

- **Double tap:** `queueDoubleTap` shares captured app/display validation, target settling, cancellation and in-flight tracking. One gesture contains two 60 ms contacts starting at 0 and 140 ms. Android 7+.
- **Hold then drag:** `queueDrag` uses a stationary continued stroke (500–2000 ms hold) followed by a continuous movement (100–3000 ms). Both endpoints use captured normalized coordinates. It rechecks foreground/display after holding and releases without moving if they changed. Android 8+. UI uses red/blue swipe endpoints and a separate hold duration.
- **Exact editable field:** `editElementById` supports focus/replace/clear with a fresh screenId/nodeId and selected target. It validates the snapshot fingerprint, editable/enabled/visible state, consumes the reference before dispatch, and blocks password fields. Text is bounded to 2000 characters; clear sends an empty string. Read a fresh tree after each action. The UI exposes these actions in each editable row's menu.
- **Keyboard:** `queueScreenAction(action: keyboard, text: default|search|next|enter)` operates only on the target's focused, enabled, non-password editor. Default invokes the exposed IME node action (Android 11+). Explicit modes require Android 13+ and a matching accessibility InputConnection. Search/Next must match the editor's advertised action. Next explicitly sends balanced Tab key events because Chrome ignored `performEditorAction(NEXT)` in the device fixture; Enter sends balanced Enter events. Dispatch does not guarantee an app effect or submission success.
- **More wait states:** `waitForUi(condition: enabled)` requires a visible enabled/clickable button stable for 500 ms. `condition: textChanged` requires a unique resourceId/contentDescription locator, records its first text, and waits for a different value stable for 500 ms. Missing nodes do not count as changed text; ambiguous matches fail explicitly; incomplete scans and wrong-app roots cannot satisfy a state wait. No click follows success.


### Refactor and review — 2026-10-27

The gesture dispatch and keyboard connection handling were simplified, and duplicate pending-status redraws were reduced. Review fixes prevent a cancelled or stale drag hold from continuing, require visible viewport bounds for UI presence, recheck foreground for the default keyboard action, and recognize an enabled clickable ancestor of a matched label. Native 165 tests and Flutter 63 tests passed with analysis and a regular debug build. The earlier five connected-device checks preceded these review fixes; see the subsequent device run below.


### Post-review device verification — 2026-10-27

The connected HONOR passed eight integration cases, including offscreen presence, stopping during drag hold, and a real Thai Settings flow that scrolled twice to About phone, tapped it, and verified the device-name label. Testing exposed an early continuing-stroke callback: drag now waits until the requested hold interval has elapsed before evaluating cancellation and dispatching movement. Native 165 tests, Flutter 63 tests, analysis, and the regular debug build passed after the fix. Keyboard fixture output was verified in the accessibility tree; Chrome reported its label as zero-height while the keyboard was open.
