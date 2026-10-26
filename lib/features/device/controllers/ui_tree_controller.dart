import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'device_controller.dart';

class UiTreeController extends DeviceController {
  UiTreeController(super.feedback);

  final targetController = TextEditingController();
  List<Map<String, dynamic>> elements = [];
  bool isReading = false;
  bool showGestureFallback = false;

  Future<void> read() async {
    update(() {
      isReading = true;
      feedback.message = null;
    });
    try {
      final fetchedElements = await platform.getUiTree();
      if (!mounted) return;
      update(() {
        elements = fetchedElements;
        feedback.message =
            'อ่านได้ ${fetchedElements.length} รายการจากหน้าจอปัจจุบัน';
      });
    } on PlatformException catch (error) {
      if (mounted) update(() => feedback.message = error.message ?? error.code);
    } on MissingPluginException {
      if (mounted) {
        update(() => feedback.message = 'ไม่พบ Accessibility command channel');
      }
    } finally {
      if (mounted) update(() => isReading = false);
    }
  }

  Future<void> tapByText() async {
    final target = targetController.text.trim();
    if (target.isEmpty) {
      update(() => feedback.message = 'ใส่ข้อความเป้าหมายก่อน');
      return;
    }

    update(() {
      feedback.isTapping = true;
      feedback.message = null;
      showGestureFallback = false;
    });
    final beforeSignature = treeSignature(elements);
    try {
      final tapResponse = await platform.tapElementByText(target);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final fetchedElements = await platform.getUiTree();
      if (!mounted) return;
      final treeChanged =
          elements.isNotEmpty &&
          beforeSignature != treeSignature(fetchedElements);
      final actionMessage =
          tapResponse?['message'] as String? ?? 'Android รับคำสั่งแตะแล้ว';
      update(() {
        elements = fetchedElements;
        showGestureFallback = !treeChanged;
        feedback.message = treeChanged
            ? '$actionMessage · UI tree เปลี่ยนแล้ว'
            : '$actionMessage · UI tree ไม่เปลี่ยน หากเป็นปุ่มทดสอบ ลอง Gesture แยกได้';
      });
    } on PlatformException catch (error) {
      if (mounted) update(() => feedback.message = error.message ?? error.code);
    } on MissingPluginException {
      if (mounted) {
        update(() => feedback.message = 'ไม่พบ Accessibility command channel');
      }
    } finally {
      if (mounted) update(() => feedback.isTapping = false);
    }
  }

  Future<void> tapWithGesture() async {
    final target = targetController.text.trim();
    if (target.isEmpty) return;
    final beforeSignature = treeSignature(elements);
    update(() {
      feedback.isTapping = true;
      showGestureFallback = false;
      feedback.message = null;
    });
    try {
      final tapResponse = await platform.tapElementByTextWithGesture(target);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final fetchedElements = await platform.getUiTree();
      if (!mounted) return;
      final treeChanged =
          elements.isNotEmpty &&
          beforeSignature != treeSignature(fetchedElements);
      final actionMessage =
          tapResponse?['message'] as String? ?? 'ส่ง Gesture แล้ว';
      update(() {
        elements = fetchedElements;
        feedback.message = treeChanged
            ? '$actionMessage · UI tree เปลี่ยนแล้ว'
            : '$actionMessage · UI tree ไม่เปลี่ยน';
      });
    } on PlatformException catch (error) {
      if (mounted) update(() => feedback.message = error.message ?? error.code);
    } on MissingPluginException {
      if (mounted) {
        update(() => feedback.message = 'ไม่พบ Accessibility command channel');
      }
    } finally {
      if (mounted) update(() => feedback.isTapping = false);
    }
  }

  String treeSignature(List<Map<String, dynamic>> elements) {
    return elements
        .map(
          (element) =>
              '${element['text']}|${element['contentDescription']}|${element['resourceId']}|${element['clickable']}|${element['bounds']}',
        )
        .join('\n');
  }

  @override
  void dispose() {
    targetController.dispose();
    super.dispose();
  }
}
