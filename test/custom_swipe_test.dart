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
  ScreenCaptureController capture(CommandFeedback f) =>
      ScreenCaptureController(f)
        ..packageName = 'target.app'
        ..width = 1280
        ..height = 2800
        ..rotation = 0
        ..selectedX = .2
        ..selectedY = .8
        ..swipeEndX = .8
        ..swipeEndY = .2;
  test(
    'Custom swipe forwards start end duration and display metadata',
    () async {
      MethodCall? request;
      messenger.setMockMethodCallHandler(channel, (call) async {
        request = call;
        return {'message': 'queued'};
      });
      final f = CommandFeedback()..targetPackage = 'target.app';
      final c = capture(f);
      final a = ScreenActionController(f, c);
      addTearDown(a.dispose);
      addTearDown(c.dispose);
      a.setSwipeDuration(750);
      await a.swipeSelectedPoints();
      expect(request!.method, 'queueSwipe');
      expect(request!.arguments, {
        'x': .2,
        'y': .8,
        'endX': .8,
        'endY': .2,
        'width': 1280,
        'height': 2800,
        'rotation': 0,
        'packageName': 'target.app',
        'durationMs': 750,
      });
    },
  );
  test('Missing or identical endpoint never sends a gesture', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return null;
    });
    final f = CommandFeedback();
    final c = capture(f)..swipeEndX = null;
    final a = ScreenActionController(f, c);
    addTearDown(a.dispose);
    addTearDown(c.dispose);
    await a.swipeSelectedPoints();
    c.swipeEndX = c.selectedX;
    c.swipeEndY = c.selectedY;
    await a.swipeSelectedPoints();
    expect(calls, 0);
  });
  test('Selecting endpoint preserves start and target change clears both', () {
    final c = capture(CommandFeedback());
    addTearDown(c.dispose);
    c.selectSwipeEnd(true);
    c.selectPoint(.7, .3);
    expect(c.selectedX, .2);
    expect(c.swipeEndX, .7);
    c.clearForTargetChange();
    expect(c.selectedX, isNull);
    expect(c.swipeEndX, isNull);
    expect(c.selectingSwipeEnd, isFalse);
  });
  test('Swipe cannot use another apps captured screen', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return null;
    });
    final f = CommandFeedback()..targetPackage = 'other.app';
    final c = capture(f);
    final a = ScreenActionController(f, c);
    addTearDown(a.dispose);
    addTearDown(c.dispose);
    await a.swipeSelectedPoints();
    expect(calls, 0);
  });
}
