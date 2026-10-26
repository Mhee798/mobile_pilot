import 'dart:async';

import 'package:flutter/services.dart';

import 'device_controller.dart';

class ScreenCaptureController extends DeviceController {
  ScreenCaptureController(super.feedback);

  Timer? pollTimer;
  Timer? _deadlineTimer;
  bool _deadlineReached = false;
  bool _isPolling = false;
  int _requestId = 0;
  static const _captureTimeout = Duration(seconds: 30);
  static const _channelTimeout = Duration(seconds: 2);
  int pollAttempts = 0;
  Uint8List? image;
  int? width;
  int? height;
  int? rotation;
  String? packageName;
  double? selectedX;
  double? selectedY;
  bool isCapturing = false;
  bool isWaiting = false;

  void selectPoint(double x, double y) => update(() {
    selectedX = x;
    selectedY = y;
  });

  Future<void> capture() async {
    if (!mounted || isCapturing || isWaiting) return;
    final requestId = ++_requestId;
    _isPolling = false;
    _deadlineTimer?.cancel();
    _deadlineReached = false;
    update(() {
      isCapturing = true;
      feedback.message = null;
    });
    try {
      final response = await platform.armScreenCapture();
      if (!mounted || requestId != _requestId) return;
      if (response == null) {
        throw const FormatException('Capture could not be armed.');
      }
      pollTimer?.cancel();
      update(() {
        isWaiting = true;
        pollAttempts = 0;
        feedback.message = 'สลับไปแอปเป้าหมายภายใน 30 วินาที แล้วกลับมา MobilePilot เพื่อดูภาพ';
      });
      _deadlineTimer = Timer(_captureTimeout, () {
        if (!mounted || requestId != _requestId || !isWaiting) return;
        _deadlineReached = true;
        // Read a completed capture before expiring: the user may still be in the target app.
        unawaited(poll());
      });
      return;
    } on PlatformException catch (error) {
      if (mounted) update(() => feedback.message = error.message ?? error.code);
    } on MissingPluginException {
      if (mounted) {
        update(
          () => feedback.message =
              'ไม่พบ screenshot channel; ต้อง build Android ใหม่',
        );
      }
    } on FormatException catch (error) {
      if (mounted) update(() => feedback.message = error.message.toString());
    } finally {
      if (mounted) update(() => isCapturing = false);
    }
  }

  Future<void> poll() async {
    if (!isWaiting || !mounted || _isPolling) return;
    final requestId = _requestId;
    _isPolling = true;
    try {
      final response = await platform.getCapturedScreen().timeout(
        _channelTimeout,
      );
      if (!mounted || requestId != _requestId || !isWaiting) return;
      if (response == null) {
        pollAttempts++;
        if (_deadlineReached || pollAttempts >= 40) {
          await _expire(requestId);
          return;
        }
        pollTimer?.cancel();
        pollTimer = Timer(const Duration(milliseconds: 700), poll);
        return;
      }
      final jpeg = response['jpeg'];
      final capturedWidth = response['width'] as int?;
      final capturedHeight = response['height'] as int?;
      final capturedRotation = response['rotation'] as int?;
      final capturedPackageName = response['packageName'] as String?;
      if (jpeg is! Uint8List ||
          capturedWidth == null ||
          capturedHeight == null ||
          capturedRotation == null ||
          capturedPackageName == null) {
        throw const FormatException('Screenshot response was incomplete.');
      }
      _stopWaiting();
      update(() {
        image = jpeg;
        width = capturedWidth;
        height = capturedHeight;
        rotation = capturedRotation;
        packageName = capturedPackageName;
        selectedX = null;
        selectedY = null;
        feedback.message = 'จับภาพแอปแล้ว ($capturedWidth×$capturedHeight)';
      });
    } on TimeoutException {
      await _expire(requestId);
    } on PlatformException catch (error) {
      if (mounted && requestId == _requestId) {
        _stopWaiting();
        update(() {
          feedback.message = error.message ?? error.code;
        });
      }
    } on MissingPluginException {
      if (mounted && requestId == _requestId) {
        _stopWaiting();
        update(
          () => feedback.message =
              'ไม่พบ screenshot channel; ต้อง build Android ใหม่',
        );
      }
    } on FormatException catch (error) {
      if (mounted && requestId == _requestId) {
        _stopWaiting();
        update(() {
          feedback.message = error.message.toString();
        });
      }
    } finally {
      if (requestId == _requestId) _isPolling = false;
    }
  }

  void _stopWaiting() {
    pollTimer?.cancel();
    _deadlineTimer?.cancel();
    isWaiting = false;
  }

  Future<void> _expire(int requestId) async {
    if (!mounted || requestId != _requestId || !isWaiting) return;
    _stopWaiting();
    update(() {
      feedback.message =
          'ไม่พบภาพจากแอปอื่น กลับไปจับภาพอีกครั้งแล้วรอในแอปเป้าหมายสักครู่';
    });
    try {
      await platform.cancelScreenCapture().timeout(_channelTimeout);
    } on PlatformException {
      // Android also expires armed captures independently after 30 seconds.
    } on MissingPluginException {
      // Keep retry available when the native channel is unavailable.
    } on TimeoutException {
      // A missing cancellation response must not leave the UI waiting.
    }
  }

  @override
  void dispose() {
    _requestId++;
    _stopWaiting();
    super.dispose();
  }
}
