import 'package:flutter/material.dart';

import '../../../../core/platform/mobile_pilot_platform.dart';

/// Offers settings and rechecks the permission when the app resumes.
class AccessibilityRequiredAction extends StatefulWidget {
  const AccessibilityRequiredAction({super.key, required this.onStatus});
  final void Function(bool?) onStatus;

  @override
  State<AccessibilityRequiredAction> createState() =>
      _AccessibilityRequiredActionState();
}

class _AccessibilityRequiredActionState
    extends State<AccessibilityRequiredAction>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final enabled = await const MobilePilotPlatform()
          .isAccessibilityServiceEnabled();
      if (mounted) widget.onStatus(enabled);
    } catch (_) {
      // Keep the action visible if the status cannot be checked.
    }
  }

  Future<void> _open() async {
    try {
      await const MobilePilotPlatform().openAccessibilitySettings();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เปิดการตั้งค่าไม่สำเร็จ')),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: _open,
    icon: const Icon(Icons.settings_accessibility),
    label: const Text('เปิด Accessibility เพื่อใช้เครื่องมือ'),
  );
}
