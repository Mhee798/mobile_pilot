# Project structure

The Flutter code is organized by feature under `lib/features`. Each feature
contains the layers it currently needs:

- `presentation`: screens, widgets, and UI state or controllers.
- `data`: integrations with external libraries, platform services, and storage.
- `application`: task orchestration and state shared across screens.
- `domain`: add this when a feature has business rules or contracts that can
  be independent of Flutter and external integrations.

`lib/core/platform` contains the shared Android platform-channel adapter.
`lib/app.dart` assembles the app, and `lib/main.dart` starts it. Tests live in
`test` and device integration tests in `integration_test`.

This folder organization is an incremental step toward Clean Architecture.
Existing controllers and AI services still combine some UI, application, and
integration responsibilities. Move those responsibilities behind domain
contracts when the relevant feature needs them; folder names alone do not
enforce dependency boundaries.

The app-level `BlocProvider` owns one `AiTaskController` and its model service.
The chat route observes that controller without closing it on navigation, so
messages, model settings and in-flight operations survive leaving the chat.
Initial screen context is accepted only for an idle, empty conversation; reopening
chat must not overwrite a running task's target. The old `AiTestCubit` and
`AiTestState` names are compatibility aliases. A service explicitly injected into
the test page remains page-owned for isolated tests.

This lifetime lasts within the Flutter process. It does not provide Android
foreground execution or process-death recovery.

The app injects `AiTaskOverlay` into the controller. The dedicated
`com.mobilepilot/ai_task` channel publishes status changes (not answer tokens)
to a separate AI status line in the accessibility overlay. Its Stop button
cancels native pending commands immediately and asks the controller to stop
generation. Manual overlay actions are blocked during generation. The controller
publishes completion only after generation exits; the native bridge keeps status
in memory and clears it when the Flutter engine disconnects. This does not add
a foreground service or guarantee background inference.

App choices retain the request that produced them. After the user selects a
candidate, a verified `opened` result resumes generation with that request and
the chosen app, under the same serialized operation. An unconfirmed/failed open
does not resume. Cancel, a new user request, or reset discards the pending request;
an automatic successful open also invalidates earlier search choices. Resumption
uses the normal generation and Stop path, without adding a duplicate user message.

`AiDeviceActions` validates mutation arguments, manages short native leases,
single-use node/capture references, capture metadata, queued results, and
cancellation. `ai_action_definitions.dart` groups related actions into compact
schemas. `AiDeviceTools` owns selected-target and paged-tree context; named nodes
are paged before layout-only nodes without dropping non-password nodes.
`runAiToolLoop` executes calls sequentially (including model parallel batches),
feeds a result for every committed call, and attaches screenshot bytes to the
tool response outside JSON when Vision is enabled. It bounds both rounds and
calls. The model service discards a chat on exceptions so incomplete native
history is never reused. Native dispatch results require a later UI check;
they do not constitute semantic verification of the goal.

Review hardening: cancellation is rechecked after app search, and selection/open
is part of the running task. Coordinate actions compare bounded UI-tree content
before/after capture and again before dispatch. This cannot detect pixel-only
changes invisible to Accessibility and is not atomic with screenshot acquisition.
Native terminal failure codes now become error results consumed by the repeat
guard. A three-minute loop budget bounds model/tool waits; cancellation still
depends on native/engine responsiveness. Final text is withheld when a dispatched
action has no subsequent successful live read; a live read alone does not prove
the user's semantic goal. device_status distinguishes permission enabled, service
connected, and active-window availability. Persistent recovery and general
goal-condition verification remain future work.

The model-facing UI API now uses monotonic numeric refs, scoped to the current
snapshot. The adapter retains full native IDs/text and resolves refs without
accepting old references. `verify_goal(ref: number)` derives a unique locator and
observed checkbox state locally, then performs a new read; the model does not
copy selectors or expected text. Legacy snapshot/node arguments remain an internal
compatibility path, not the published model schema.

`modelPayload` strips native identifiers, duplicate fields and geometry from UI
tool replies. A 4000-byte JSON-result budget stops a turn and balances outstanding
calls; it is a conservative text-budget heuristic, not an exact tokenizer or
image-token bound. Tool mode recreates the native chat per user turn with a
bounded factual continuation summary rather than growing native history forever.
This retains partial context, not verbatim conversation memory.

After a mutation, another mutation is blocked until fresh evidence is assessed.
A matched final goal blocks further mutations. This guards the execution order;
it does not prove the model chose a semantically sufficient goal condition.

The model-facing action and verification schemas now use an exact `label` from
the latest UI. The adapter requires a single matching node; truncated, missing
or duplicate labels are rejected, never resolved by guessing. Internal numeric
refs remain supported for adapter compatibility. A premature final answer can
receive one bounded verification reminder. If verification matches on the last
tool round, one additional text-only generation may report the result; tool
calls from that reporting generation are not executed.

AI run history is a separate, display-only local store (`AiRunHistory`), not a
replay queue or model memory. It records requests, loaded-model file identity,
tool arguments/results, elapsed time, and stop reasons. Manual app selection is
recorded as its own run. Storage retains at most 30 runs/40 steps per run with a
512 KiB aggregate target (older runs are evicted), bounded details, and no binary
images/icons. Text can contain private screen data; the history page offers
confirmed deletion while no run is active. Restored in-flight work is uncertain.

`AiTaskState` and chat message data now live outside the controller. Tool-result
presentation is handled separately from generation, and the service shares one
result-notification path for executed and blocked calls. Recovery checkpoints
remain independent of diagnostic history.
