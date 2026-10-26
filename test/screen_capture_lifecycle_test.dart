import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/features/device/controllers/device_controller.dart';
import 'package:mobile_pilot/features/device/controllers/screen_capture_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.mobilepilot/settings');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final captured = <String, dynamic>{
    'jpeg': Uint8List.fromList([1, 2, 3]),
    'width': 1280,
    'height': 2800,
    'rotation': 0,
    'packageName': 'com.android.settings',
  };

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets(
    'Capture expires and allows retry without any lifecycle transition',
    (tester) async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return call.method == 'armScreenCapture'
            ? {'code': 'CAPTURE_ARMED'}
            : null;
      });
      final feedback = CommandFeedback();
      final capture = ScreenCaptureController(feedback);
      addTearDown(() {
        if (capture.mounted) capture.dispose();
      });
      await capture.capture();
      await tester.pump(const Duration(milliseconds: 29_999));
      expect(capture.isWaiting, isTrue);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(capture.isWaiting, isFalse);
      expect(feedback.message, contains('ไม่พบภาพจากแอปอื่น'));
      expect(
        calls.where((method) => method == 'cancelScreenCapture'),
        hasLength(1),
      );
      await capture.capture();
      expect(capture.isWaiting, isTrue);
      expect(
        calls.where((method) => method == 'armScreenCapture'),
        hasLength(2),
      );
      capture.dispose();
    },
  );

  testWidgets(
    'Deadline retrieves an already completed capture instead of cancelling it',
    (tester) async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return switch (call.method) {
          'armScreenCapture' => {'code': 'CAPTURE_ARMED'},
          'getCapturedScreen' => captured,
          _ => null,
        };
      });
      final feedback = CommandFeedback();
      final capture = ScreenCaptureController(feedback);
      addTearDown(capture.dispose);
      await capture.capture();
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(capture.isWaiting, isFalse);
      expect(capture.image, orderedEquals([1, 2, 3]));
      expect(capture.packageName, 'com.android.settings');
      expect(feedback.message, 'จับภาพแอปแล้ว (1280×2800)');
      await tester.pump(const Duration(seconds: 30));
      expect(
        calls.where((method) => method == 'getCapturedScreen'),
        hasLength(1),
      );
      expect(calls, isNot(contains('cancelScreenCapture')));
    },
  );

  testWidgets(
    'A hanging native read is bounded and its late response is ignored',
    (tester) async {
      final firstRead = Completer<Map<String, dynamic>?>();
      var reads = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        return switch (call.method) {
          'armScreenCapture' => {'code': 'CAPTURE_ARMED'},
          'getCapturedScreen' => ++reads == 1 ? firstRead.future : captured,
          _ => null,
        };
      });
      final capture = ScreenCaptureController(CommandFeedback());
      addTearDown(capture.dispose);
      await capture.capture();
      final pending = capture.poll();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      await pending;
      expect(capture.isWaiting, isFalse);
      await capture.capture();
      await capture.poll();
      firstRead.complete({...captured, 'packageName': 'old.app'});
      await tester.pump();
      expect(capture.packageName, 'com.android.settings');
    },
  );

  testWidgets(
    'A late cancellation response cannot block polling for a new request',
    (tester) async {
      final cancellation = Completer<void>();
      var reads = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'armScreenCapture':
            return {'code': 'CAPTURE_ARMED'};
          case 'getCapturedScreen':
            return ++reads == 1 ? null : captured;
          case 'cancelScreenCapture':
            await cancellation.future;
            return null;
          default:
            return null;
        }
      });
      final feedback = CommandFeedback();
      final capture = ScreenCaptureController(feedback);
      addTearDown(capture.dispose);
      await capture.capture();
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(capture.isWaiting, isFalse);
      await capture.capture();
      await capture.poll();
      expect(capture.packageName, 'com.android.settings');
      cancellation.complete();
      await tester.pump();
      expect(feedback.message, 'จับภาพแอปแล้ว (1280×2800)');
    },
  );

  testWidgets('Disposal cancels the capture deadline', (tester) async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return {'code': 'CAPTURE_ARMED'};
    });
    final capture = ScreenCaptureController(CommandFeedback());
    await capture.capture();
    capture.dispose();
    await tester.pump(const Duration(seconds: 32));
    expect(calls, ['armScreenCapture']);
  });

  testWidgets('A late arm response does not notify a disposed controller', (
    tester,
  ) async {
    final armed = Completer<Map<String, dynamic>>();
    messenger.setMockMethodCallHandler(channel, (_) => armed.future);
    final capture = ScreenCaptureController(CommandFeedback());
    final pending = capture.capture();
    await tester.pump();
    capture.dispose();
    armed.complete({'code': 'CAPTURE_ARMED'});
    await tester.pump();
    await pending;
    await tester.pump(const Duration(seconds: 32));
    expect(tester.takeException(), isNull);
  });
}
