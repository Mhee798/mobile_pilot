import 'package:flutter/material.dart';

import '../controllers/floating_controls_controller.dart';

class FloatingControlsToggle extends StatelessWidget {
  const FloatingControlsToggle({super.key, required this.floating});

  final FloatingControlsController floating;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: floating.isEnabled,
      onChanged: floating.isUpdating ? null : floating.setEnabled,
      title: const Text('ปุ่มลอย MobilePilot'),
      subtitle: const Text(
        'แสดงแผงคำสั่งบนแอปอื่น ใช้ Accessibility ที่เปิดอยู่ ไม่ต้องเปิดสิทธิ์ overlay แยก',
      ),
      secondary: floating.isUpdating
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.bubble_chart_outlined),
    );
  }
}
