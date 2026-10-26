# MobilePilot --- AI Mobile Use for Android

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

## Current Implementation Status — 2026-10-26

The project currently has a working **manual Android-control prototype**. It is
not an AI agent yet: the user selects and runs individual controls from the
MobilePilot screen; there is no natural-language planner, model connection, or
tool-calling loop.

| Area | Status | Evidence / limit |
| --- | --- | --- |
| Accessibility onboarding and service status | Done | Opens Android Accessibility settings, checks status on return, and opens the command screen when enabled. |
| UI tree and element actions | Done, basic | Reads accessible elements and supports text-based tap with gesture fallback. Unique-target disambiguation and screen-versioned node IDs are not implemented. |
| App search and launch | Done, basic | Searches launchable apps by display name and lets the user choose a result. |
| Screenshot and coordinate control | Done, basic | Captures another app, previews it, selects a point, and queues tap, scroll, horizontal swipe, Back, or text entry. Capture is event-driven and device behavior still needs broader testing. |
| Focused text entry | Verified on device | On 2026-10-26, `MP_SAFE_TEST_42` was inserted into Chrome's focused address field on a PTP N49. It was not submitted. Password fields are blocked. |
| Floating controls | Implemented, basic | Accessibility service can show a draggable bubble and action panel, including cancel. Overlay behavior needs more device/app testing. |
| AI planner, Vision fallback, chat, task history | Not started | No model/API integration, natural-language planning, or persistent task history yet. |
| Verification and task lifecycle | Partial | Some actions report dispatch status; there is a constrained Android Settings tree-change check. General post-action verification, task states, and recovery are not implemented. |

The latest `flutter analyze`, Android debug build, and installation on the
connected device succeeded. These checks confirm the current prototype builds;
they do not satisfy the MVP reliability target or prove broad app compatibility.

After the controller refactor, a PTP N49 smoke run on 2026-10-26 verified app
launch, UI-tree reading, capture/point tap, floating gestures, focused text entry,
cancellation and capture expiry/retry. A point-tap window-event cancellation bug
found during that run was fixed and covered by two regression tests. The native
suite now passes 40 tests and the Flutter suite passes 16; see
[Testing](Testing.md) for commands, device observations and harness limitations.

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
stream, and the floating panel is not yet connected to an AI task lifecycle.
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

### Example UI-tree response

``` json
{
  "screenId": "screen-12",
  "elements": [
    {
      "id": "node-42",
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

The `screenId` and node reference are illustrative. The implementation
should generate its own identifiers and invalidate them when the UI
changes.

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
4.  [ ] Build the agent loop and typed AI tools.
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
