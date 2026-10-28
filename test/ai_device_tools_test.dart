import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/features/ai/data/ai_device_tools.dart';

void main() {
  test('saved-screen tool is offered only when a saved screen exists', () {
    expect(
      AiDeviceTools().modelDefinitions.any(
        (tool) => tool.name == 'read_ui_snapshot',
      ),
      isFalse,
    );
    expect(
      AiDeviceTools(
        snapshot: [
          {'nodeId': 'saved'},
        ],
      ).modelDefinitions.any((tool) => tool.name == 'read_ui_snapshot'),
      isTrue,
    );
  });
  test('Stop during app search prevents a later launch', () async {
    const channel = MethodChannel('com.mobilepilot/settings');
    final gate = Completer<void>();
    var launches = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'findLaunchableApps') {
            await gate.future;
            return [
              {'label': 'Settings', 'packageName': 'settings'},
            ];
          }
          if (call.method == 'launchApp') launches++;
          return null;
        });
    final tools = AiDeviceTools();
    final pending = tools.execute('open_app', {'name': 'Settings'});
    await Future<void>.delayed(Duration.zero);
    await tools.cancelAll();
    gate.complete();
    expect((await pending)['code'], 'ACTION_CANCELLED');
    expect(launches, 0);
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.mobilepilot/settings');
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test('wait validates arguments and reports the native result without screen text', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls++;
          expect(call.method, 'waitForUi');
          expect(call.arguments['targetPackage'], 'example.target');
          expect(call.arguments['timeoutMs'], 5000);
          return {
            'code': 'UI_FOUND',
            'message': 'found',
            'element': {'text': 'private'},
          };
        });
    final tools = AiDeviceTools(targetPackage: 'example.target');
    final args = {
      'selector': 'text',
      'value': 'Menu',
      'condition': 'present',
      'timeout_seconds': 5,
    };
    expect(
      (await tools.execute('wait_for_ui', {
        ...args,
        'timeout_seconds': 61,
      }))['error'],
      isNotNull,
    );
    expect(
      (await tools.execute('wait_for_ui', {
        ...args,
        'condition': 'textChanged',
      }))['error'],
      isNotNull,
    );
    expect(calls, 0);
    final result = await tools.execute('wait_for_ui', args);
    expect(result['code'], 'UI_FOUND');
    expect(result.toString(), isNot(contains('private')));
    expect(calls, 1);
  });

  test('search validates query and returns launchable apps', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'findLaunchableApps');
          expect(call.arguments['query'], 'Shopee');
          return [
            {'label': 'Shopee', 'packageName': 'example.shopee'},
          ];
        });
    final tools = AiDeviceTools();
    expect(
      (await tools.execute('find_apps', {'query': ''}))['error'],
      isNotNull,
    );
    final result = await tools.execute('find_apps', {'query': ' Shopee '});
    expect(result['apps'], [
      {'label': 'Shopee', 'packageName': 'example.shopee'},
    ]);
  });

  test(
    'snapshot is bounded, excludes passwords and declares it may be stale',
    () async {
      final source = [
        {'text': 'secret', 'password': true},
        for (var i = 0; i < 45; i++) {'text': 'button $i', 'clickable': true},
      ];
      final tools = AiDeviceTools(snapshot: source);
      source.clear();
      final result = await tools.execute('read_ui_snapshot', {});
      expect(result['source'], contains('stale'));
      expect(result['total'], 45);
      expect(result['truncated'], true);
      expect((result['elements'] as List).length, 40);
      expect(result.toString(), isNot(contains('secret')));
      expect(
        (await AiDeviceTools().execute('read_ui_snapshot', {}))['error'],
        isNotNull,
      );
      expect((await tools.execute('tap', {}))['error'], isNotNull);
    },
  );

  test(
    'opens a uniquely matched app and requires foreground confirmation',
    () async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'findLaunchableApps') {
              return [
                {'label': 'Shopee', 'packageName': 'example.shopee'},
              ];
            }
            if (call.method == 'launchApp') {
              expect(call.arguments['packageName'], 'example.shopee');
              return {'code': 'TARGET_READY'};
            }
            return null;
          });
      final result = await AiDeviceTools().execute('open_app', {
        'name': 'Shopee',
      });
      expect(result['status'], 'opened');
      expect(calls, ['findLaunchableApps', 'launchApp']);
    },
  );

  test('does not launch when the name is ambiguous or missing', () async {
    var launches = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'launchApp') launches++;
          if (call.method == 'findLaunchableApps') {
            return [
              {'label': 'Shop A', 'packageName': 'shop.a'},
              {'label': 'Shop B', 'packageName': 'shop.b'},
            ];
          }
          return null;
        });
    final tools = AiDeviceTools();
    expect(
      (await tools.execute('open_app', {'name': 'Shop'}))['status'],
      'ambiguous',
    );
    expect(
      (await tools.execute('open_app', {'name': 'Shop A'}))['status'],
      'ambiguous',
    );
    expect((await tools.execute('open_app', {'name': ''}))['error'], isNotNull);
    expect(launches, 0);
  });

  test('reports unconfirmed launch without claiming success', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'findLaunchableApps') {
            return [
              {'label': 'Shopee', 'packageName': 'example.shopee'},
            ];
          }
          throw PlatformException(
            code: 'TARGET_NOT_READY',
            message: 'ยังยืนยันไม่ได้',
          );
        });
    final result = await AiDeviceTools().execute('open_app', {
      'name': 'Shopee',
    });
    expect(result['status'], 'unconfirmed');
    expect(result['message'], 'ยังยืนยันไม่ได้');
  });

  test(
    'reads and pages the selected target UI, excluding password nodes',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'getUiTree');
            expect(call.arguments['targetPackage'], 'example.target');
            return [
              for (var i = 0; i < 85; i++)
                {
                  'screenId': 'screen-1',
                  'nodeId': 'n$i',
                  'packageName': 'example.target',
                  'text': 'item $i',
                },
              {
                'screenId': 'screen-1',
                'nodeId': 'secret',
                'packageName': 'example.target',
                'text': 'secret',
                'password': true,
              },
            ];
          });
      final tools = AiDeviceTools(targetPackage: 'example.target');
      final first = await tools.execute('read_current_ui', {});
      expect(first['status'], 'ok');
      expect(first['total'], 85);
      expect(first['next_offset'], 10);
      expect((first['elements'] as List).length, 10);
      final collected = <String>[];
      var page = first;
      while (true) {
        collected.addAll(
          (page['elements'] as List).map((node) => node['nodeId'] as String),
        );
        final next = page['next_offset'];
        if (next == null) break;
        page = await tools.execute('read_ui_page', {
          'snapshot_id': first['snapshot_id'],
          'offset': next,
        });
      }
      expect(collected, [for (var i = 0; i < 85; i++) 'n$i']);
      final last = await tools.execute('read_ui_page', {
        'snapshot_id': first['snapshot_id'],
        'offset': 80,
      });
      expect((last['elements'] as List).length, 5);
      expect(last['next_offset'], isNull);
      expect(last.toString(), isNot(contains('secret')));
      expect(
        (await tools.execute('read_ui_page', {
          'snapshot_id': 'wrong',
          'offset': 40,
        }))['error'],
        isNotNull,
      );
    },
  );

  test(
    'reports missing or unready target rather than an empty successful screen',
    () async {
      expect(
        (await AiDeviceTools().execute('read_current_ui', {}))['error'],
        isNotNull,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            throw PlatformException(
              code: 'TARGET_NOT_READY',
              message: 'target not ready',
            );
          });
      final result = await AiDeviceTools(targetPackage: 'example.target')
          .execute('read_current_ui', {});
      expect(result['code'], 'TARGET_NOT_READY');
      expect(result['error'], 'target not ready');
    },
  );

  test('opens the verified target for a later live screen read', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'findLaunchableApps') {
            return [
              {'label': 'Target', 'packageName': 'example.target'},
            ];
          }
          if (call.method == 'launchApp') return {'code': 'TARGET_READY'};
          if (call.method == 'getUiTree') {
            expect(call.arguments['targetPackage'], 'example.target');
            return [
              {
                'screenId': 's',
                'nodeId': 'n',
                'packageName': 'example.target',
                'text': 'ok',
              },
            ];
          }
          throw StateError('unexpected call');
        });
    final tools = AiDeviceTools();
    expect(
      (await tools.execute('open_app', {'name': 'Target'}))['status'],
      'opened',
    );
    expect((await tools.execute('read_current_ui', {}))['status'], 'ok');
  });
}
