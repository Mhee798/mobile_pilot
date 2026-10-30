import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/features/ai/data/ai_device_tools.dart';
import 'package:mobile_pilot/features/ai/data/ai_model_payload.dart';
import 'package:mobile_pilot/features/ai/data/ai_ui_nodes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.mobilepilot/settings');
  late List<MethodCall> calls;
  late AiDeviceTools tools;
  Completer<void>? beginGate;
  late String terminalCode;
  late String scrollCode;
  late String settingsCode;
  late bool changed;
  late int disconnectedChecks;
  late String wifiLabel;
  late int imageRevision;
  Uint8List? customImage;
  late bool changingNativeSnapshots;
  late int nativeReads;
  test('map, alarm and media dispatch are not reported as confirmed', () async {
    tools.beginTurn(userRequest: 'เปิดแผนที่เชียงใหม่');
    expect(
      (await tools.execute('open_map', {'query': 'กรุงเทพ'}))['code'],
      'INVALID_ARGUMENT',
    );
    expect(
      (await tools.execute('open_map', {'query': 'เชียงใหม่'}))['status'],
      'dispatched_unconfirmed',
    );
    expect(
      (await tools.execute('prepare_alarm', {'hour': 25, 'minute': 0}))['code'],
      'INVALID_ARGUMENT',
    );
    expect(
      (await tools.execute('prepare_alarm', {
        'hour': 8,
        'minute': 15,
      }))['status'],
      'dispatched_unconfirmed',
    );
    expect(
      (await tools.execute('media_control', {'action': 'pause'}))['status'],
      'dispatched_unconfirmed',
    );
  });
  test(
    'open link requires a complete URL from the current user request',
    () async {
      tools.beginTurn(userRequest: 'เปิด https://example.com/watch?v=1');
      expect(
        (await tools.execute('open_link', {
          'url': 'https://example.com',
        }))['code'],
        'INVALID_ARGUMENT',
      );
      expect(
        (await tools.execute('open_link', {
          'url': 'https://example.com/watch?v=1',
        }))['status'],
        'dispatched_unconfirmed',
      );
      expect(tools.targetPackage, isNull);
    },
  );
  test('selected file is available only after explicit selection', () async {
    expect(
      (await tools.execute('read_selected_file', {}))['code'],
      'NO_FILE_SELECTED',
    );
    tools.selectTextFile('example.txt', 'hello');
    expect(
      (await tools.execute('read_selected_file', {}))['file_text'],
      'hello',
    );
    tools.selectTextFile(null, null);
    expect(
      (await tools.execute('read_selected_file', {}))['code'],
      'NO_FILE_SELECTED',
    );
  });
  test('device info and media volume validate requests', () async {
    final info = await tools.execute('device_info', {});
    expect(info['battery_percent'], 42);
    expect(
      (await tools.execute('media_volume', {'action': 'get'}))['current'],
      3,
    );
    expect(
      (await tools.execute('media_volume', {
        'action': 'set',
        'value': -1,
      }))['code'],
      'INVALID_ARGUMENT',
    );
    expect(
      (await tools.execute('media_volume', {
        'action': 'set',
        'value': 5,
      }))['current'],
      5,
    );
  });
  test('editable search text cannot prove that search results exist', () async {
    final page = await tools.execute('read_current_ui', {});
    final input = (page['elements'] as List).cast<Map>().singleWhere(
      (node) => node['editable'] == true,
    );
    final result = await tools.execute('verify_goal', {'ref': input['ref']});
    expect(result['status'], 'insufficient_evidence');
    expect(result['code'], 'EDITABLE_EVIDENCE');
  });
  test(
    'observation evidence is attached by the adapter, not model refs',
    () async {
      final page = await tools.execute('read_current_ui', {});
      final ref = uiRefAlias((page['elements'] as List).first['ref'] as int);
      expect(
        (await tools.execute('report_observation', {
          'summary': 'พบรายการบนจอ',
          'evidence_refs': [ref],
        }))['status'],
        'observation_report',
      );
      await tools.execute('read_current_ui', {});
      expect(
        (await tools.execute('report_observation', {
          'summary': 'ข้อมูลเก่า',
          'evidence_refs': [ref],
        }))['status'],
        'observation_report',
      );
      final report = await tools.execute('report_observation', {
        'summary': 'พบรายการบนจอ',
      });
      expect((report['evidence'] as Map)['elements'], isNotEmpty);
      tools.invalidateObservations();
      expect(
        (await tools.execute('report_observation', {
          'summary': 'ไม่มีข้อมูล',
        }))['code'],
        'INVALID_ARGUMENT',
      );
    },
  );
  test(
    'a late alias from the previous observation never targets the new tree',
    () async {
      final old = await tools.execute('read_current_ui', {});
      final alias = uiRefAlias(
        ((old['elements'] as List).first as Map)['ref'] as int,
      );
      await tools.execute('read_current_ui', {});
      final result = await tools.execute('ui_action', {
        'ref': alias,
        'action': 'tap',
      });
      expect(result['code'], 'INVALID_ARGUMENT');
      expect(calls.where((call) => call.method == 'tapElementById'), isEmpty);
    },
  );
  test('model schemas always require a ref for acting and verifying', () {
    final action = tools.modelDefinitions.singleWhere(
      (tool) => tool.name == 'ui_action',
    );
    expect(action.parameters['required'], containsAll(['ref', 'action']));
    expect(
      (action.parameters['properties'] as Map).containsKey('label'),
      isFalse,
    );
    final verify = tools.modelDefinitions.singleWhere(
      (tool) => tool.name == 'verify_goal',
    );
    expect(verify.parameters['required'], contains('ref'));
  });
  test(
    'settings shortcut exposes and accepts common Android destinations',
    () async {
      final tool = tools.modelDefinitions.singleWhere(
        (t) => t.name == 'open_system_settings',
      );
      final destinations =
          ((tool.parameters['properties'] as Map)['destination'] as Map)['enum']
              as List;
      expect(
        destinations,
        containsAll([
          'cast',
          'nfc',
          'language',
          'date_time',
          'vpn',
          'notifications',
        ]),
      );
      for (final destination in [
        'cast',
        'nfc',
        'language',
        'vpn',
        'notifications',
      ]) {
        expect(
          (await tools.execute('open_system_settings', {
            'destination': destination,
          }))['status'],
          'opened',
        );
      }
    },
  );
  test(
    'settings shortcut confirms target and rejects invalid destinations',
    () async {
      final bad = await tools.execute('open_system_settings', {
        'destination': 'unknown',
      });
      expect(bad['code'], 'INVALID_ARGUMENT');
      expect(calls.where((c) => c.method == 'openSystemSettings'), isEmpty);
      final missing = await tools.execute('open_system_settings', {
        'destination': 'app_details',
      });
      expect(missing['code'], 'INVALID_ARGUMENT');
      final opened = await tools.execute('open_system_settings', {
        'destination': 'wifi',
      });
      expect(opened['status'], 'opened');
      expect(tools.targetPackage, 'com.android.settings');
      expect(opened['note'], contains('not been changed'));
      settingsCode = 'TARGET_NOT_READY';
      final unconfirmed = await tools.execute('open_system_settings', {
        'destination': 'bluetooth',
      });
      expect(unconfirmed['status'], 'unconfirmed');
      expect(tools.targetPackage, isNull);
    },
  );
  test(
    'tap text without a target explains ref instead of requesting snapshot',
    () async {
      await tools.execute('read_current_ui', {});
      final result = await tools.execute('ui_action', {
        'action': 'tap',
        'text': 'Search',
      });
      expect(result['code'], 'INVALID_ARGUMENT');
      expect(result['error'], contains('requires ref'));
      expect(result['error'], contains('text is replacement content only'));
      expect(calls.where((call) => call.method == 'tapElementById'), isEmpty);
    },
  );
  setUp(() {
    calls = [];
    beginGate = null;
    terminalCode = 'GESTURE_COMPLETED';
    scrollCode = 'ACTION_DISPATCHED';
    settingsCode = 'TARGET_READY';
    changed = false;
    disconnectedChecks = 0;
    wifiLabel = 'Wi-Fi';
    imageRevision = 3;
    customImage = null;
    changingNativeSnapshots = false;
    nativeReads = 0;
    tools = AiDeviceTools(targetPackage: 'app.target');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'getDeviceReadiness':
              return {
                'connected': disconnectedChecks-- <= 0,
                'hasWindow': true,
              };
            case 'getDeviceInfo':
              return {'model': 'test-device', 'battery_percent': 42};
            case 'getMediaVolume':
              return {'current': 3, 'maximum': 15};
            case 'setMediaVolume':
              return {'current': call.arguments['value'], 'maximum': 15};
            case 'openLink':
            case 'openMap':
            case 'prepareAlarm':
            case 'mediaControl':
              return {'code': 'INTENT_DISPATCHED'};
            case 'openSystemSettings':
              return {
                'code': settingsCode,
                'packageName': 'com.android.settings',
              };
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
              nativeReads++;
              return [
                {
                  'screenId': changingNativeSnapshots ? 's$nativeReads' : 's1',
                  'nodeId': 'layout',
                  'packageName': 'app.target',
                },
                {
                  'screenId': changingNativeSnapshots ? 's$nativeReads' : 's1',
                  'nodeId': 'wifi',
                  'packageName': 'app.target',
                  'text': changed ? 'Different screen' : wifiLabel,
                  'clickable': true,
                  'enabled': true,
                  'visible': true,
                },
                {
                  'screenId': changingNativeSnapshots ? 's$nativeReads' : 's1',
                  'nodeId': 'input',
                  'packageName': 'app.target',
                  'text': 'Search',
                  'editable': true,
                  'enabled': true,
                },
                {
                  'screenId': changingNativeSnapshots ? 's$nativeReads' : 's1',
                  'nodeId': 'password',
                  'packageName': 'app.target',
                  'password': true,
                },
              ];
            case 'getCapturedScreen':
              return {
                'jpeg':
                    customImage ?? Uint8List.fromList([1, 2, imageRevision]),
                'width': 1000,
                'height': 2000,
                'rotation': 0,
                'packageName': 'app.target',
              };
            case 'getPointTapResult':
              return {'code': terminalCode, 'message': 'native result'};
            case 'editElementById':
              if (changingNativeSnapshots) {
                return {
                  'code': call.arguments['screenId'] == 's$nativeReads'
                      ? 'INPUT_DISPATCHED'
                      : 'STALE_SCREEN',
                };
              }
              return {'code': 'ACTION_DISPATCHED'};
            case 'aiKeyboard':
              return {'code': 'IME_DISPATCHED'};
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

  test(
    'capture publishes new UI references before model types into the input',
    () async {
      changingNativeSnapshots = true;
      await tools.execute('read_current_ui', {});
      final capture = await tools.execute('capture_screen', {});
      expect(capture['status'], 'captured');
      expect(capture['ui_after_capture']['status'], 'ok');
      expect(
        (capture['ui_after_capture']['elements'] as List).any(
          (node) => node['label'] == 'Search',
        ),
        isTrue,
      );
      expect(tools.takeCapturedImage(), [1, 2, 3]);
      final result = await tools.execute('ui_action', {
        'label': 'Search',
        'action': 'replace',
        'text': 'MacBook',
      });
      expect(result['code'], 'INPUT_DISPATCHED');
      final edit = calls.singleWhere(
        (call) => call.method == 'editElementById',
      );
      expect(edit.arguments['screenId'], 's$nativeReads');
    },
  );

  test(
    'keyboard search submits without a screenshot and rejects invalid keys',
    () async {
      final invalid = await tools.execute('keyboard_action', {'key': 'buy'});
      expect(invalid['code'], 'INVALID_ARGUMENT');
      expect(calls.where((call) => call.method == 'aiKeyboard'), isEmpty);
      final result = await tools.execute('keyboard_action', {'key': 'search'});
      expect(result['code'], 'IME_DISPATCHED');
      final sent = calls.singleWhere((call) => call.method == 'aiKeyboard');
      expect(sent.arguments['targetPackage'], 'app.target');
      expect(sent.arguments['runId'], startsWith('ai-action-'));
      expect(calls.where((call) => call.method == 'armScreenCapture'), isEmpty);
    },
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

  test(
    'allows unrelated image changes but rejects changes near the tap',
    () async {
      Future<Uint8List> picture(ui.Rect rectangle) async {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
        canvas.drawRect(
          rectangle,
          ui.Paint()..color = const ui.Color(0xff000000),
        );
        final image = await recorder.endRecording().toImage(100, 100);
        try {
          return (await image.toByteData(format: ui.ImageByteFormat.png))!
              .buffer
              .asUint8List();
        } finally {
          image.dispose();
        }
      }

      customImage = await picture(const ui.Rect.fromLTWH(0, 0, 10, 10));
      var capture = await tools.execute('capture_screen', {});
      customImage = await picture(const ui.Rect.fromLTWH(0, 0, 20, 10));
      var result = await tools.execute('screen_action', {
        'capture_id': capture['capture_id'],
        'action': 'tap',
        'x': .5,
        'y': .5,
      });
      expect(result['code'], 'GESTURE_COMPLETED');
      capture = await tools.execute('capture_screen', {});
      customImage = await picture(const ui.Rect.fromLTWH(48, 48, 5, 5));
      final before = calls
          .where((call) => call.method == 'queuePointTap')
          .length;
      result = await tools.execute('screen_action', {
        'capture_id': capture['capture_id'],
        'action': 'tap',
        'x': .5,
        'y': .5,
      });
      expect(result['error'], contains('Screen pixels changed'));
      expect(
        calls.where((call) => call.method == 'queuePointTap').length,
        before,
      );
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
      final label = (page['elements'] as List).singleWhere(
        (node) => node['label'] == wifiLabel,
      )['label'];
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

  test('temporary service disconnection waits before dispatch, never replays a tap', () async {
    await tools.execute('read_current_ui', {});
    disconnectedChecks = 2;
    final result = await tools.execute('ui_action', {
      'label': 'Wi-Fi',
      'action': 'tap',
    });
    expect(result['code'], 'ACTION_DISPATCHED');
    expect(
      calls.where((call) => call.method == 'getDeviceReadiness'),
      hasLength(3),
    );
    expect(
      calls.where((call) => call.method == 'tapElementById'),
      hasLength(1),
    );
  });

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
      expect(
        (page['elements'] as List).any((node) => node['nodeId'] == 'wifi'),
        isTrue,
      );
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
