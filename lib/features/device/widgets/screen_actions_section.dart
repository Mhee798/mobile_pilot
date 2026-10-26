import 'package:flutter/material.dart';

import '../controllers/device_controller.dart';
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
            capture.packageName!.toLowerCase().contains('launcher')
                ? 'ภาพนี้มาจากหน้า Home/Launcher (${capture.packageName!}) ถ้าช่องค้นหาเปิดแอปอื่น ให้เปิดแอปนั้นและแตะช่องพิมพ์ก่อนกลับมาเข้าคิวข้อความ'
                : 'ภาพจาก ${capture.packageName!}. คำสั่งจะเข้าคิวแล้วสลับไปแอปเป้าหมายอัตโนมัติ',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (capture.packageName != null) ...[
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
          TextField(
            controller: actions.textController,
            maxLength: 2000,
            onChanged: (_) => onTextChanged(),
            decoration: const InputDecoration(
              labelText: 'ข้อความสำหรับช่องที่โฟกัส',
              helperText: 'แตะช่องข้อความในแอปที่ต้องการทดสอบก่อนกลับมา MobilePilot แล้วใส่ข้อความตัวอย่างและเข้าคิว MobilePilot จะกลับไปแอปล่าสุดให้อัตโนมัติ',
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
