import 'package:flutter/services.dart';

import 'device_controller.dart';

class FloatingControlsController extends DeviceController {
  FloatingControlsController(super.feedback);

  bool isEnabled = false;
  bool isUpdating = false;

  Future<void> load() async {
    try {
      final enabled = await platform.getFloatingControlsEnabled();
      if (mounted) {
        update(() => isEnabled = enabled ?? false);
      }
    } on PlatformException {
      if (mounted) update(() => feedback.message = 'อ่านสถานะปุ่มลอยไม่ได้');
    } on MissingPluginException {
      if (mounted) {
        update(() => feedback.message = 'อัปเดตแอปด้วย Android build ใหม่ก่อน');
      }
    }
  }

  Future<void> setEnabled(bool enabled) async {
    update(() => isUpdating = true);
    try {
      final response = await platform.setFloatingControlsEnabled(enabled);
      if (mounted) {
        update(() {
          isEnabled = response?['enabled'] as bool? ?? false;
          feedback.message =
              response?['message'] as String? ?? 'เปลี่ยนสถานะปุ่มลอยแล้ว';
        });
      }
    } on PlatformException catch (error) {
      if (mounted) {
        update(() {
          isEnabled = !enabled;
          feedback.message = error.message ?? error.code;
        });
      }
    } on MissingPluginException {
      if (mounted) {
        update(() {
          isEnabled = !enabled;
          feedback.message =
              'ไม่พบ floating controls channel; ต้อง build Android ใหม่';
        });
      }
    } finally {
      if (mounted) update(() => isUpdating = false);
    }
  }
}
