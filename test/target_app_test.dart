import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/features/device/presentation/controllers/app_launcher_controller.dart';
import 'package:mobile_pilot/features/device/presentation/controllers/device_controller.dart';
import 'package:mobile_pilot/features/device/presentation/controllers/screen_action_controller.dart';
import 'package:mobile_pilot/features/device/presentation/controllers/screen_capture_controller.dart';
import 'package:mobile_pilot/features/device/presentation/controllers/ui_tree_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.mobilepilot/settings');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('Selecting a target cancels native old work and searches preserve selection', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'findLaunchableApps' ? <Object>[] : null;
    });
    final feedback = CommandFeedback();
    final launcher = AppLauncherController(feedback);
    addTearDown(launcher.dispose);
    await launcher.select({'label': 'Settings', 'packageName': 'settings.app'});
    expect(calls.first.method, 'setTargetApp');
    expect(calls.first.arguments['packageName'], 'settings.app');
    launcher.searchController.text = 'Other';
    await launcher.findApps();
    expect(feedback.targetPackage, 'settings.app');
    expect(launcher.selectedPackage, 'settings.app');
  });

  test('Launch stays waiting until native foreground confirmation and reports failure', () async {
    final launch = Completer<Object?>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'launchApp') return launch.future;
      return null;
    });
    final launcher = AppLauncherController(CommandFeedback());
    addTearDown(launcher.dispose);
    await launcher.select({'label': 'Settings', 'packageName': 'settings.app'});
    final pending = launcher.launchSelected();
    expect(launcher.isLaunching, isTrue);
    launch.completeError(PlatformException(code: 'TARGET_NOT_READY'));
    await pending;
    expect(launcher.isLaunching, isFalse);
    expect(launcher.targetStatus, contains('TARGET_NOT_READY'));
  });

  test(
    'UI reads and text taps pass the selected target without launching it',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'getUiTree'
            ? <Object>[]
            : {'message': 'accepted'};
      });
      final feedback = CommandFeedback()..targetPackage = 'settings.app';
      final tree = UiTreeController(feedback);
      addTearDown(tree.dispose);
      await tree.read();
      tree.targetController.text = 'Battery';
      await tree.tapByText();
      expect(calls.where((c) => c.method == 'launchApp'), isEmpty);
      for (final call in calls) {
        expect(call.arguments['targetPackage'], 'settings.app');
      }
    },
  );

  test('Late tree response from the old target is discarded', () async {
    final response = Completer<Object?>();
    messenger.setMockMethodCallHandler(channel, (_) => response.future);
    final feedback = CommandFeedback()..targetPackage = 'old.app';
    final tree = UiTreeController(feedback);
    addTearDown(tree.dispose);
    final pending = tree.read();
    feedback.targetPackage = 'new.app';
    response.complete([
      {'text': 'Old target'},
    ]);
    await pending;
    expect(tree.elements, isEmpty);
  });

  test(
    'An old screenshot cannot direct point or text actions to another target',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      final feedback = CommandFeedback()..targetPackage = 'new.app';
      final capture = ScreenCaptureController(feedback)
        ..packageName = 'old.app'
        ..width = 100
        ..height = 200
        ..rotation = 0
        ..selectedX = 0.5
        ..selectedY = 0.5;
      final actions = ScreenActionController(feedback, capture);
      addTearDown(actions.dispose);
      addTearDown(capture.dispose);
      await actions.tapSelectedPoint();
      await actions.queue('type_text', text: 'hello');
      expect(calls, isEmpty);
      expect(feedback.message, contains('กรุณาจับภาพใหม่'));
    },
  );

  test(
    'Cancel button cancels native pending actions without launching an app',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      final feedback = CommandFeedback();
      final capture = ScreenCaptureController(feedback);
      final actions = ScreenActionController(feedback, capture);
      addTearDown(actions.dispose);
      addTearDown(capture.dispose);
      await actions.cancelPending();
      expect(calls.single.method, 'cancelScreenActions');
      expect(feedback.message, contains('ยกเลิกคำสั่งที่รออยู่แล้ว'));
    },
  );

  testWidgets(
    'Capture binds to selected target and target change clears its deadline',
    (tester) async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return {'code': 'CAPTURE_ARMED'};
      });
      final feedback = CommandFeedback()..targetPackage = 'settings.app';
      final capture = ScreenCaptureController(feedback);
      await capture.capture();
      expect(calls.single.arguments['targetPackage'], 'settings.app');
      feedback.targetPackage = 'other.app';
      capture.clearForTargetChange();
      await tester.pump(const Duration(seconds: 31));
      expect(capture.isWaiting, isFalse);
      expect(capture.packageName, isNull);
      expect(calls.length, 1);
      capture.dispose();
    },
  );
}
