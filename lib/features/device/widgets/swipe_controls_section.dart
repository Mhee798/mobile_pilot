import 'package:flutter/material.dart';

import '../controllers/screen_capture_controller.dart';
import '../controllers/screen_action_controller.dart';

class SwipeControlsSection extends StatelessWidget {
  const SwipeControlsSection({
    super.key,
    required this.capture,
    required this.actions,
    required this.busy,
  });
  final ScreenCaptureController capture;
  final ScreenActionController actions;
  final bool busy;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            label: const Text('เลือกจุดเริ่ม'),
            selected: !capture.selectingSwipeEnd,
            onSelected: busy ? null : (_) => capture.selectSwipeEnd(false),
          ),
          ChoiceChip(
            label: const Text('เลือกจุดปลาย'),
            selected: capture.selectingSwipeEnd,
            onSelected: busy ? null : (_) => capture.selectSwipeEnd(true),
          ),
        ],
      ),
      Text(
        capture.selectingSwipeEnd
            ? 'แตะภาพเพื่อวางธงสีน้ำเงินที่จุดปลาย'
            : 'แตะภาพเพื่อวางหมุดสีแดงที่จุดเริ่ม',
      ),
      if (capture.swipeEndX != null && capture.swipeEndY != null)
        Text(
          'จุดปลาย: x=${capture.swipeEndX!.toStringAsFixed(3)}, y=${capture.swipeEndY!.toStringAsFixed(3)}',
        ),
      DropdownButtonFormField<int>(
        initialValue: actions.swipeDurationMs,
        decoration: const InputDecoration(labelText: 'ระยะเวลาปัด'),
        items: [
          for (final ms in [100, 250, 400, 750, 1000, 1500, 2000, 3000])
            DropdownMenuItem(value: ms, child: Text('${ms / 1000} วินาที')),
        ],
        onChanged: busy
            ? null
            : (value) {
                if (value != null) actions.setSwipeDuration(value);
              },
      ),
      OutlinedButton.icon(
        onPressed:
            busy ||
                capture.selectedX == null ||
                capture.selectedY == null ||
                capture.swipeEndX == null ||
                capture.swipeEndY == null
            ? null
            : actions.swipeSelectedPoints,
        icon: const Icon(Icons.swipe),
        label: const Text('เตรียมปัดจากจุดเริ่มไปจุดปลาย'),
      ),
    ],
  );
}
