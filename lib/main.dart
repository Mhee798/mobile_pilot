import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'app.dart';

export 'app.dart' show MobilePilotApp;
export 'features/setup/presentation/screen/accessibility_setup_page.dart'
    show AccessibilitySetupPage;
export 'features/device/presentation/screen/command_page.dart' show CommandPage;

// Set to true to open the existing diagnostic screens instead of Home.
const bool useDebugUi = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  runApp(const MobilePilotApp(useDebugUi: useDebugUi));
}
