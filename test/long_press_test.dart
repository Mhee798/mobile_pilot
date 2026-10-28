import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/features/device/presentation/controllers/device_controller.dart';
import 'package:mobile_pilot/features/device/presentation/controllers/screen_capture_controller.dart';
import 'package:mobile_pilot/features/device/presentation/controllers/screen_action_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.mobilepilot/settings');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  ScreenCaptureController capture(CommandFeedback feedback) =>
      ScreenCaptureController(feedback)
        ..packageName = 'target.app'
        ..width = 1280
        ..height = 2800
        ..rotation = 0
        ..selectedX = .25
        ..selectedY = .75;

  test('Drag needs destination and forwards hold and travel times', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return {'message': 'queued'};
    });
    final feedback = CommandFeedback()..targetPackage = 'target.app';
    final screen = capture(feedback);
    final actions = ScreenActionController(feedback, screen);
    addTearDown(actions.dispose);
    addTearDown(screen.dispose);
    await actions.dragSelectedPoints();
    expect(calls, isEmpty);
    screen.swipeEndX = .8;
    screen.swipeEndY = .2;
    actions.setDragHold(1000);
    actions.setSwipeDuration(800);
    await actions.dragSelectedPoints();
    expect(calls.single.method, 'queueDrag');
    expect(calls.single.arguments['holdMs'], 1000);
    expect(calls.single.arguments['durationMs'], 800);
  });
  test(
    'Double tap forwards capture target and blocks stale selected target',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return {'message': 'queued'};
      });
      final feedback = CommandFeedback()..targetPackage = 'target.app';
      final screen = capture(feedback);
      final actions = ScreenActionController(feedback, screen);
      addTearDown(actions.dispose);
      addTearDown(screen.dispose);
      await actions.doubleTapSelectedPoint();
      expect(calls.first.method, 'queueDoubleTap');
      expect(calls.first.arguments['packageName'], 'target.app');
      feedback.targetPackage = 'other.app';
      await actions.doubleTapSelectedPoint();
      expect(calls.length, 1);
    },
  );
  test(
    'Long press forwards screenshot metadata and selected duration',
    () async {
      MethodCall? request;
      messenger.setMockMethodCallHandler(channel, (call) async {
        request = call;
        return {'message': 'queued'};
      });
      final feedback = CommandFeedback()..targetPackage = 'target.app';
      final screen = capture(feedback);
      final actions = ScreenActionController(feedback, screen);
      addTearDown(actions.dispose);
      addTearDown(screen.dispose);
      actions.setLongPressDuration(1500);
      await actions.longPressSelectedPoint();
      expect(request!.method, 'queueLongPress');
      expect(request!.arguments, {
        'x': .25,
        'y': .75,
        'width': 1280,
        'height': 2800,
        'rotation': 0,
        'packageName': 'target.app',
        'durationMs': 1500,
      });
      expect(feedback.isTapping, isFalse);
    },
  );
  test('Long press cannot use an old screenshot from another target', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return null;
    });
    final feedback = CommandFeedback()..targetPackage = 'other.app';
    final screen = capture(feedback);
    final actions = ScreenActionController(feedback, screen);
    addTearDown(actions.dispose);
    addTearDown(screen.dispose);
    await actions.longPressSelectedPoint();
    expect(calls, 0);
    expect(feedback.message, contains('กรุณาจับภาพใหม่'));
  });
  test('Long press requires a selected point', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return null;
    });
    final feedback = CommandFeedback();
    final screen = capture(feedback)..selectedX = null;
    final actions = ScreenActionController(feedback, screen);
    addTearDown(actions.dispose);
    addTearDown(screen.dispose);
    await actions.longPressSelectedPoint();
    expect(calls, 0);
  });
}
