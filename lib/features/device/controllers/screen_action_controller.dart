import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'device_controller.dart';
import 'screen_capture_controller.dart';

class ScreenActionController extends DeviceController {
  ScreenActionController(super.feedback, this.capture);

  final ScreenCaptureController capture;
  final textController = TextEditingController();
  Timer? pollTimer;
  int pollAttempts = 0;

  Future<void> tapSelectedPoint() async {
    final x = capture.selectedX;
    final y = capture.selectedY;
    final width = capture.width;
    final height = capture.height;
    final rotation = capture.rotation;
    final packageName = capture.packageName;
    if (x == null ||
        y == null ||
        width == null ||
        height == null ||
        rotation == null ||
        packageName == null) {
      update(() => feedback.message = 'จับภาพแล้วเลือกจุดบนภาพก่อน');
      return;
    }
    update(() => feedback.isTapping = true);
    try {
      final response = await platform.queuePointTap(
        x: x,
        y: y,
        width: width,
        height: height,
        rotation: rotation,
        packageName: packageName,
      );
      if (mounted) {
        update(
          () => feedback.message =
              response?['message'] as String? ?? 'ส่งคำสั่งแตะแล้ว',
        );
      }
    } on PlatformException catch (error) {
      if (mounted) update(() => feedback.message = error.message ?? error.code);
    } on MissingPluginException {
      if (mounted) {
        update(
          () => feedback.message =
              'ไม่พบ coordinate gesture channel; ต้อง build Android ใหม่',
        );
      }
    } finally {
      if (mounted) update(() => feedback.isTapping = false);
    }
  }

  Future<void> loadResult() async {
    try {
      final response = await platform.getPointTapResult();
      final code = response?['code'] as String?;
      final message = response?['message'] as String?;
      if (!mounted || code == null || message == null) return;
      update(() => feedback.message = 'Point tap [$code]: $message');
      pollTimer?.cancel();
      if (code == 'TAP_QUEUED' ||
          code == 'TAP_SENDING' ||
          code == 'TAP_WAITING_FOR_TARGET' ||
          code == 'ACTION_QUEUED' ||
          code == 'ACTION_SENDING' ||
          code == 'ACTION_WAITING_FOR_TARGET') {
        pollAttempts++;
        if (pollAttempts < 30 &&
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed) {
          pollTimer = Timer(const Duration(milliseconds: 500), loadResult);
        }
      } else {
        pollAttempts = 0;
      }
    } on PlatformException {
      // Keep the existing command screen usable if the point-tap channel is unavailable.
    }
  }

  Future<void> queue(String action, {String? text}) async {
    final packageName = capture.packageName;
    final width = capture.width;
    final height = capture.height;
    final rotation = capture.rotation;
    if (packageName == null ||
        width == null ||
        height == null ||
        rotation == null) {
      update(() => feedback.message = 'จับภาพแอปเป้าหมายก่อน');
      return;
    }
    update(() => feedback.isTapping = true);
    try {
      final response = await platform.queueScreenAction(
        action: action,
        packageName: packageName,
        width: width,
        height: height,
        rotation: rotation,
        text: text,
      );
      if (mounted) {
        update(
          () => feedback.message =
              response?['message'] as String? ?? 'เข้าคิวคำสั่งแล้ว',
        );
      }
    } on PlatformException catch (error) {
      if (mounted) update(() => feedback.message = error.message ?? error.code);
    } on MissingPluginException {
      if (mounted) {
        update(
          () => feedback.message =
              'ไม่พบ screen action channel; ต้อง build Android ใหม่',
        );
      }
    } finally {
      if (mounted) update(() => feedback.isTapping = false);
    }
  }

  @override
  void dispose() {
    pollTimer?.cancel();
    textController.dispose();
    super.dispose();
  }
}
