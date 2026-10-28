import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/features/ai/data/ai_device_tools.dart';
import 'package:mobile_pilot/features/ai/data/ai_model_payload.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.mobilepilot/settings');
  late List<MethodCall> calls;
  late AiDeviceTools tools;
  Completer<void>? beginGate;
  late String terminalCode;
  late String scrollCode;
  late bool changed;
  late String wifiLabel;
  late int imageRevision;
  setUp(() {
    calls = [];
    beginGate = null;
    terminalCode = 'GESTURE_COMPLETED';
    scrollCode = 'ACTION_DISPATCHED';
    changed = false;
    wifiLabel = 'Wi-Fi';
    imageRevision = 3;
    tools = AiDeviceTools(targetPackage: 'app.target');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'scrollUntilUi':
              return {'code': scrollCode, 'message': 'native scroll result'};
            case 'beginCommandSession':
              await beginGate?.future;
              return null;
            case 'finishCommandSession':
            case 'cancelCommandSession':
            case 'cancelScreenActions':
            case 'cancelScreenCapture':
            case 'cancelUiWait':
              return null;
            case 'getUiTree':
              return [
                {
                  'screenId': 's1',
                  'nodeId': 'layout',
                  'packageName': 'app.target',
                },
                {
                  'screenId': 's1',
                  'nodeId': 'wifi',
                  'packageName': 'app.target',
                  'text': changed ? 'Different screen' : wifiLabel,
                  'clickable': true,
                  'enabled': true,
                  'visible': true,
                },
                {
                  'screenId': 's1',
                  'nodeId': 'input',
                  'packageName': 'app.target',
                  'text': 'Search',
                  'editable': true,
                  'enabled': true,
                },
                {
                  'screenId': 's1',
                  'nodeId': 'password',
                  'packageName': 'app.target',
                  'password': true,
                },
              ];
            case 'getCapturedScreen':
              return {
                'jpeg': Uint8List.fromList([1, 2, imageRevision]),
                'width': 1000,
                'height': 2000,
                'rotation': 0,
                'packageName': 'app.target',
              };
            case 'getPointTapResult':
              return {'code': terminalCode, 'message': 'native result'};
            case 'isAccessibilityServiceEnabled':
              return true;
            case 'getFloatingControlsEnabled':
              return false;
            case 'setFloatingControlsEnabled':
              return {'enabled': call.arguments['enabled']};
            default:
              return {
                'code': call.method.startsWith('queue')
                    ? 'ACTION_QUEUED'
                    : 'ACTION_DISPATCHED',
                'message': 'native',
              };
          }
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test('found scroll result provides a fresh reference that can be tapped immediately', () async {
    scrollCode = 'UI_FOUND';
    final result = await tools.execute('scroll_until_ui', {
      'selector': 'text',
      'value': 'Wi-Fi',
      'direction': 'down',
      'max_scrolls': 5,
      'timeout_seconds': 10,
    });
    expect(result['snapshot_id'], 'ui1');
    expect((result['matched_elements'] as List).single['nodeId'], 'wifi');
    final tap = await tools.execute('ui_action', {
      'snapshot_id': result['snapshot_id'],
      'node_id': 'wifi',
      'action': 'tap',
    });
    expect(tap['code'], 'ACTION_DISPATCHED');
    expect(calls.where((call) => call.method == 'scrollUntilUi'), hasLength(1));
  });

  test(
    'native IDs cannot be mistaken for the model snapshot reference',
    () async {
      final first = await tools.execute('read_current_ui', {});
      expect(first['snapshot_id'], 'ui1');
      final wrong = await tools.execute('ui_action', {
        'snapshot_id': 's1',
        'node_id': 'wifi',
        'action': 'tap',
      });
      expect(wrong['error'], contains('received s1, current ui1'));
      expect(calls.where((c) => c.method == 'tapElementById'), isEmpty);
      final fresh = await tools.execute('read_current_ui', {});
      expect(fresh['snapshot_id'], 'ui2');
      expect(
        (await tools.execute('ui_action', {
          'snapshot_id': fresh['snapshot_id'],
          'node_id': 'wifi',
          'action': 'tap',
        }))['code'],
        'ACTION_DISPATCHED',
      );
      expect(
        calls
            .singleWhere((c) => c.method == 'tapElementById')
            .arguments['screenId'],
        's1',
      );
    },
  );

  test(
    'pixel-only change rejects a gesture even if the UI tree is identical',
    () async {
      final capture = await tools.execute('capture_screen', {});
      imageRevision++;
      final result = await tools.execute('screen_action', {
        'capture_id': capture['capture_id'],
        'action': 'tap',
        'x': 0.5,
        'y': 0.5,
      });
      expect(result['error'], contains('Screen pixels changed'));
      expect(calls.where((call) => call.method == 'queuePointTap'), isEmpty);
    },
  );

  test('changed content in the same app rejects a screenshot action', () async {
    final capture = await tools.execute('capture_screen', {});
    changed = true;
    final result = await tools.execute('screen_action', {
      'capture_id': capture['capture_id'],
      'action': 'tap',
      'x': 0.5,
      'y': 0.5,
    });
    expect(result['error'], contains('Screen content changed'));
    expect(calls.where((call) => call.method == 'queuePointTap'), isEmpty);
  });

  test(
    'model can copy an exact label longer than both display limits',
    () async {
      wifiLabel = 'ข้อความยาว' * 30;
      final page = modelPayload(
        'read_current_ui',
        await tools.execute('read_current_ui', {}),
      );
      final label = (page['elements'] as List).first['label'];
      expect(label, wifiLabel);
      expect(
        (await tools.execute('verify_goal', {'label': label}))['status'],
        'matched',
      );
      expect(
        (await tools.execute('ui_action', {
          'label': label,
          'action': 'tap',
        }))['code'],
        'ACTION_DISPATCHED',
      );
    },
  );

  test('numeric refs map exactly and expire on a fresh read', () async {
    final first = await tools.execute('read_current_ui', {});
    final node = (first['elements'] as List).singleWhere(
      (n) => n['nodeId'] == 'wifi',
    );
    final oldRef = node['ref'];
    expect(oldRef, isA<int>());
    final second = await tools.execute('read_current_ui', {});
    expect(
      (await tools.execute('ui_action', {
        'ref': oldRef,
        'action': 'tap',
      }))['error'],
      isNotNull,
    );
    // Invalid attempts consume the snapshot; re-read before retrying.
    final latest = await tools.execute('read_current_ui', {});
    final freshRef = (latest['elements'] as List).singleWhere(
      (n) => n['nodeId'] == 'wifi',
    )['ref'];
    expect((second['elements'] as List).first['ref'], isNot(oldRef));
    expect(
      (await tools.execute('ui_action', {
        'ref': freshRef,
        'action': 'tap',
      }))['code'],
      'ACTION_DISPATCHED',
    );
    expect(
      calls
          .singleWhere((c) => c.method == 'tapElementById')
          .arguments['nodeId'],
      'wifi',
    );
  });
  test(
    'exact labels resolve current nodes and missing labels never tap',
    () async {
      await tools.execute('read_current_ui', {});
      expect(
        (await tools.execute('ui_action', {
          'label': 'Wi',
          'action': 'tap',
        }))['code'],
        'INVALID_ARGUMENT',
      );
      expect(calls.where((c) => c.method == 'tapElementById'), isEmpty);
      await tools.execute('read_current_ui', {});
      expect(
        (await tools.execute('verify_goal', {'label': 'Wi-Fi'}))['status'],
        'matched',
      );
      expect(
        (await tools.execute('ui_action', {
          'label': 'Wi-Fi',
          'action': 'tap',
        }))['code'],
        'ACTION_DISPATCHED',
      );
    },
  );
  test('goal refs derive exact full text without model copying it', () async {
    final page = await tools.execute('read_current_ui', {});
    final ref = (page['elements'] as List).singleWhere(
      (n) => n['nodeId'] == 'wifi',
    )['ref'];
    final result = await tools.execute('verify_goal', {'ref': ref});
    expect(result['status'], 'matched');
    expect((result['conditions'] as List).single['value'], 'Wi-Fi');
    expect(calls.where((c) => c.method == 'getUiTree'), hasLength(2));
  });
  test(
    'node tap uses verified target and lease, consumes the reference',
    () async {
      final page = await tools.execute('read_current_ui', {});
      expect((page['elements'] as List).first['nodeId'], 'wifi');
      final result = await tools.execute('ui_action', {
        'snapshot_id': 'ui1',
        'node_id': 'wifi',
        'action': 'tap',
      });
      expect(result['code'], 'ACTION_DISPATCHED');
      expect(result['verification_required'], isTrue);
      final tap = calls.singleWhere((c) => c.method == 'tapElementById');
      expect(tap.arguments['screenId'], 's1');
      expect(tap.arguments['targetPackage'], 'app.target');
      expect(
        tap.arguments['runId'],
        calls
            .singleWhere((c) => c.method == 'beginCommandSession')
            .arguments['sessionId'],
      );
      expect(
        (await tools.execute('ui_action', {
          'snapshot_id': 'ui1',
          'node_id': 'wifi',
          'action': 'tap',
        }))['error'],
        isNotNull,
      );
      expect(calls.where((c) => c.method == 'tapElementById').length, 1);
    },
  );
  for (final action in ['focus', 'replace', 'clear']) {
    test('editable node $action forwards text safely', () async {
      await tools.execute('read_current_ui', {});
      final result = await tools.execute('ui_action', {
        'snapshot_id': 'ui1',
        'node_id': 'input',
        'action': action,
        'text': 'ไทย',
      });
      expect(result['code'], 'ACTION_DISPATCHED');
      final call = calls.singleWhere((c) => c.method == 'editElementById');
      expect(call.arguments['action'], action);
      expect(call.arguments['text'], 'ไทย');
    });
  }
  test('password and unknown nodes never reach Android actions', () async {
    for (final node in ['password', 'unknown']) {
      await tools.execute('read_current_ui', {});
      expect(
        (await tools.execute('ui_action', {
          'snapshot_id': 'ui1',
          'node_id': node,
          'action': 'replace',
          'text': 'secret',
        }))['error'],
        isNotNull,
      );
    }
    expect(calls.where((c) => c.method == 'editElementById'), isEmpty);
  });
  const methods = {
    'tap': 'queuePointTap',
    'double_tap': 'queueDoubleTap',
    'long_press': 'queueLongPress',
    'swipe': 'queueSwipe',
    'drag': 'queueDrag',
    'pinch': 'queuePinch',
    'scroll_up': 'queueScreenAction',
    'scroll_down': 'queueScreenAction',
    'swipe_left': 'queueScreenAction',
    'swipe_right': 'queueScreenAction',
    'back': 'queueScreenAction',
    'type_text': 'queueScreenAction',
    'keyboard': 'queueScreenAction',
  };
  for (final entry in methods.entries) {
    test(
      'screen ${entry.key} waits for terminal result and consumes capture',
      () async {
        final capture = await tools.execute('capture_screen', {});
        expect(capture['status'], 'captured');
        expect(tools.takeCapturedImage(), isNotNull);
        expect(tools.takeCapturedImage(), isNull);
        final args = {
          'capture_id': capture['capture_id'],
          'action': entry.key,
          'x': 0.4,
          'y': 0.5,
          'end_x': 0.7,
          'end_y': 0.6,
          'scale': 0.5,
          'text': entry.key == 'keyboard' ? 'search' : 'ทดสอบ',
        };
        final result = await tools.execute('screen_action', args);
        expect(result['code'], 'GESTURE_COMPLETED');
        final call = calls.singleWhere((c) => c.method == entry.value);
        expect(call.arguments['packageName'], 'app.target');
        expect(call.arguments['width'], 1000);
        expect(call.arguments['runId'], isNotNull);
        expect(
          (await tools.execute('screen_action', args))['error'],
          isNotNull,
        );
        expect(calls.where((c) => c.method == entry.value).length, 1);
      },
    );
  }
  test('invalid coordinates, duration and pinch values never queue', () async {
    for (final extra in [
      {'action': 'tap', 'x': double.nan, 'y': 0.5},
      {'action': 'tap', 'x': -0.1, 'y': 0.5},
      {'action': 'long_press', 'x': 0.5, 'y': 0.5, 'duration_ms': 10},
      {'action': 'pinch', 'x': 0.5, 'y': 0.5, 'scale': 1},
      {'action': 'keyboard', 'text': 'delete_everything'},
    ]) {
      final capture = await tools.execute('capture_screen', {});
      expect(
        (await tools.execute('screen_action', {
          'capture_id': capture['capture_id'],
          ...extra,
        }))['error'],
        isNotNull,
      );
    }
    expect(calls.where((c) => c.method.startsWith('queue')), isEmpty);
  });
  test('cancel between lease request and dispatch prevents any tap', () async {
    await tools.execute('read_current_ui', {});
    beginGate = Completer<void>();
    final action = tools.execute('ui_action', {
      'snapshot_id': 'ui1',
      'node_id': 'wifi',
      'action': 'tap',
    });
    await Future<void>.delayed(Duration.zero);
    await tools.cancelAll();
    beginGate!.complete();
    expect((await action)['error'], isNotNull);
    expect(calls.where((c) => c.method == 'tapElementById'), isEmpty);
    expect(
      (await tools.execute('open_app', {'name': 'Settings'}))['code'],
      'ACTION_CANCELLED',
    );
  });
  test('terminal native failure is not reported as success', () async {
    terminalCode = 'TAP_CANCELLED';
    final capture = await tools.execute('capture_screen', {});
    final result = await tools.execute('screen_action', {
      'capture_id': capture['capture_id'],
      'action': 'tap',
      'x': 0.5,
      'y': 0.5,
    });
    expect(result['code'], 'TAP_CANCELLED');
    expect(result['status'], isNot('success'));
  });
  test('scroll is bounded and target-bound', () async {
    final result = await tools.execute('scroll_until_ui', {
      'selector': 'text',
      'value': 'Wi-Fi',
      'direction': 'down',
      'max_scrolls': 5,
      'timeout_seconds': 10,
    });
    expect(result['code'], 'ACTION_DISPATCHED');
    final call = calls.singleWhere((c) => c.method == 'scrollUntilUi');
    expect(call.arguments['maxScrolls'], 5);
    expect(call.arguments['targetPackage'], 'app.target');
    expect(call.arguments['runId'], isNotNull);
    expect(calls.where((c) => c.method == 'cancelUiWait'), isNotEmpty);
    expect(
      (await tools.execute('scroll_until_ui', {
        'selector': 'text',
        'value': 'Wi-Fi',
        'direction': 'down',
        'max_scrolls': 41,
        'timeout_seconds': 10,
      }))['error'],
      isNotNull,
    );
  });
  test('navigation, status and overlay route to native capabilities', () async {
    expect(
      (await tools.execute('device_status', {}))['accessibility_enabled'],
      isTrue,
    );
    expect(
      (await tools.execute('floating_controls', {'enabled': true}))['enabled'],
      isTrue,
    );
    expect(
      (await tools.execute('navigate', {'action': 'home'}))['code'],
      'ACTION_DISPATCHED',
    );
    expect(
      (await tools.execute('navigate', {'action': 'back'}))['code'],
      'ACTION_DISPATCHED',
    );
    expect(calls.where((c) => c.method == 'aiBack'), hasLength(1));
    expect(
      (await tools.execute('floating_controls', {'enabled': 'yes'}))['error'],
      isNotNull,
    );
  });
}
