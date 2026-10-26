import 'package:flutter/material.dart';

import 'features/setup/accessibility_setup_page.dart';

class MobilePilotApp extends StatelessWidget {
  const MobilePilotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MobilePilot',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3157D5)),
        useMaterial3: true,
      ),
      home: const AccessibilitySetupPage(),
    );
  }
}
