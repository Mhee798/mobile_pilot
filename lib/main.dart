import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'features/home/presentation/screen/floating_chat_page.dart';

export 'app.dart' show MobilePilotApp;
export 'features/setup/presentation/screen/accessibility_setup_page.dart'
    show AccessibilitySetupPage;
export 'features/device/presentation/screen/command_page.dart' show CommandPage;

// Set to true to open the existing diagnostic screens instead of Home.
const bool useDebugUi = false;

@pragma('vm:entry-point')
Future<void> floatingChatMain(List<String> args) =>
    runFloatingChat(capsule: args.contains('capsule'));

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  runApp(const MobilePilotApp(useDebugUi: useDebugUi));
}
