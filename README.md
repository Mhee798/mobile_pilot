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
