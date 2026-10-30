import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/features/ai/data/ai_ui_nodes.dart';
import 'package:mobile_pilot/features/ai/data/ai_device_tools.dart';
import 'package:flutter/services.dart';

void main() {
  test('short aliases round trip without reusing an earlier reference', () {
    final aliases = <String>{};
    for (var ref = 1; ref <= 10000; ref++) {
      final alias = uiRefAlias(ref);
      expect(parseUiRef(alias), ref);
      expect(aliases.add(alias), isTrue);
    }
    expect(uiRefAlias(1), 'A');
    expect(uiRefAlias(26), 'Z');
    expect(uiRefAlias(27), 'AA');
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  test('UI refs accept exact positive integers only', () {
    for (final value in <Object>[12, 12.0, '12']) {
      expect(parseUiRef(value), 12);
    }
    for (final value in <Object?>[
      null,
      0,
      -1,
      1.5,
      'ui12',
      '12x',
      double.infinity,
    ]) {
      expect(parseUiRef(value), isNull);
    }
  });
  test('label resolves to its closest clickable parent, never a sibling or disabled node', () {
    final label = <String, dynamic>{'nodeId': 'node-0.1.2', 'text': 'Wi-Fi'};
    final nodes = [
      <String, dynamic>{'nodeId': 'node-0', 'clickable': true},
      <String, dynamic>{'nodeId': 'node-0.1', 'clickable': true},
      <String, dynamic>{'nodeId': 'node-0.1.2.0', 'clickable': true},
      label,
    ];
    expect(tapNodeId(label, nodes), 'node-0.1');
    nodes[1]['enabled'] = false;
    expect(tapNodeId(label, nodes), 'node-0');
    nodes[0]['password'] = true;
    expect(tapNodeId(label, nodes), isNull);
  });
  test(
    'unnamed clickable containers cannot hide menu labels on the first page',
    () async {
      const channel = MethodChannel('com.mobilepilot/settings');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => [
              for (var i = 0; i < 15; i++)
                {
                  'screenId': 's',
                  'nodeId': 'container$i',
                  'packageName': 'target',
                  'clickable': true,
                },
              {
                'screenId': 's',
                'nodeId': 'wifi',
                'packageName': 'target',
                'text': 'Wi-Fi',
                'clickable': true,
              },
            ],
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final result = await AiDeviceTools(targetPackage: 'target')
          .execute('read_current_ui', {});
      expect((result['elements'] as List).first['text'], 'Wi-Fi');
      expect(result['total'], 16);
      expect(result['next_offset'], 10);
    },
  );
}
