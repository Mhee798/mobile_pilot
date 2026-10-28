import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'device_controller.dart';

class SettingsTestController extends DeviceController {
  SettingsTestController(super.feedback, this.targetController);

  final TextEditingController targetController;
  Timer? pollTimer;
  String? message;
  bool isStarting = false;

  Future<void> loadResult() async {
    try {
      final response = await platform.getSettingsTapTestResult();
      if (!mounted) return;
      final status = response?['status'] as String?;
      final resultMessage = response?['message'] as String?;
      if (status == null ||
          status.isEmpty ||
          resultMessage == null ||
          resultMessage.isEmpty) {
        return;
      }
      update(() => message = 'Settings test [$status]: $resultMessage');
      pollTimer?.cancel();
      if ((status == 'waiting' || status == 'running') &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        pollTimer = Timer(const Duration(seconds: 1), loadResult);
      }
    } on PlatformException {
      // The local in-app commands remain usable if the Settings test is unavailable.
    } on MissingPluginException {
      // A full Android rebuild is required after adding the native test channel.
    }
  }

  Future<void> run() async {
    final target = targetController.text.trim();
    if (target.isEmpty) {
      update(() => message = 'ใส่ข้อความที่มองเห็นใน Settings ก่อน');
      return;
    }
    update(() {
      isStarting = true;
      message = 'กำลังเปิด Settings เพื่อหา "$target"';
    });
    try {
      final response = await platform.startSettingsTapTest(target);
      if (mounted) {
        update(
          () => message =
              response?['message'] as String? ??
              'เปิด Settings แล้ว กำลังรอเป้าหมาย',
        );
      }
    } on PlatformException catch (error) {
      if (mounted) {
        update(() => message = error.message ?? error.code);
      }
    } on MissingPluginException {
      if (mounted) {
        update(
          () => message =
              'อัปเดตแอปด้วย full Android rebuild ก่อนใช้ Settings test',
        );
      }
    } finally {
      if (mounted) update(() => isStarting = false);
    }
  }

  @override
  void dispose() {
    pollTimer?.cancel();
    super.dispose();
  }
}
