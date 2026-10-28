import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'device_controller.dart';

class WaitForUiController extends DeviceController {
  WaitForUiController(super.feedback);

  final valueController = TextEditingController();
  String selector = 'text';
  String condition = 'present';
  void setCondition(String value) => update(() => condition = value);
  int timeoutSeconds = 15;
  bool isWaiting = false;
  bool scrollToFind = false;
  String direction = 'down';
  int maxScrolls = 10;
  String distance = 'long';
  void setDistance(String value) => update(() => distance = value);

  void setScrollToFind(bool value) => update(() {
    scrollToFind = value;
    if (value) condition = 'present';
  });
  void setDirection(String value) => update(() => direction = value);
  void setMaxScrolls(int value) => update(() => maxScrolls = value);
  String? message;
  String? _activeId;
  static int _nextId = 0;

  void setSelector(String value) => update(() => selector = value);
  void setTimeout(int value) => update(() => timeoutSeconds = value);

  Future<void> start() async {
    if (!mounted || isWaiting) return;
    final target = feedback.targetPackage;
    final value = valueController.text.trim();
    if (target == null || value.isEmpty || value.length > 200) {
      update(
        () => message = 'เลือกแอปเป้าหมายและใส่ค่าที่รอ 1–200 ตัวอักษรก่อน',
      );
      return;
    }
    if (condition == 'textChanged' && selector == 'text') {
      update(
        () => message =
            'รอข้อความเปลี่ยนต้องเลือก Resource ID หรือคำอธิบายที่ไม่ซ้ำก่อน',
      );
      return;
    }
    final scrolling = scrollToFind;
    final disappearing = condition == 'disappeared';
    final id = 'ui-wait-${DateTime.now().microsecondsSinceEpoch}-${++_nextId}';
    _activeId = id;
    update(() {
      isWaiting = true;
      message =
          'กำลังรอ “$value” ไม่เกิน $timeoutSeconds วินาที กดเปิดแอปเป้าหมายได้';
    });
    try {
      final request = scrolling
          ? platform.scrollUntilUi(
              requestId: id,
              targetPackage: target,
              selector: selector,
              value: value,
              timeoutMs: timeoutSeconds * 1000,
              direction: direction,
              maxScrolls: maxScrolls,
              distance: distance,
            )
          : platform.waitForUi(
              requestId: id,
              targetPackage: target,
              selector: selector,
              value: value,
              timeoutMs: timeoutSeconds * 1000,
              condition: condition,
            );
      final response = await request.timeout(
        Duration(seconds: timeoutSeconds + 2),
      );
      if (!mounted || _activeId != id || feedback.targetPackage != target) {
        return;
      }
      final code = response?['code'];
      final detail = response?['message'];
      if (code is! String || detail is! String) {
        throw const FormatException('ผลการรอ UI ไม่สมบูรณ์');
      }
      update(
        () => message = switch (code) {
          'UI_FOUND' =>
            scrolling
                ? 'พบ “$value” แล้ว · เลื่อน ${response?['scrollCount'] ?? 0} ครั้ง (ยังไม่ได้แตะ)'
                : 'พบ “$value” ในแอปเป้าหมายแล้ว',
          'UI_ENABLED' => 'พบปุ่ม “$value” ที่พร้อมกดแล้ว (ยังไม่ได้แตะ)',
          'UI_TEXT_CHANGED' =>
            'ข้อความของ “$value” เปลี่ยนแล้ว: ${response?['beforeText']} → ${(response?['element'] as Map?)?['text']}',
          'UI_DISAPPEARED' =>
            'พบ “$value” แล้ว และรายการหายไปต่อเนื่องอย่างน้อย 0.5 วินาที',
          'UI_TIMEOUT' =>
            disappearing
                ? 'หมดเวลา ยังยืนยันไม่ได้ว่าพบ “$value” แล้วหายไป'
                : 'หมดเวลารอ ไม่พบ “$value” ในแอปเป้าหมาย',
          'UI_CANCELLED' => 'ยกเลิกการรอ UI แล้ว',
          _ => '$detail · เลื่อน ${response?['scrollCount'] ?? 0} ครั้ง',
        },
      );
    } on TimeoutException {
      if (mounted && _activeId == id) {
        update(
          () => message =
              'ไม่ได้รับผลจาก Android ภายในเวลาที่กำหนด ยกเลิกคำขอแล้ว',
        );
      }
      unawaited(_cancelNative(id));
    } on PlatformException catch (error) {
      if (mounted && _activeId == id) {
        update(() => message = error.message ?? error.code);
      }
    } on MissingPluginException {
      if (mounted && _activeId == id) {
        update(() => message = 'ต้อง build Android ใหม่ก่อนใช้การรอ UI');
      }
    } on FormatException catch (error) {
      if (mounted && _activeId == id) update(() => message = error.message);
    } finally {
      if (mounted && _activeId == id) {
        _activeId = null;
        update(() => isWaiting = false);
      }
    }
  }

  Future<void> cancel() async {
    final id = _activeId;
    if (id == null) return;
    try {
      await platform.cancelUiWait(id).timeout(const Duration(seconds: 2));
      if (mounted && _activeId == id) {
        _activeId = null;
        update(() {
          isWaiting = false;
          message = 'ยกเลิกการรอ UI แล้ว';
        });
      }
    } on PlatformException catch (error) {
      if (mounted && _activeId == id) {
        update(() => message = error.message ?? error.code);
      }
    } on MissingPluginException {
      if (mounted && _activeId == id) {
        update(() => message = 'ไม่พบช่องทางยกเลิกการรอ UI');
      }
    } on TimeoutException {
      if (mounted && _activeId == id) {
        update(
          () =>
              message = 'ยังยืนยันการยกเลิกไม่ได้ Android จะหยุดรอเมื่อหมดเวลา',
        );
      }
    }
  }

  Future<void> _cancelNative(String id) async {
    try {
      await platform.cancelUiWait(id).timeout(const Duration(seconds: 2));
    } on PlatformException {
      // Native wait also has its own deadline.
    } on MissingPluginException {
      // The disposed page cannot act on an unavailable channel.
    } on TimeoutException {
      // Android still enforces the original deadline if cancellation cannot respond.
    }
  }

  void targetChanged() {
    final id = _activeId;
    _activeId = null;
    if (id != null) unawaited(_cancelNative(id));
    update(() {
      isWaiting = false;
      message = null;
    });
  }

  @override
  void dispose() {
    final id = _activeId;
    _activeId = null;
    if (id != null) unawaited(_cancelNative(id));
    valueController.dispose();
    super.dispose();
  }
}
