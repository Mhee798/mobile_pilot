import 'package:flutter/services.dart';

import 'device_controller.dart';
import 'screen_capture_controller.dart';

class PinchController extends DeviceController {
  PinchController(super.feedback, this.capture);
  final ScreenCaptureController capture;
  double scale = 4.0;
  double startSpan = 0.2;
  String axis = 'horizontal';
  int durationMs = 1000;
  void strongExpand() => update(() {
    scale = 4.0;
    startSpan = 0.2;
    durationMs = 1000;
  });
  void strongShrink() => update(() {
    scale = 0.25;
    startSpan = 0.8;
    durationMs = 1000;
  });
  void setScale(double value) => update(() => scale = value);
  void setSpan(double value) => update(() => startSpan = value);
  void setAxis(String value) => update(() => axis = value);
  void setDuration(int value) => update(() => durationMs = value);
  void chooseCenter() {
    capture.selectSwipeEnd(false);
    update(
      () => feedback.message = 'แตะภาพเพื่อวางหมุดแดงที่จุดกึ่งกลางของการซูม',
    );
  }

  Future<void> queue() async {
    if (!mounted || feedback.isTapping) return;
    final x = capture.selectedX;
    final y = capture.selectedY;
    final width = capture.width;
    final height = capture.height;
    final rotation = capture.rotation;
    final pkg = capture.packageName;
    if (x == null ||
        y == null ||
        width == null ||
        height == null ||
        rotation == null ||
        pkg == null) {
      update(
        () => feedback.message = 'จับภาพแล้วเลือกหมุดแดงเป็นจุดกึ่งกลางก่อนซูม',
      );
      return;
    }
    if (feedback.targetPackage != null && feedback.targetPackage != pkg) {
      update(
        () => feedback.message = 'ภาพนี้ไม่ใช่แอปเป้าหมาย กรุณาจับภาพใหม่',
      );
      return;
    }
    update(() => feedback.isTapping = true);
    try {
      final result = await platform.queuePinch(
        x: x,
        y: y,
        width: width,
        height: height,
        rotation: rotation,
        packageName: pkg,
        durationMs: durationMs,
        startSpan: startSpan,
        scale: scale,
        axis: axis,
      );
      if (mounted) {
        update(
          () => feedback.message =
              result?['message'] as String? ?? 'เข้าคิวสองนิ้วแล้ว',
        );
      }
    } on PlatformException catch (error) {
      if (mounted) update(() => feedback.message = error.message ?? error.code);
    } on MissingPluginException {
      if (mounted) {
        update(
          () => feedback.message = 'ต้อง build Android ใหม่ก่อนใช้สองนิ้ว',
        );
      }
    } finally {
      if (mounted) update(() => feedback.isTapping = false);
    }
  }
}
