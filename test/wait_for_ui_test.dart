import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/features/device/controllers/device_controller.dart';
import 'package:mobile_pilot/features/device/controllers/wait_for_ui_controller.dart';
import 'package:mobile_pilot/features/device/widgets/wait_for_ui_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.mobilepilot/settings');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('Requires explicit target and nonempty selector value', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    final wait = WaitForUiController(CommandFeedback());
    addTearDown(wait.dispose);
    await wait.start();
    expect(calls, isEmpty);
    expect(wait.isWaiting, isFalse);
  });

  test('Passes a typed target condition and handles found result', () async {
    MethodCall? request;
    messenger.setMockMethodCallHandler(channel, (call) async {
      request = call;
      return {'code': 'UI_FOUND', 'message': 'found'};
    });
    final wait = WaitForUiController(
      CommandFeedback()..targetPackage = 'settings.app',
    );
    addTearDown(wait.dispose);
    wait.valueController.text = 'Search';
    wait.selector = 'contentDescription';
    wait.timeoutSeconds = 5;
    await wait.start();
    expect(request!.method, 'waitForUi');
    expect(request!.arguments['targetPackage'], 'settings.app');
    expect(request!.arguments['selector'], 'contentDescription');
    expect(request!.arguments['value'], 'Search');
    expect(request!.arguments['timeoutMs'], 5000);
    expect(wait.message, contains('พบ “Search”'));
    expect(wait.isWaiting, isFalse);
  });

  test(
    'Scroll lookup sends limits and reports count without a click',
    () async {
      MethodCall? request;
      messenger.setMockMethodCallHandler(channel, (call) async {
        request = call;
        return {'code': 'UI_FOUND', 'message': 'found', 'scrollCount': 3};
      });
      final wait = WaitForUiController(
        CommandFeedback()..targetPackage = 'settings.app',
      );
      addTearDown(wait.dispose);
      wait.valueController.text = 'Search';
      wait.setScrollToFind(true);
      wait.setDirection('up');
      wait.setMaxScrolls(5);
      await wait.start();
      expect(request!.method, 'scrollUntilUi');
      expect(request!.arguments['direction'], 'up');
      expect(request!.arguments['maxScrolls'], 5);
      expect(request!.arguments['distance'], 'long');
      expect(wait.message, contains('3 ครั้ง'));
      expect(wait.message, contains('ยังไม่ได้แตะ'));
    },
  );

  test('Cancelling a scroll ignores its late result', () async {
    final response = Completer<Object?>();
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'scrollUntilUi' ? response.future : null;
    });
    final wait = WaitForUiController(
      CommandFeedback()..targetPackage = 'settings.app',
    );
    addTearDown(wait.dispose);
    wait.valueController.text = 'Search';
    wait.setScrollToFind(true);
    final pending = wait.start();
    await Future<void>.delayed(Duration.zero);
    await wait.cancel();
    expect(calls.last.method, 'cancelUiWait');
    expect(
      calls.last.arguments['requestId'],
      calls.first.arguments['requestId'],
    );
    response.complete({
      'code': 'UI_FOUND',
      'message': 'late',
      'scrollCount': 2,
    });
    await pending;
    expect(wait.message, 'ยกเลิกการรอ UI แล้ว');
  });

  test(
    'Disappearance is explicit and does not change presence callers',
    () async {
      MethodCall? request;
      messenger.setMockMethodCallHandler(channel, (call) async {
        request = call;
        return {'code': 'UI_DISAPPEARED', 'message': 'gone'};
      });
      final wait = WaitForUiController(
        CommandFeedback()..targetPackage = 'settings.app',
      );
      addTearDown(wait.dispose);
      wait.valueController.text = 'Loading';
      wait.setCondition('disappeared');
      await wait.start();
      expect(request!.arguments['condition'], 'disappeared');
      expect(wait.message, contains('รายการหายไป'));
      wait.setScrollToFind(true);
      expect(wait.condition, 'present');
    },
  );

  test(
    'New wait conditions are explicit and changed text needs stable locator',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return {'code': 'UI_ENABLED', 'message': 'ready'};
      });
      final wait = WaitForUiController(
        CommandFeedback()..targetPackage = 'target.app',
      );
      addTearDown(wait.dispose);
      wait.valueController.text = 'Continue';
      wait.setCondition('enabled');
      await wait.start();
      expect(calls.single.arguments['condition'], 'enabled');
      expect(wait.message, contains('พร้อมกด'));
      wait.setCondition('textChanged');
      await wait.start();
      expect(calls.length, 1);
      wait.setSelector('resourceId');
      await wait.start();
      expect(calls.last.arguments['condition'], 'textChanged');
    },
  );
  test('Timeout result allows retry', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return {'code': 'UI_TIMEOUT', 'message': 'timed out'};
    });
    final wait = WaitForUiController(
      CommandFeedback()..targetPackage = 'settings.app',
    );
    addTearDown(wait.dispose);
    wait.valueController.text = 'Missing';
    await wait.start();
    expect(wait.message, contains('หมดเวลารอ'));
    await wait.start();
    expect(calls, 2);
  });

  test(
    'Cancellation addresses only its request and late found result is ignored',
    () async {
      final response = Completer<Object?>();
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'waitForUi' ? response.future : null;
      });
      final wait = WaitForUiController(
        CommandFeedback()..targetPackage = 'settings.app',
      );
      addTearDown(wait.dispose);
      wait.valueController.text = 'Search';
      final pending = wait.start();
      await Future<void>.delayed(Duration.zero);
      await wait.cancel();
      expect(calls.last.method, 'cancelUiWait');
      expect(
        calls.last.arguments['requestId'],
        calls.first.arguments['requestId'],
      );
      response.complete({'code': 'UI_FOUND', 'message': 'found'});
      await pending;
      expect(wait.message, 'ยกเลิกการรอ UI แล้ว');
      expect(wait.isWaiting, isFalse);
    },
  );

  test(
    'Target change ignores old results while a new wait stays active',
    () async {
      final first = Completer<Object?>();
      final second = Completer<Object?>();
      var starts = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'waitForUi') {
          return ++starts == 1 ? first.future : second.future;
        }
        return null;
      });
      final feedback = CommandFeedback()..targetPackage = 'old.app';
      final wait = WaitForUiController(feedback);
      addTearDown(wait.dispose);
      wait.valueController.text = 'Search';
      final old = wait.start();
      feedback.targetPackage = 'new.app';
      wait.targetChanged();
      final current = wait.start();
      first.complete({'code': 'UI_FOUND', 'message': 'old'});
      await old;
      expect(wait.isWaiting, isTrue);
      second.complete({'code': 'UI_TIMEOUT', 'message': 'timeout'});
      await current;
      expect(wait.message, contains('หมดเวลารอ'));
    },
  );

  test('Disposal cancels native wait and ignores its late response', () async {
    final response = Completer<Object?>();
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      return call.method == 'waitForUi' ? response.future : null;
    });
    final wait = WaitForUiController(
      CommandFeedback()..targetPackage = 'settings.app',
    );
    wait.valueController.text = 'Search';
    final pending = wait.start();
    wait.dispose();
    response.complete({'code': 'UI_FOUND', 'message': 'found'});
    await pending;
    expect(methods, contains('cancelUiWait'));
  });

  testWidgets('Missing native response is bounded without a resume event', (
    tester,
  ) async {
    final response = Completer<Object?>();
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'waitForUi' ? response.future : null;
    });
    final wait = WaitForUiController(
      CommandFeedback()..targetPackage = 'settings.app',
    );
    wait.timeoutSeconds = 5;
    wait.valueController.text = 'Search';
    final pending = wait.start();
    await tester.pump();
    await tester.pump(const Duration(seconds: 7));
    await pending;
    expect(wait.isWaiting, isFalse);
    expect(wait.message, contains('ไม่ได้รับผลจาก Android'));
    expect(calls, contains('cancelUiWait'));
    wait.dispose();
    response.complete(null);
    await tester.pump();
  });

  testWidgets(
    'Wait section shows completion independently of shared command feedback',
    (tester) async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'code': 'UI_FOUND', 'message': 'found'},
      );
      final feedback = CommandFeedback()..targetPackage = 'settings.app';
      final wait = WaitForUiController(feedback);
      wait.valueController.text = 'Search';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedBuilder(
              animation: wait,
              builder: (_, _) => WaitForUiSection(controller: wait),
            ),
          ),
        ),
      );
      await wait.start();
      feedback.message = 'old point tap';
      await tester.pumpAndSettle();
      expect(find.text('พบ “Search” ในแอปเป้าหมายแล้ว'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      wait.dispose();
    },
  );
}
