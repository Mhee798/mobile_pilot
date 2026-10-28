import 'package:flutter/material.dart';

import '../controllers/device_controller.dart';
import 'swipe_controls_section.dart';
import '../controllers/screen_capture_controller.dart';
import '../controllers/screen_action_controller.dart';

class ScreenActionsSection extends StatelessWidget {
  const ScreenActionsSection({
    super.key,
    required this.capture,
    required this.actions,
    required this.feedback,
    required this.onTextChanged,
  });

  final ScreenCaptureController capture;
  final ScreenActionController actions;
  final CommandFeedback feedback;
  final VoidCallback onTextChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (capture.packageName != null)
          Text(
            'ภาพจาก ${capture.packageName!}. เข้าคิวแล้วกดเปิดแอปเป้าหมาย หรือสลับไปแอปนั้นภายใน 60 วินาที',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (capture.packageName != null) ...[
          SwipeControlsSection(
            capture: capture,
            actions: actions,
            busy: feedback.isTapping,
          ),
          OutlinedButton.icon(
            onPressed: feedback.isTapping || capture.selectedX == null
                ? null
                : actions.doubleTapSelectedPoint,
            icon: const Icon(Icons.touch_app),
            label: const Text('เตรียมแตะสองครั้งพิกัดนี้'),
          ),
          DropdownButtonFormField<int>(
            initialValue: actions.dragHoldMs,
            decoration: const InputDecoration(labelText: 'กดค้างก่อนลาก'),
            items: [
              for (final ms in [500, 750, 1000, 1500, 2000])
                DropdownMenuItem(value: ms, child: Text('$ms ms')),
            ],
            onChanged: feedback.isTapping
                ? null
                : (value) {
                    if (value != null) actions.setDragHold(value);
                  },
          ),
          OutlinedButton.icon(
            onPressed:
                feedback.isTapping ||
                    capture.selectedX == null ||
                    capture.swipeEndX == null
                ? null
                : actions.dragSelectedPoints,
            icon: const Icon(Icons.open_with),
            label: const Text('เตรียมลากจากจุดแดงไปจุดน้ำเงิน'),
          ),
          const Text(
            'ใช้เวลาลากจากตัวเลือกเวลาปัดด้านบน · กดค้างแล้วเคลื่อนโดยไม่ยกนิ้ว',
          ),
          DropdownButtonFormField<int>(
            initialValue: actions.longPressDurationMs,
            decoration: const InputDecoration(labelText: 'ระยะเวลากดค้าง'),
            items: [
              for (final ms in [500, 750, 1000, 1500, 2000, 3000])
                DropdownMenuItem(value: ms, child: Text('${ms / 1000} วินาที')),
            ],
            onChanged: feedback.isTapping
                ? null
                : (value) {
                    if (value != null) actions.setLongPressDuration(value);
                  },
          ),
          OutlinedButton.icon(
            onPressed:
                feedback.isTapping ||
                    capture.selectedX == null ||
                    capture.selectedY == null
                ? null
                : actions.longPressSelectedPoint,
            icon: const Icon(Icons.touch_app),
            label: const Text('เตรียมกดค้างพิกัดนี้'),
          ),
          OutlinedButton.icon(
            onPressed: actions.cancelPending,
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('ยกเลิกคำสั่งที่รอ'),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: feedback.isTapping
                    ? null
                    : () => actions.queue('scroll_up'),
                icon: const Icon(Icons.arrow_upward),
                label: const Text('เลื่อนขึ้น'),
              ),
              OutlinedButton.icon(
                onPressed: feedback.isTapping
                    ? null
                    : () => actions.queue('scroll_down'),
                icon: const Icon(Icons.arrow_downward),
                label: const Text('เลื่อนลง'),
              ),
              OutlinedButton.icon(
                onPressed: feedback.isTapping
                    ? null
                    : () => actions.queue('swipe_left'),
                icon: const Icon(Icons.swipe_left),
                label: const Text('ปัดซ้าย'),
              ),
              OutlinedButton.icon(
                onPressed: feedback.isTapping
                    ? null
                    : () => actions.queue('swipe_right'),
                icon: const Icon(Icons.swipe_right),
                label: const Text('ปัดขวา'),
              ),
              OutlinedButton.icon(
                onPressed: feedback.isTapping
                    ? null
                    : () => actions.queue('back'),
                icon: const Icon(Icons.arrow_back),
                label: const Text('ย้อนกลับ'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: actions.keyboardAction,
            decoration: const InputDecoration(
              labelText: 'ปุ่มคีย์บอร์ดของช่องที่โฟกัส',
            ),
            items: const [
              DropdownMenuItem(
                value: 'default',
                child: Text('ปุ่มปัจจุบันของช่อง'),
              ),
              DropdownMenuItem(value: 'search', child: Text('ค้นหา (Search)')),
              DropdownMenuItem(
                value: 'next',
                child: Text('ถัดไป (Next / Tab)'),
              ),
              DropdownMenuItem(value: 'enter', child: Text('Enter')),
            ],
            onChanged: feedback.isTapping
                ? null
                : (value) {
                    if (value != null) actions.setKeyboardAction(value);
                  },
          ),
          OutlinedButton.icon(
            onPressed: feedback.isTapping ? null : actions.pressKeyboardAction,
            icon: const Icon(Icons.keyboard_return),
            label: const Text('เข้าคิวกดปุ่มคีย์บอร์ด'),
          ),
          const Text(
            'อาจค้นหา ส่งฟอร์ม หรือขึ้นบรรทัดใหม่ตามแอป · Next ส่ง Tab เพื่อเลื่อนโฟกัส · Search/Next ต้องตรงกับปุ่มที่ช่องเสนอ · ระบุปุ่มเองใช้ Android 13 ขึ้นไป',
          ),
          TextField(
            controller: actions.textController,
            maxLength: 2000,
            onChanged: (_) => onTextChanged(),
            decoration: const InputDecoration(
              labelText: 'ข้อความสำหรับช่องที่โฟกัส',
              helperText: 'แตะช่องข้อความในแอปเป้าหมายก่อนกลับมาเข้าคิว จากนั้นกดเปิดแอปเป้าหมาย ข้อความจะส่งไปแอปในภาพเท่านั้น',
              border: OutlineInputBorder(),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed:
                  feedback.isTapping || actions.textController.text.isEmpty
                  ? null
                  : () => actions.queue(
                      'type_text',
                      text: actions.textController.text,
                    ),
              icon: const Icon(Icons.keyboard),
              label: const Text('เข้าคิวใส่ข้อความ'),
            ),
          ),
          Text(
            'ข้อความจะแทนที่เนื้อหาในช่องที่โฟกัส ไม่กดส่ง และจะไม่พิมพ์ลงช่องรหัสผ่าน',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
