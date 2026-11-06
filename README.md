# MobilePilot

MobilePilot is an Android AI agent that turns chat instructions into actions on your phone. Ask it to open an app, find a screen element, or enter a search query, then follow its tool steps and stop the task from the main chat or floating overlay.

## Screenshots

<img src="doc/screenshots/main-chat.png" alt="MobilePilot main chat welcome screen" width="240"> <img src="doc/screenshots/model-picker.png" alt="MobilePilot model picker with on-device and cloud tabs" width="240">

## Demos

| Demo | What the recording shows |
| --- | --- |
| [Play lo-fi in YouTube](doc/demos/MobilePilot-YouTube.mp4) · 16 s | A request starts in the floating chat. The chat collapses as Gemini starts using tools, and YouTube opens the *Chill Lofi Mix* video page. |
| [Search for MacBook in Shopee](doc/demos/MobilePilot-Shopee.mp4) · 19 s | A request starts in the main chat. Gemini opens Shopee, enters `MacBook`, and reaches the search results while the floating bubble shows progress. |

Both clips were recorded on an Android phone and edited for length. They show the destinations reached in those runs.

## Features

- **Android device tools** for launching apps, reading the accessibility tree, waiting for UI changes, and performing supported text, tap, and gesture actions.
- **Local and cloud models.** Import or download compatible LiteRT-LM models, use Gemini Cloud through Firebase AI Logic, or try Gemini Nano on supported devices.
- **Floating chat** with the same active conversation and model as the main app. Send messages, choose an app when the agent asks, inspect tool steps, stop a run, or return to the main app.
- **Persistent chat** with conversation search, drafts, image and file attachments, and retry. The interface supports Thai and English and light and dark themes.

## Architecture

```mermaid
flowchart LR
  Home["Flutter main chat"]
  Overlay["Flutter floating chat"]
  Model["Local or Gemini Cloud tool loop"]
  Service["Kotlin Accessibility Service"]
  Device["Android target app"]

  Overlay <-->|"Conversation bridge"| Home
  Home <-->|"Messages and tool results"| Model
  Model <-->|"Typed tools via platform channels"| Service
  Service <-->|"UI tree, screenshots and actions"| Device
```

The Android layer checks that a UI reference still matches the target before using it. An accepted gesture and a verified outcome are tracked separately. The floating chat runs in a separate Flutter engine and shares conversation state through a native bridge.

[Project structure](doc/architecture.md) · [AI tool guide](doc/AI-Tool-Guide.md)

## Run locally

1. Install Flutter with Dart **3.13.7** or newer within Dart 3, plus the Android SDK. MobilePilot requires **Android 11 (API 30)** or newer. Use a physical device for cross-app control.
2. Create a Firebase project, register the Android package `com.example.mobile_pilot`, and run `flutterfire configure` for that project. Generate `lib/firebase_options.dart` and place `google-services.json` in `android/app/`. These local configuration files are ignored by Git.
3. For Gemini Cloud, enable Firebase AI Logic and configure App Check. Debug builds use a registered App Check debug token. Release builds use Play Integrity. Keep debug tokens private.
4. Connect the device and run:

   ```sh
   flutter pub get
   flutter run
   ```

5. Choose a model from the chat header or Settings. For device actions, enable the MobilePilot service in Android Accessibility settings. Enable the floating window in MobilePilot settings to use chat while another app is open.

For local inference, import a compatible `.litertlm` file or select a model from the download catalog. Gemini Nano availability depends on the device and AICore.

## Testing and limits

```sh
flutter analyze
flutter test
```

- Device-control outcomes depend on the target app, accessibility data, Android version, and permissions. The demos are individual observed runs. The roadmap tracks a repeatability target of at least 9 successful runs out of 10 for the same workflow.
- Background execution depends on Android and the selected model. The task journal can report interruptions after reopening. Gemini Nano inference is subject to foreground restrictions.
- UI text and screenshots can contain private data. When using cloud models, review the available screenshot-sharing settings and use harmless tasks for demos. Per-action approvals for consequential actions are planned.

[Testing evidence](doc/Testing.md) · [Model testing](doc/Model-Testing-Results.md) · [Roadmap](doc/MobilePilot-Plan.md) · [Action risk policy](doc/Action-Risk-Policy.md)
