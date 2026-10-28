import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'device_controller.dart';
import 'screen_capture_controller.dart';

enum _PointAction { tap, doubleTap, longPress, swipe, drag }

class ScreenActionController extends DeviceController {
  ScreenActionController(super.feedback, this.capture);

  final ScreenCaptureController capture;
  final textController = TextEditingController();
  Timer? pollTimer;
  int pollAttempts = 0;

  int swipeDurationMs = 400;
  void setSwipeDuration(int value) => update(() => swipeDurationMs = value);
  Future<void> swipeSelectedPoints() =>
      _queuePoint(_PointAction.swipe, durationMs: swipeDurationMs);

  String keyboardAction = 'default';
  void setKeyboardAction(String value) => update(() => keyboardAction = value);
  Future<void> pressKeyboardAction() => queue('keyboard', text: keyboardAction);
  int dragHoldMs = 750;
  void setDragHold(int value) => update(() => dragHoldMs = value);
  Future<void> dragSelectedPoints() =>
      _queuePoint(_PointAction.drag, durationMs: swipeDurationMs);
  int longPressDurationMs = 1000;
  void setLongPressDuration(int value) =>
      update(() => longPressDurationMs = value);
  Future<void> doubleTapSelectedPoint() => _queuePoint(_PointAction.doubleTap);
  Future<void> tapSelectedPoint() => _queuePoint(_PointAction.tap);
  Future<void> longPressSelectedPoint() =>
      _queuePoint(_PointAction.longPress, durationMs: longPressDurationMs);

  Future<void> _queuePoint(_PointAction action, {int? durationMs}) async {
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
    if (feedback.targetPackage != null &&
        feedback.targetPackage != packageName) {
      update(
        () => feedback.message =
            'ภาพนี้ไม่ใช่แอปเป้าหมายที่เลือก กรุณาจับภาพใหม่',
      );
      return;
    }
    final endX = capture.swipeEndX;
    final endY = capture.swipeEndY;
    if ((action == _PointAction.swipe || action == _PointAction.drag) &&
        (endX == null || endY == null || (endX == x && endY == y))) {
      update(() => feedback.message = 'เลือกจุดปลายที่ต่างจากจุดเริ่มก่อนปัด');
      return;
    }
    update(() => feedback.isTapping = true);
    try {
      final Map<String, dynamic>? response;
      switch (action) {
        case _PointAction.drag:
          response = await platform.queueDrag(
            x: x,
            y: y,
            endX: endX!,
            endY: endY!,
            width: width,
            height: height,
            rotation: rotation,
            packageName: packageName,
            holdMs: dragHoldMs,
            durationMs: durationMs!,
          );
        case _PointAction.doubleTap:
          response = await platform.queueDoubleTap(
            x: x,
            y: y,
            width: width,
            height: height,
            rotation: rotation,
            packageName: packageName,
          );
        case _PointAction.swipe:
          response = await platform.queueSwipe(
            x: x,
            y: y,
            endX: endX!,
            endY: endY!,
            width: width,
            height: height,
            rotation: rotation,
            packageName: packageName,
            durationMs: durationMs!,
          );
        case _PointAction.tap:
          response = await platform.queuePointTap(
            x: x,
            y: y,
            width: width,
            height: height,
            rotation: rotation,
            packageName: packageName,
          );
        case _PointAction.longPress:
          response = await platform.queueLongPress(
            x: x,
            y: y,
            width: width,
            height: height,
            rotation: rotation,
            packageName: packageName,
            durationMs: durationMs!,
          );
      }
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

  Future<void> cancelPending() async {
    try {
      await platform.cancelScreenActions();
      pollTimer?.cancel();
      pollAttempts = 0;
      if (mounted) {
        update(
          () => feedback.message = 'ยกเลิกคำสั่งที่รออยู่แล้ว คำสั่งที่ส่งไปก่อนหน้านี้อาจทำงานไปแล้ว',
        );
      }
    } on PlatformException catch (error) {
      if (mounted) update(() => feedback.message = error.message ?? error.code);
    } on MissingPluginException {
      if (mounted) {
        update(() => feedback.message = 'ต้อง build Android ใหม่ก่อนยกเลิกคิว');
      }
    }
  }

  Future<void> loadResult() async {
    try {
      final response = await platform.getPointTapResult();
      final code = response?['code'] as String?;
      final message = response?['message'] as String?;
      if (!mounted || code == null || message == null) return;
      final status = 'คำสั่ง [$code]: $message';
      if (feedback.message != status) update(() => feedback.message = status);
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
    if (feedback.targetPackage != null &&
        feedback.targetPackage != packageName) {
      update(
        () => feedback.message =
            'ภาพนี้ไม่ใช่แอปเป้าหมายที่เลือก กรุณาจับภาพใหม่',
      );
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
