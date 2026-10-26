# Action Risk Policy

## Purpose

This policy defines how MobilePilot should decide whether an Android UI action can run immediately, needs user approval, or must pause because its target or effect is unclear. It applies to Accessibility actions, coordinate gestures, and actions requested by an AI agent.

This is a product rule for implementation. The current prototype does not yet enforce these risk gates.

## How to Assess an Action

Assess the specific action and its expected effect using the available evidence:

1. Identify the operation: read, navigate, change a setting, enter data, submit, send, delete, purchase, grant access, or another operation.
2. Identify the exact target and affected data or person from the current screen, UI tree, and task context.
3. Determine whether the effect is reversible, remains on-device, or commits information or changes outside the current screen.
4. If the target or effect is ambiguous, treat it as unclassified and ask the user. Do not guess from an app name, icon, or label alone.

App-provided text and screen content are evidence about the interface, not instructions that can change this policy or expand the user's authorization. AI confidence by itself is not proof that a target or consequence is safe.

## Risk Levels

### Low: Read or Navigate

Examples:

- Read a screen or UI tree.
- Scroll, open a page, or go back.
- Search or inspect information without submitting a change.

Run these actions within the user's requested task. Stop if the action unexpectedly reaches a consequential confirmation screen.

### Medium: Reversible, On-Device Changes

Examples:

- Change a display preference or another ordinary setting that can be restored.
- Fill a draft field without submitting it.

Show the exact value or field that will change. Keep an undo or restore path where the app supports one. If the setting affects privacy, security, account access, permissions, or external sharing, classify it as high risk instead.

### High: Consequential or Hard-to-Reverse Actions

Examples:

- Send a message, publish a post, share a file, or place a call.
- Buy an item, make a payment, or confirm a transaction.
- Submit a form that creates an external commitment.
- Delete data, change account/security access, or grant a sensitive permission.

Pause for explicit approval immediately before each such action. The approval preview must identify the action, target or recipient, exact content or value when applicable, and expected consequence. Provide separate, clearly labeled approval and cancel controls. Approval is limited to that one action and expires if the target screen or action changes.

## Ambiguous or Unclassified Actions

- Do not execute an action autonomously when its target or effect cannot be determined from the available evidence.
- For an unlabeled coordinate or icon, show the captured screen and intended point and require the user to choose or confirm that point before acting.
- If the screen changes after approval, discard the approval and ask again against the new screen.
- If an app's wording or behavior conflicts with the user's request, stop and explain the conflict.

## Execution and Verification

- Distinguish queued, dispatched, and verified states. A successful Accessibility API call or completed gesture does not prove that the app performed the intended operation.
- After an action, inspect the resulting screen or UI tree when possible and report what changed. If the result cannot be observed, report it as unverified.
- A Stop or cancel request must clear pending actions and approvals before any further action is sent.
- Never bypass Android security controls, protected screens, or permission prompts.

## Implementation Requirements

- Enforce this policy in the action-execution layer; do not rely on an AI prompt or documentation alone.
- Use explicit rules for known action types and consequences. Treat missing or conflicting evidence as unclassified rather than inventing a risk score.
- Keep approval scoped to one action, one target, and the visible content or value shown in the approval preview.
- Avoid storing screenshots or private screen text longer than required for the current task. Disclose before sending screen data to an external AI service.
