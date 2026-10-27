import 'package:flutter/material.dart';

import '../controllers/command_sequence_controller.dart';

class CommandSequenceSection extends StatelessWidget {
  const CommandSequenceSection({super.key, required this.controller});
  final CommandSequenceController controller;

  @override
  Widget build(BuildContext context) => Card(
    child: ExpansionTile(
      title: const Text('ทดสอบคำสั่งต่อเนื่อง'),
      subtitle: Text(controller.status),
      childrenPadding: const EdgeInsets.all(16),
      children: [
        const Text(
          'เปิดแอป → รอ UI → อ่านรายการ → แตะหนึ่งครั้ง → รอ UI ใหม่ แต่ละช่วงรอไม่เกิน 15 วินาที',
        ),
        DropdownButtonFormField<String>(
          initialValue: controller.selector,
          decoration: const InputDecoration(
            labelText: 'ค้นหาทั้ง 3 เงื่อนไขจาก',
          ),
          items: const [
            DropdownMenuItem(value: 'text', child: Text('ข้อความ')),
            DropdownMenuItem(
              value: 'contentDescription',
              child: Text('คำอธิบายองค์ประกอบ'),
            ),
            DropdownMenuItem(
              value: 'resourceId',
              child: Text('รหัสองค์ประกอบ (Resource ID)'),
            ),
          ],
          onChanged: controller.isRunning
              ? null
              : (value) {
                  if (value != null) controller.setSelector(value);
                },
        ),
        for (final entry in [
          (controller.beforeController, 'UI ที่ต้องพบก่อนแตะ'),
          (controller.buttonController, 'ปุ่มที่จะกดหนึ่งครั้ง'),
          (controller.afterController, 'UI ใหม่ที่ต้องพบหลังแตะ'),
        ])
          TextField(
            controller: entry.$1,
            enabled: !controller.isRunning,
            maxLength: 200,
            decoration: InputDecoration(labelText: entry.$2),
          ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: controller.isRunning ? null : controller.start,
              icon: const Icon(Icons.play_arrow),
              label: const Text('เริ่มชุดทดสอบ'),
            ),
            OutlinedButton.icon(
              onPressed: controller.isRunning ? controller.stop : null,
              icon: const Icon(Icons.stop),
              label: const Text('หยุดชุดทดสอบ'),
            ),
          ],
        ),
        for (final step in controller.steps)
          Align(alignment: Alignment.centerLeft, child: Text(step)),
      ],
    ),
  );
}
