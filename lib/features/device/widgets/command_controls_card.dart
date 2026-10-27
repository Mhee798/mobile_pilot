import 'package:flutter/material.dart';

import '../controllers/app_launcher_controller.dart';
import '../controllers/device_controller.dart';
import '../controllers/floating_controls_controller.dart';
import '../controllers/screen_capture_controller.dart';
import '../controllers/settings_test_controller.dart';
import '../controllers/ui_tree_controller.dart';
import 'app_launcher_section.dart';
import 'wait_for_ui_section.dart';
import '../controllers/wait_for_ui_controller.dart';
import 'floating_controls_toggle.dart';

class CommandControlsCard extends StatelessWidget {
  const CommandControlsCard({
    super.key,
    required this.launcher,
    required this.uiWait,
    required this.floating,
    required this.capture,
    required this.settings,
    required this.tree,
    required this.feedback,
    required this.tapTestCount,
    required this.onTestTap,
  });

  final AppLauncherController launcher;
  final WaitForUiController uiWait;
  final FloatingControlsController floating;
  final ScreenCaptureController capture;
  final SettingsTestController settings;
  final UiTreeController tree;
  final CommandFeedback feedback;
  final int tapTestCount;
  final VoidCallback onTestTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FloatingControlsToggle(floating: floating),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: floating.isUpdating
                      ? null
                      : () => floating.navigate('home'),
                  icon: const Icon(Icons.home_outlined),
                  label: const Text('หน้าหลัก Home'),
                ),
                OutlinedButton.icon(
                  onPressed: floating.isUpdating
                      ? null
                      : () => floating.navigate('recents'),
                  icon: const Icon(Icons.recent_actors_outlined),
                  label: const Text('แอปล่าสุด Recents'),
                ),
              ],
            ),
            const Text(
              'นำทางทันทีและยกเลิกคิวที่รออยู่ คำสั่งที่ส่งไปแล้วอาจยังทำงานต่อ',
            ),
            const Divider(),
            AppLauncherSection(launcher: launcher),
            Text(launcher.targetStatus),
            if (launcher.selectedPackage != null) ...[
              Text(
                'คำสั่งจะทำกับ ${launcher.selectedLabel} เท่านั้น · ไม่เปิดแอปให้อัตโนมัติ',
              ),
              OutlinedButton.icon(
                onPressed: launcher.isLaunching || launcher.isSelecting
                    ? null
                    : launcher.launchSelected,
                icon: const Icon(Icons.open_in_new),
                label: Text(
                  launcher.isLaunching
                      ? 'กำลังเปิดและรอแอปพร้อม…'
                      : 'เปิดแอปเป้าหมาย',
                ),
              ),
            ],
            const Divider(),
            WaitForUiSection(controller: uiWait),
            const Divider(),
            FilledButton.icon(
              onPressed: tree.isReading ? null : tree.read,
              icon: tree.isReading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.account_tree_outlined),
              label: Text(
                feedback.targetPackage == null
                    ? 'อ่าน UI tree ของหน้าจอนี้'
                    : 'อ่าน UI tree ของแอปเป้าหมาย',
              ),
            ),
            OutlinedButton.icon(
              onPressed: capture.isCapturing || capture.isWaiting
                  ? null
                  : capture.capture,
              icon: capture.isCapturing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.image_outlined),
              label: Text(
                capture.isWaiting
                    ? 'รอภาพจากแอปเป้าหมาย…'
                    : 'จับภาพแอปอื่นเพื่อเลือกพิกัด',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onTestTap,
              icon: const Icon(Icons.touch_app_outlined),
              label: const Text('ปุ่มทดสอบการแตะ'),
            ),
            Text('ผลทดสอบ: ถูกแตะ $tapTestCount ครั้ง'),
            const SizedBox(height: 12),
            TextField(
              controller: tree.targetController,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'ข้อความเป้าหมายที่จะกด',
                hintText: 'เช่น แบตเตอรี่ หรือ Battery',
                helperText: 'Settings test ใช้ข้อความที่เห็นจริงในหน้า Android Settings',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: feedback.isTapping ? null : tree.tapByText,
              icon: feedback.isTapping
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.touch_app_outlined),
              label: const Text('แตะ element ตามข้อความ'),
            ),
            FilledButton.tonalIcon(
              onPressed: settings.isStarting ? null : settings.run,
              icon: settings.isStarting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.settings_outlined),
              label: const Text('ทดสอบแตะใน Android Settings'),
            ),
            Text(
              'การทดสอบนี้จำกัดอยู่ใน Android Settings แตะเป้าหมายเดียว แล้วตรวจว่า UI tree เปลี่ยนหรือไม่ กลับมาที่ MobilePilot เพื่อดูผล',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (settings.message != null) ...[
              const SizedBox(height: 8),
              Text(settings.message!),
            ],
            if (feedback.message != null) ...[
              const SizedBox(height: 8),
              Text(feedback.message!, style: TextStyle(color: colors.primary)),
            ],
            if (tree.showGestureFallback) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: feedback.isTapping ? null : tree.tapWithGesture,
                icon: const Icon(Icons.gesture),
                label: const Text('ลองแตะตำแหน่งด้วย Gesture'),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              'การส่งคำสั่งแตะสำเร็จยังไม่ยืนยันว่าหน้าจอเปลี่ยนตามต้องการ',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
