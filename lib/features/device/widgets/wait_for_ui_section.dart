import 'package:flutter/material.dart';

import '../controllers/wait_for_ui_controller.dart';

class WaitForUiSection extends StatelessWidget {
  const WaitForUiSection({super.key, required this.controller});
  final WaitForUiController controller;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('รอ UI / เลื่อนจนเจอรายการ'),
      subtitle: Text(
        controller.message ?? 'เลือกแอปด้านบน แล้วระบุสิ่งที่ต้องการรอ',
      ),
      children: [
        const Text(
          'เลือกแอปเป้าหมายด้านบน ระบุรายการ แล้วเริ่มคำสั่งและเปิดแอปเป้าหมายเอง ไม่แตะรายการให้อัตโนมัติ',
        ),
        DropdownButtonFormField<String>(
          key: ValueKey(controller.condition),
          initialValue: controller.condition,
          decoration: const InputDecoration(labelText: 'เงื่อนไขการรอ'),
          items: const [
            DropdownMenuItem(value: 'present', child: Text('รอให้พบรายการ')),
            DropdownMenuItem(value: 'enabled', child: Text('รอปุ่มพร้อมกด')),
            DropdownMenuItem(
              value: 'textChanged',
              child: Text('รอข้อความของรายการเปลี่ยน'),
            ),
            DropdownMenuItem(
              value: 'disappeared',
              child: Text('รอรายการหาย · ต้องพบก่อน'),
            ),
          ],
          onChanged: controller.isWaiting || controller.scrollToFind
              ? null
              : (value) {
                  if (value != null) controller.setCondition(value);
                },
        ),
        if (controller.condition == 'enabled')
          const Text(
            'ต้องเป็นปุ่มที่มองเห็น เปิดใช้งาน และแตะได้ต่อเนื่อง 0.5 วินาที · ยังไม่กดปุ่ม',
          ),
        if (controller.condition == 'textChanged')
          const Text(
            'ใช้ Resource ID หรือคำอธิบายที่ไม่ซ้ำ · บันทึกข้อความแรก แล้วรอค่าใหม่คงอยู่ 0.5 วินาที · รายการหายไม่นับว่าข้อความเปลี่ยน',
          ),
        if (controller.condition == 'disappeared')
          const Text(
            'ต้องพบรายการก่อน แล้วไม่พบต่อเนื่อง 0.5 วินาทีในแอปเดิม · ไม่ยืนยันว่าการโหลดหรือธุรกรรมสำเร็จ',
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('เลื่อนจนเจอรายการ'),
          subtitle: const Text(
            'รอแอปเป้าหมายด้านหน้า 1 วินาที เลื่อนทีละรอบโดยไม่แตะรายการ',
          ),
          value: controller.scrollToFind,
          onChanged: controller.isWaiting ? null : controller.setScrollToFind,
        ),
        if (controller.scrollToFind) ...[
          const Text(
            'ใช้ส่วนที่เลื่อนได้อันแรกใน UI tree · ข้อความต้องตรงทั้งรายการ · หากแอปไม่เปิดเผย UI จะค้นหาไม่ได้',
          ),
          DropdownButtonFormField<String>(
            initialValue: controller.direction,
            decoration: const InputDecoration(labelText: 'ทิศทาง'),
            items: const [
              DropdownMenuItem(
                value: 'down',
                child: Text('เลื่อนดูรายการด้านล่าง'),
              ),
              DropdownMenuItem(
                value: 'up',
                child: Text('เลื่อนดูรายการด้านบน'),
              ),
            ],
            onChanged: controller.isWaiting
                ? null
                : (value) {
                    if (value != null) controller.setDirection(value);
                  },
          ),
          DropdownButtonFormField<String>(
            initialValue: controller.distance,
            decoration: const InputDecoration(labelText: 'ระยะเลื่อนต่อครั้ง'),
            items: const [
              DropdownMenuItem(
                value: 'long',
                child: Text('ปัดยาว · 80% ของพื้นที่รายการ'),
              ),
              DropdownMenuItem(
                value: 'short',
                child: Text('ปัดสั้น · 40% ของพื้นที่รายการ'),
              ),
              DropdownMenuItem(
                value: 'app',
                child: Text('ให้แอปกำหนดระยะ (แบบเดิม)'),
              ),
            ],
            onChanged: controller.isWaiting
                ? null
                : (value) {
                    if (value != null) controller.setDistance(value);
                  },
          ),
          const Text(
            'ระยะนิ้วปัดไม่ใช่ระยะเนื้อหาที่รับประกัน · เวลาสูงสุดนับรวมเวลาสลับแอปด้วย',
          ),
          DropdownButtonFormField<int>(
            initialValue: controller.maxScrolls,
            decoration: const InputDecoration(labelText: 'จำนวนครั้งสูงสุด'),
            items: [
              for (final count in [3, 5, 10, 20, 40])
                DropdownMenuItem(value: count, child: Text('$count ครั้ง')),
            ],
            onChanged: controller.isWaiting
                ? null
                : (value) {
                    if (value != null) controller.setMaxScrolls(value);
                  },
          ),
        ],
        DropdownButtonFormField<String>(
          initialValue: controller.selector,
          decoration: const InputDecoration(labelText: 'ค้นหาจาก'),
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
          onChanged: controller.isWaiting
              ? null
              : (value) {
                  if (value != null) controller.setSelector(value);
                },
        ),
        TextField(
          controller: controller.valueController,
          enabled: !controller.isWaiting,
          maxLength: 200,
          decoration: const InputDecoration(
            labelText: 'ค่าที่ต้องการรอ',
            hintText: 'เช่น เกี่ยวกับโทรศัพท์ หรือ Search',
          ),
        ),
        DropdownButtonFormField<int>(
          initialValue: controller.timeoutSeconds,
          decoration: const InputDecoration(labelText: 'เวลารอสูงสุด'),
          items: [
            for (final seconds in [5, 15, 30, 60])
              DropdownMenuItem(value: seconds, child: Text('$seconds วินาที')),
          ],
          onChanged: controller.isWaiting
              ? null
              : (value) {
                  if (value != null) controller.setTimeout(value);
                },
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: controller.isWaiting ? null : controller.start,
              icon: const Icon(Icons.hourglass_top),
              label: Text(
                controller.scrollToFind ? 'เริ่มเลื่อนค้นหา' : 'เริ่มรอ UI',
              ),
            ),
            OutlinedButton.icon(
              onPressed: controller.isWaiting ? controller.cancel : null,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('ยกเลิกการรอ UI'),
            ),
          ],
        ),
      ],
    );
  }
}
