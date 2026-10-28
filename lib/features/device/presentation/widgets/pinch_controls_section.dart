import 'package:flutter/material.dart';

import '../controllers/pinch_controller.dart';

class PinchControlsSection extends StatelessWidget {
  const PinchControlsSection({
    super.key,
    required this.controller,
    required this.busy,
  });
  final PinchController controller;
  final bool busy;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: const Text('สองนิ้วขยาย/ย่อ'),
    subtitle: const Text(
      'ใช้หมุดแดงเป็นจุดกึ่งกลาง เลือกพื้นที่ที่แอปรองรับการซูม',
    ),
    children: [
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton(
            onPressed: busy ? null : controller.strongExpand,
            child: const Text('ตั้งค่าขยายมาก'),
          ),
          OutlinedButton(
            onPressed: busy ? null : controller.strongShrink,
            child: const Text('ตั้งค่าย่อมาก'),
          ),
        ],
      ),
      const Text(
        'ขยายมาก: ระยะนิ้ว 20% → 80% · ย่อมาก: 80% → 20% ใช้เวลา 1 วินาที',
      ),
      OutlinedButton.icon(
        onPressed: busy ? null : controller.chooseCenter,
        icon: const Icon(Icons.center_focus_strong),
        label: const Text('เลือกจุดกึ่งกลางบนภาพ'),
      ),
      DropdownButtonFormField<double>(
        key: ValueKey('pinch-scale-${controller.scale}'),
        initialValue: controller.scale,
        decoration: const InputDecoration(labelText: 'อัตราการกาง/หุบนิ้ว'),
        items: const [
          DropdownMenuItem(value: 4.0, child: Text('กางนิ้ว 4 เท่า (ขยายมาก)')),
          DropdownMenuItem(value: 3.0, child: Text('กางนิ้ว 3 เท่า')),
          DropdownMenuItem(
            value: 0.25,
            child: Text('หุบนิ้วเหลือ 0.25 (ย่อมาก)'),
          ),
          DropdownMenuItem(value: 2.0, child: Text('กางนิ้ว 2 เท่า (ขยาย)')),
          DropdownMenuItem(value: 1.5, child: Text('กางนิ้ว 1.5 เท่า (ขยาย)')),
          DropdownMenuItem(value: 0.5, child: Text('หุบนิ้วเหลือ 0.5 (ย่อ)')),
          DropdownMenuItem(value: 0.75, child: Text('หุบนิ้วเหลือ 0.75 (ย่อ)')),
        ],
        onChanged: busy
            ? null
            : (v) {
                if (v != null) controller.setScale(v);
              },
      ),
      DropdownButtonFormField<double>(
        key: ValueKey('pinch-span-${controller.startSpan}'),
        initialValue: controller.startSpan,
        decoration: const InputDecoration(
          labelText: 'ระยะนิ้วเริ่มต้น (% ของด้านสั้นจอ)',
        ),
        items: [
          for (final v in [.15, .2, .25, .35, .5, .7, .8])
            DropdownMenuItem(value: v, child: Text('${(v * 100).round()}%')),
        ],
        onChanged: busy
            ? null
            : (v) {
                if (v != null) controller.setSpan(v);
              },
      ),
      DropdownButtonFormField<String>(
        initialValue: controller.axis,
        decoration: const InputDecoration(labelText: 'แนวการวางนิ้ว'),
        items: const [
          DropdownMenuItem(value: 'horizontal', child: Text('แนวนอน')),
          DropdownMenuItem(value: 'vertical', child: Text('แนวตั้ง')),
        ],
        onChanged: busy
            ? null
            : (v) {
                if (v != null) controller.setAxis(v);
              },
      ),
      DropdownButtonFormField<int>(
        key: ValueKey('pinch-duration-${controller.durationMs}'),
        initialValue: controller.durationMs,
        decoration: const InputDecoration(labelText: 'เวลาขยาย/ย่อ'),
        items: [
          for (final ms in [100, 250, 500, 750, 1000, 1500, 3000])
            DropdownMenuItem(value: ms, child: Text('${ms / 1000} วินาที')),
        ],
        onChanged: busy
            ? null
            : (v) {
                if (v != null) controller.setDuration(v);
              },
      ),
      FilledButton.tonalIcon(
        onPressed: busy ? null : controller.queue,
        icon: const Icon(Icons.pinch),
        label: const Text('เตรียมซูมสองนิ้ว'),
      ),
    ],
  );
}
