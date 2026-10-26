import 'package:flutter/material.dart';

import 'app.dart';

export 'app.dart' show MobilePilotApp;
export 'features/setup/accessibility_setup_page.dart'
    show AccessibilitySetupPage;
export 'features/device/command_page.dart' show CommandPage;

void main() {
  runApp(const MobilePilotApp());
}
