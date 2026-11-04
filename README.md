# MobilePilot

## Firebase setup for a new checkout

Firebase configuration is local and is not committed. To build the Android app,
create or select a Firebase project, register the Android package
`com.example.mobile_pilot`, and run `flutterfire configure` for that project.
Generate `lib/firebase_options.dart` and place the Android configuration at
`android/app/google-services.json`. Enable Firebase AI Logic and configure App
Check for the app; debug builds use a registered App Check debug token, while
release builds use Play Integrity. Never commit debug tokens or local Firebase
configuration. The cloud feature requires network access and an enabled model.

Gemini Nano is optional and requires a compatible Android device and AICore;
the system may download its model when first prepared.

Gemini Cloud currently retains the conversation and tool results, including
captured images, for the active chat. Long chats can grow in memory, token use
and network traffic; start a new chat when needed. Bounded history with an
explicit context handoff remains future work.

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.


## App languages

The production Home, sidebar, chat input and settings support Thai and English
using `easy_localization`. Thai is the initial language; an explicit selection
in Settings > Appearance > App language is saved by the package.

Edit `assets/translations/th.json` and `assets/translations/en.json` together.
Use `context.tr('section.key')` in widgets so text updates when the locale changes.
Run `flutter test test/localization_test.dart test/settings_page_test.dart` to
check catalog keys, placeholders, language switching and persistence.

UI language is independent of AI conversations, dictation and the Thai TTS demo.
The existing AI/device test screens retain their original text.


## Model picker

Open Models from the Home title or Settings > AI > Model. Local `.litertlm`
files are streamed into the app's `model_library` directory and indexed in
`model_library_v1` (Hive). Downloads and imported files share the same library. Completed transfer metadata
is written before the staging-file rename, so startup can finish a committed
rename and remove abandoned numeric `.partial` files. Unindexed complete model
files and unrelated staging files are retained.
The file's model family and image-mode preference are explicit at import.
Files outside this library can be loaded as legacy entries but cannot be deleted
from the picker.

The selected configuration is persisted separately from runtime readiness:
after restart, tap a selection to load it or check cloud access again. File
switches install without activating first, release the previous runtime, open
the new one, then commit the SDK identity. If opening fails, the previous runtime
is restored when possible; changing runtimes starts a fresh conversation context.

Nano availability is probed without downloading. Only Prepare and use requests
OS preparation. Cloud selection checks Gemini access through the existing Firebase
configuration using a fixed token-count request; it never sends chat history.
This marks the connection as checked, not a guarantee of inference quota.
Deleting an owned model unregisters its SDK identity before deleting its file.
The cloud test chat inherits the selected cloud model. The production Home chat
input remains a UI preview.

Model catalog references:
- https://aistudio.google.com/docs/models
- https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm
- https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm
