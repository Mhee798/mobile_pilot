import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/features/device/controllers/device_controller.dart';
import 'package:mobile_pilot/features/device/controllers/command_sequence_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.mobilepilot/settings');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  CommandSequenceController create() =>
      CommandSequenceController(CommandFeedback()..targetPackage = 'target.app')
        ..beforeController.text = 'Home'
        ..buttonController.text = 'Open menu'
        ..afterController.text = 'Menu item';
  List<Map<String, dynamic>> nodes() => [
    {'text': 'Home', 'visible': true},
    {
      'text': 'Open menu',
      'visible': true,
      'enabled': true,
      'clickable': true,
      'screenId': 'screen-1',
      'nodeId': 'node-2',
      'packageName': 'target.app',
    },
  ];
  Object? response(MethodCall call) => switch (call.method) {
    'launchApp' => {'code': 'TARGET_READY'},
    'waitForUi' => {'code': 'UI_FOUND'},
    'getUiTree' => nodes(),
    'tapElementById' => {'code': 'ACTION_DISPATCHED'},
    _ => null,
  };

  test(
    'Sequence uses one target/session and verifies the newly present result',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return response(call);
      });
      final run = create();
      addTearDown(run.dispose);
      await run.start();
      expect(run.status, startsWith('ผ่าน:'));
      expect(run.isRunning, isFalse);
      expect(calls.map((c) => c.method), [
        'beginCommandSession',
        'launchApp',
        'waitForUi',
        'getUiTree',
        'tapElementById',
        'waitForUi',
        'finishCommandSession',
      ]);
      final id = calls.first.arguments['sessionId'];
      for (final call in calls.skip(1).take(5)) {
        expect(call.arguments['runId'], id);
      }
      expect(calls[4].arguments['nodeId'], 'node-2');
    },
  );
  test('Duplicate buttons stop without guessing or tapping', () async {
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      if (call.method == 'getUiTree') return [...nodes(), nodes().last];
      return response(call);
    });
    final run = create();
    addTearDown(run.dispose);
    await run.start();
    expect(methods, isNot(contains('tapElementById')));
    expect(methods.last, 'cancelCommandSession');
    expect(run.status, contains('หลายรายการ'));
  });
  test('An already present result cannot verify a new action', () async {
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      return call.method == 'getUiTree'
          ? [
              ...nodes(),
              {'text': 'Menu item', 'visible': true},
            ]
          : response(call);
    });
    final run = create();
    addTearDown(run.dispose);
    await run.start();
    expect(methods, isNot(contains('tapElementById')));
    expect(run.status, contains('อยู่ก่อนแตะแล้ว'));
  });
  test('Wait timeout prevents all remaining steps', () async {
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      return call.method == 'waitForUi'
          ? {'code': 'UI_TIMEOUT', 'message': 'missing'}
          : response(call);
    });
    final run = create();
    addTearDown(run.dispose);
    await run.start();
    expect(methods, isNot(contains('getUiTree')));
    expect(run.status, contains('ไม่ผ่าน'));
  });
  test('Stale snapshot never triggers an automatic retry', () async {
    var taps = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'tapElementById') {
        taps++;
        throw PlatformException(code: 'STALE_SCREEN');
      }
      return response(call);
    });
    final run = create();
    addTearDown(run.dispose);
    await run.start();
    expect(taps, 1);
    expect(run.status, contains('STALE_SCREEN'));
  });
  test(
    'Stop during read prevents a late response from dispatching a click',
    () async {
      final read = Completer<Object?>();
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return call.method == 'getUiTree' ? read.future : response(call);
      });
      final run = create();
      addTearDown(run.dispose);
      final pending = run.start();
      while (!calls.contains('getUiTree')) {
        await Future<void>.delayed(Duration.zero);
      }
      await run.stop();
      read.complete(nodes());
      await pending;
      expect(calls, isNot(contains('tapElementById')));
      expect(run.status, contains('หยุดชุดทดสอบ'));
    },
  );
  test(
    'Floating Stop cancellation of wait reports stopped instead of success',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'waitForUi'
            ? {'code': 'UI_CANCELLED'}
            : response(call),
      );
      final run = create();
      addTearDown(run.dispose);
      await run.start();
      expect(run.status, 'หยุดชุดทดสอบแล้ว');
      expect(run.isRunning, isFalse);
    },
  );
  test(
    'Late result from stopped run cannot overwrite a completed retry',
    () async {
      final begin = Completer<Object?>();
      var starts = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'beginCommandSession' && ++starts == 1) {
          return begin.future;
        }
        return response(call);
      });
      final run = create();
      addTearDown(run.dispose);
      final old = run.start();
      await Future<void>.delayed(Duration.zero);
      await run.stop();
      await run.start();
      begin.complete(null);
      await old;
      expect(run.status, startsWith('ผ่าน:'));
      expect(run.isRunning, isFalse);
    },
  );
}
