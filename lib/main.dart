import 'package:flutter/material.dart';

import 'app.dart';

export 'app.dart' show MobilePilotApp;
export 'features/setup/presentation/accessibility_setup_page.dart'
    show AccessibilitySetupPage;
export 'features/device/presentation/command_page.dart' show CommandPage;

// Keep the existing test screens as the default while the production UI is
// being built. Set to false to preview its separate entry point.
const bool useDebugUi = true;

void main() {
  runApp(const MobilePilotApp(useDebugUi: useDebugUi));
}
