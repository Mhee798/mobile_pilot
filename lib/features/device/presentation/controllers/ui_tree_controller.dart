import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'device_controller.dart';

class UiTreeController extends DeviceController {
  UiTreeController(super.feedback);

  final targetController = TextEditingController();
  final inputTextController = TextEditingController();
  List<Map<String, dynamic>> elements = [];
  bool isReading = false;
  bool showGestureFallback = false;

  bool canTapReference(Map<String, dynamic> element) =>
      !feedback.isTapping &&
      feedback.targetPackage != null &&
      element['packageName'] == feedback.targetPackage &&
      element['screenId'] is String &&
      element['nodeId'] is String &&
      element['clickable'] == true &&
      element['editable'] != true &&
      element['visible'] == true &&
      element['enabled'] == true;

  bool canEditReference(Map<String, dynamic> element) =>
      !feedback.isTapping &&
      feedback.targetPackage != null &&
      element['packageName'] == feedback.targetPackage &&
      element['screenId'] is String &&
      element['nodeId'] is String &&
      element['editable'] == true &&
      element['password'] != true &&
      element['enabled'] == true &&
      element['visible'] == true;

  Future<void> editReference(
    Map<String, dynamic> element,
    String action,
  ) async {
    if (!canEditReference(element)) return;
    final target = feedback.targetPackage!;
    update(() {
      feedback.isTapping = true;
      feedback.message = 'รอแอปเป้าหมาย กดเปิดแอปเป้าหมายภายใน 10 วินาที';
    });
    try {
      final response = await platform.editElementById(
        screenId: element['screenId'] as String,
        nodeId: element['nodeId'] as String,
        targetPackage: target,
        action: action,
        text: inputTextController.text,
      );
      if (mounted && feedback.targetPackage == target) {
        update(() {
          elements = [];
          feedback.message = response?['message'] as String?;
        });
      }
    } on PlatformException catch (error) {
      if (mounted && feedback.targetPackage == target) {
        update(() {
          if (error.code == 'STALE_SCREEN') elements = [];
          feedback.message = error.message ?? error.code;
        });
      }
    } on MissingPluginException {
      if (mounted) {
        update(() => feedback.message = 'ต้อง build Android ใหม่ก่อน');
      }
    } finally {
      if (mounted) update(() => feedback.isTapping = false);
    }
  }

  Future<void> tapReference(Map<String, dynamic> element) async {
    if (!canTapReference(element)) return;
    final targetPackage = element['packageName'] as String;
    update(() {
      feedback.isTapping = true;
      feedback.message = 'รอแอปเป้าหมายเพื่อแตะรายการที่เลือก กดเปิดแอปเป้าหมายภายใน 10 วินาที';
    });
    try {
      final response = await platform.tapElementById(
        screenId: element['screenId'] as String,
        nodeId: element['nodeId'] as String,
        targetPackage: targetPackage,
      );
      if (!mounted || feedback.targetPackage != targetPackage) return;
      update(() {
        elements = [];
        showGestureFallback = false;
        feedback.message =
            response?['message'] as String? ??
            'ส่งคำสั่งแตะแล้ว กรุณาอ่าน UI tree ใหม่';
      });
    } on PlatformException catch (error) {
      if (mounted && feedback.targetPackage == targetPackage) {
        update(() {
          if (error.code == 'STALE_SCREEN') elements = [];
          feedback.message = error.message ?? error.code;
        });
      }
    } on MissingPluginException {
      if (mounted) {
        update(
          () =>
              feedback.message = 'ต้อง build Android ใหม่ก่อนแตะด้วยรหัสรายการ',
        );
      }
    } finally {
      if (mounted) update(() => feedback.isTapping = false);
    }
  }

  Future<void> read() async {
    final targetPackage = feedback.targetPackage;
    update(() {
      isReading = true;
      feedback.message = feedback.targetPackage == null ? null : 'รอแอปเป้าหมายอยู่ด้านหน้า (ไม่เกิน 10 วินาที) กดเปิดแอปเป้าหมายได้';
    });
    try {
      final fetchedElements = await platform.getUiTree(
        targetPackage: targetPackage,
      );
      if (!mounted || feedback.targetPackage != targetPackage) return;
      update(() {
        elements = fetchedElements;
        feedback.message =
            'อ่านได้ ${fetchedElements.length} รายการจากหน้าจอปัจจุบัน';
      });
    } on PlatformException catch (error) {
      if (mounted && feedback.targetPackage == targetPackage) {
        update(() => feedback.message = error.message ?? error.code);
      }
    } on MissingPluginException {
      if (mounted && feedback.targetPackage == targetPackage) {
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
      feedback.message = feedback.targetPackage == null ? null : 'รอแอปเป้าหมายอยู่ด้านหน้า (ไม่เกิน 10 วินาที) กดเปิดแอปเป้าหมายได้';
      showGestureFallback = false;
    });
    final targetPackage = feedback.targetPackage;
    final beforeSignature = treeSignature(elements);
    try {
      final tapResponse = await platform.tapElementByText(
        target,
        targetPackage: targetPackage,
      );
      if (!mounted || feedback.targetPackage != targetPackage) return;
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted || feedback.targetPackage != targetPackage) return;
      final fetchedElements = await platform.getUiTree(
        targetPackage: targetPackage,
      );
      if (!mounted || feedback.targetPackage != targetPackage) return;
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
      if (mounted && feedback.targetPackage == targetPackage) {
        update(() => feedback.message = error.message ?? error.code);
      }
    } on MissingPluginException {
      if (mounted && feedback.targetPackage == targetPackage) {
        update(() => feedback.message = 'ไม่พบ Accessibility command channel');
      }
    } finally {
      if (mounted) update(() => feedback.isTapping = false);
    }
  }

  Future<void> tapWithGesture() async {
    final target = targetController.text.trim();
    if (target.isEmpty) return;
    final targetPackage = feedback.targetPackage;
    final beforeSignature = treeSignature(elements);
    update(() {
      feedback.isTapping = true;
      showGestureFallback = false;
      feedback.message = feedback.targetPackage == null ? null : 'รอแอปเป้าหมายอยู่ด้านหน้า (ไม่เกิน 10 วินาที) กดเปิดแอปเป้าหมายได้';
    });
    try {
      final tapResponse = await platform.tapElementByTextWithGesture(
        target,
        targetPackage: targetPackage,
      );
      if (!mounted || feedback.targetPackage != targetPackage) return;
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted || feedback.targetPackage != targetPackage) return;
      final fetchedElements = await platform.getUiTree(
        targetPackage: targetPackage,
      );
      if (!mounted || feedback.targetPackage != targetPackage) return;
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
      if (mounted && feedback.targetPackage == targetPackage) {
        update(() => feedback.message = error.message ?? error.code);
      }
    } on MissingPluginException {
      if (mounted && feedback.targetPackage == targetPackage) {
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
              '${element['text']}|${element['contentDescription']}|${element['resourceId']}|${element['clickable']}|${element['bounds']}|${element['checked']}|${element['selected']}',
        )
        .join('\n');
  }

  @override
  void dispose() {
    targetController.dispose();
    inputTextController.dispose();
    super.dispose();
  }
}
