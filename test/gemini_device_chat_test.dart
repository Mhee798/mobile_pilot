import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/features/ai/data/gemini_device_chat.dart';

GenerateContentResponse response(Content content) =>
    GenerateContentResponse([Candidate(content, null, null, null, null)], null);

void main() {
  test(
    'stops repeated stale image taps without consuming all rounds',
    () async {
      var turn = 0;
      var taps = 0;
      final chat = GeminiDeviceChat(
        generate: (_) async {
          turn++;
          return response(
            Content.model([
              FunctionCall('screen_action', {
                'action': 'tap',
                'capture_id': 'c$turn',
                'x': .5,
                'y': .5,
              }),
            ]),
          );
        },
        execute: (_, _) async {
          taps++;
          return {
            'code': 'INVALID_ARGUMENT',
            'error': 'Screen pixels changed before coordinate action.',
          };
        },
      );
      final (answer, _) = await chat.run(
        model: 'test',
        history: [Content.text('แตะ')],
        progress: (_) {},
        allowImages: true,
      );
      expect(taps, 2);
      expect(answer, contains('หยุด'));
    },
  );
  test('exposes every available device definition to Gemini', () {
    final chat = GeminiDeviceChat();
    expect(
      chat.declarations.map((item) => item.name),
      containsAll([
        'open_app',
        'open_system_settings',
        'find_apps',
        'read_current_ui',
        'read_ui_page',
        'ui_action',
        'keyboard_action',
        'capture_screen',
        'screen_action',
        'scroll_until_ui',
        'navigate',
        'device_status',
        'floating_controls',
        'cancel_actions',
        'wait_for_ui',
        'verify_goal',
        'report_observation',
      ]),
    );
  });

  test(
    'capture is blocked until enabled and image is included when allowed',
    () async {
      for (final allowed in [false, true]) {
        var requests = 0;
        var captures = 0;
        final chat = GeminiDeviceChat(
          generate: (history) async {
            if (requests++ == 0) {
              return response(
                Content.model([const FunctionCall('capture_screen', {})]),
              );
            }
            expect(
              history.last.parts.whereType<InlineDataPart>().length,
              allowed ? 1 : 0,
            );
            final result = history.last.parts
                .whereType<FunctionResponse>()
                .single
                .response;
            expect(result.containsKey('error'), !allowed);
            return response(Content.model([TextPart('เสร็จ')]));
          },
          execute: (_, _) async {
            captures++;
            return {'status': 'captured', 'capture_id': 'c1'};
          },
          takeCapturedImage: () => Uint8List.fromList([1, 2, 3]),
        );
        await chat.run(
          model: 'test',
          history: [Content.text('ดูหน้าจอ')],
          progress: (_) {},
          allowImages: allowed,
        );
        expect(captures, allowed ? 1 : 0);
      }
    },
  );
  test('opens selected ambiguous app and resumes the original task', () async {
    var turn = 0;
    String? opened;
    final chat = GeminiDeviceChat(
      generate: (history) async {
        if (turn++ == 0) {
          return response(
            Content.model([
              const FunctionCall('open_app', {'name': 'ตั้งค่า'}),
            ]),
          );
        }
        expect(
          (history.last.parts.single as FunctionResponse).response['status'],
          'opened',
        );
        return response(Content.model([TextPart('ทำต่อแล้ว')]));
      },
      execute: (_, _) async => {
        'status': 'ambiguous',
        'apps': [
          {'label': 'ตั้งค่า A', 'packageName': 'app.a'},
          {'label': 'ตั้งค่า B', 'packageName': 'app.b'},
        ],
      },
      openSelected: (packageName) async {
        opened = packageName;
        return {'status': 'opened'};
      },
    );
    final (answer, _) = await chat.run(
      model: 'test',
      history: [Content.text('เปิดตั้งค่าแล้วอ่านหน้า')],
      progress: (_) {},
      chooseApp: (apps) async => apps.last['packageName'],
    );
    expect(opened, 'app.b');
    expect(answer, 'ทำต่อแล้ว');
    expect(turn, 2);
  });
  test(
    'returns each tool result to Gemini and continues until final response',
    () async {
      final requests = <List<Content>>[];
      final calls = <String>[];
      final recorded = <String>[];
      final outputs = [
        response(
          Content.model([
            const FunctionCall('open_app', {'name': 'Settings'}),
          ]),
        ),
        response(Content.model([const FunctionCall('read_current_ui', {})])),
        response(
          Content.model([
            const FunctionCall('ui_action', {'ref': 'r1', 'action': 'tap'}),
          ]),
        ),
        response(Content.model([TextPart('เปิดหน้า Wi-Fi แล้ว')])),
      ];
      final chat = GeminiDeviceChat(
        generate: (history) async {
          requests.add(history);
          return outputs.removeAt(0);
        },
        execute: (name, args) async {
          calls.add(name);
          return {'status': 'ok'};
        },
      );
      final (answer, history) = await chat.run(
        model: 'test',
        history: [Content.text('เปิด Wi-Fi')],
        progress: (_) {},
        onStepStart: (name, args) {
          recorded.add(name);
          return recorded.length;
        },
        onStepEnd: (step, result, elapsed) async {
          recorded.add('result:$step:${result['status']}');
        },
      );
      expect(calls, ['open_app', 'read_current_ui', 'ui_action']);
      expect(recorded, [
        'open_app',
        'result:1:ok',
        'read_current_ui',
        'result:3:ok',
        'ui_action',
        'result:5:ok',
      ]);
      expect(requests[1].last.parts.single, isA<FunctionResponse>());
      expect(requests[2].last.parts.single, isA<FunctionResponse>());
      expect(answer, 'เปิดหน้า Wi-Fi แล้ว');
      expect(history.last.role, 'model');
    },
  );

  test('does not execute a tool outside the allowed set', () async {
    var executions = 0;
    var turn = 0;
    final chat = GeminiDeviceChat(
      generate: (_) async => turn++ == 0
          ? response(Content.model([const FunctionCall('unknown_tool', {})]))
          : response(Content.model([TextPart('หยุด')])),
      execute: (_, _) async {
        executions++;
        return {};
      },
    );
    await chat.run(
      model: 'test',
      history: [Content.text('ทดสอบ')],
      progress: (_) {},
    );
    expect(executions, 0);
  });
}
