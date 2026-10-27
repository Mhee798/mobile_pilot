import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'device_controller.dart';

class _SequenceCancelled implements Exception {}

class CommandSequenceController extends DeviceController {
  CommandSequenceController(super.feedback);

  final beforeController = TextEditingController();
  final buttonController = TextEditingController();
  final afterController = TextEditingController();
  String selector = 'text';
  bool isRunning = false;
  String status = 'ยังไม่ได้เริ่มชุดทดสอบ';
  final List<String> steps = [];
  String? _runId;
  String? _runTarget;
  static int _nextId = 0;

  void setSelector(String value) => update(() => selector = value);

  void _check(String id) {
    if (!mounted || _runId != id || feedback.targetPackage != _runTarget) {
      throw _SequenceCancelled();
    }
  }

  bool _matches(Map<String, dynamic> node, String field, String value) {
    final actual = node[field] as String?;
    return field == 'resourceId'
        ? actual == value
        : actual?.trim().toLowerCase() == value.toLowerCase();
  }

  void _step(String label) => update(() {
    status = label;
    steps.add(label);
  });

  Future<void> start() async {
    if (!mounted || isRunning) return;
    final target = feedback.targetPackage;
    final before = beforeController.text.trim();
    final button = buttonController.text.trim();
    final after = afterController.text.trim();
    final field = selector;
    if (target == null ||
        [before, button, after].any((v) => v.isEmpty || v.length > 200)) {
      update(
        () => status = 'เลือกแอปเป้าหมาย และกรอกเงื่อนไขทั้ง 3 ช่อง (ไม่เกิน 200 ตัวอักษร)',
      );
      return;
    }
    final id = 'sequence-${DateTime.now().microsecondsSinceEpoch}-${++_nextId}';
    _runId = id;
    _runTarget = target;
    update(() {
      isRunning = true;
      steps.clear();
      status = 'กำลังเริ่มชุดทดสอบ';
    });
    var completed = false;
    try {
      await platform
          .beginCommandSession(id, target)
          .timeout(const Duration(seconds: 2));
      _check(id);
      _step('1/5 เปิดแอปเป้าหมาย');
      final launch = await platform
          .launchApp(target, runId: id)
          .timeout(const Duration(seconds: 12));
      _check(id);
      if (launch?['code'] != 'TARGET_READY') {
        throw const FormatException('ยังยืนยันว่าแอปเปิดพร้อมไม่ได้');
      }
      _step('2/5 รอ UI ก่อนแตะ');
      await _wait(id, target, field, before, 'before');
      _check(id);
      _step('3/5 อ่าน UI และเลือกรายการ');
      final nodes = await platform
          .getUiTree(targetPackage: target, runId: id)
          .timeout(const Duration(seconds: 12));
      _check(id);
      if (nodes.any((n) => n['visible'] == true && _matches(n, field, after))) {
        throw const FormatException(
          'พบเงื่อนไขผลลัพธ์อยู่ก่อนแตะแล้ว กรุณาเลือกผลลัพธ์ที่แยกจากหน้าก่อนแตะ',
        );
      }
      final candidates = nodes
          .where(
            (n) =>
                n['visible'] == true &&
                n['enabled'] == true &&
                n['clickable'] == true &&
                n['editable'] != true &&
                _matches(n, field, button),
          )
          .toList();
      if (candidates.length != 1) {
        throw FormatException(
          candidates.isEmpty
              ? 'ไม่พบปุ่มที่พร้อมแตะตรงกับเงื่อนไข'
              : 'พบปุ่มตรงกันหลายรายการ กรุณาใช้รหัสองค์ประกอบที่แยกได้',
        );
      }
      final node = candidates.single;
      if (node['screenId'] is! String ||
          node['nodeId'] is! String ||
          node['packageName'] != target) {
        throw const FormatException(
          'รายการไม่มีรหัสอ้างอิงของแอปเป้าหมาย กรุณาอ่านหน้าจอใหม่',
        );
      }
      _step('4/5 แตะรายการหนึ่งครั้ง');
      final response = await platform
          .tapElementById(
            screenId: node['screenId'] as String,
            nodeId: node['nodeId'] as String,
            targetPackage: target,
            runId: id,
          )
          .timeout(const Duration(seconds: 12));
      _check(id);
      if (response?['code'] != 'ACTION_DISPATCHED') {
        throw const FormatException('Android ไม่ยืนยันการรับคำสั่งแตะ');
      }
      _step('5/5 รอ UI ผลลัพธ์');
      await _wait(id, target, field, after, 'after');
      _check(id);
      await platform
          .finishCommandSession(id)
          .timeout(const Duration(seconds: 2));
      _check(id);
      completed = true;
      update(() {
        status = 'ผ่าน: ทำครบ 5 ขั้นและพบ UI ผลลัพธ์';
        steps.add(status);
      });
    } on _SequenceCancelled {
      if (mounted && _runId == id) update(() => status = 'หยุดชุดทดสอบแล้ว');
    } on PlatformException catch (error) {
      if (mounted && _runId == id) {
        update(
          () => status = error.code == 'SEQUENCE_CANCELLED'
              ? 'หยุดชุดทดสอบแล้ว'
              : 'ไม่ผ่านที่ $status: ${error.message ?? error.code}',
        );
      }
    } on MissingPluginException {
      if (mounted && _runId == id) {
        update(
          () => status = 'ต้อง build Android ใหม่ก่อนใช้ชุดทดสอบต่อเนื่อง',
        );
      }
    } on FormatException catch (error) {
      if (mounted && _runId == id) {
        update(() => status = 'ไม่ผ่านที่ $status: ${error.message}');
      }
    } on TimeoutException {
      if (mounted && _runId == id) {
        update(() => status = 'หมดเวลาที่ $status หยุดส่งคำสั่งถัดไปแล้ว');
      }
    } finally {
      if (!completed) await _cancelNative(id);
      if (mounted && _runId == id) {
        _runId = null;
        _runTarget = null;
        update(() => isRunning = false);
      }
    }
  }

  Future<void> _wait(
    String id,
    String target,
    String field,
    String value,
    String phase,
  ) async {
    final result = await platform
        .waitForUi(
          requestId: '$id-$phase',
          targetPackage: target,
          selector: field,
          value: value,
          timeoutMs: 15000,
          runId: id,
        )
        .timeout(const Duration(seconds: 17));
    _check(id);
    if (result?['code'] == 'UI_CANCELLED') throw _SequenceCancelled();
    if (result?['code'] != 'UI_FOUND') {
      throw FormatException(result?['message'] as String? ?? 'ไม่พบ UI ที่รอ');
    }
  }

  Future<void> _cancelNative(String id) async {
    try {
      await platform
          .cancelCommandSession(id)
          .timeout(const Duration(seconds: 2));
    } on PlatformException {
      // Native session expires independently after 120 seconds.
    } on MissingPluginException {
      // Keep the page usable if the channel is unavailable.
    } on TimeoutException {
      // Do not let a missing acknowledgement block local cancellation.
    }
  }

  Future<void> stop() async {
    final id = _runId;
    if (id == null) return;
    _runId = null;
    _runTarget = null;
    update(() {
      isRunning = false;
      status = 'หยุดชุดทดสอบแล้ว คำสั่งที่ส่งไปก่อนหน้านี้อาจทำงานไปแล้ว';
    });
    await _cancelNative(id);
  }

  @override
  void dispose() {
    final id = _runId;
    _runId = null;
    if (id != null) unawaited(_cancelNative(id));
    beforeController.dispose();
    buttonController.dispose();
    afterController.dispose();
    super.dispose();
  }
}
