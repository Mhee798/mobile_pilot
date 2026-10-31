import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/features/ai/application/gemini_chat_controller.dart';
import 'package:mobile_pilot/features/ai/data/gemini_device_chat.dart';
import 'package:mobile_pilot/features/ai/application/ai_task_phase.dart';

GenerateContentResponse response(Content content) =>
    GenerateContentResponse([Candidate(content, null, null, null, null)], null);

Future<void> untilIdle(GeminiChatController chat) async {
  while (chat.busy) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test(
    'keeps conversation between messages and resets on model change',
    () async {
      final requests = <List<Content>>[];
      final chat = GeminiChatController(
        reply: (_, history) async {
          requests.add(history);
          return 'ตอบแล้ว';
        },
      );
      expect(chat.send('สวัสดี'), isTrue);
      await untilIdle(chat);
      expect(chat.send('ต่อ'), isTrue);
      await untilIdle(chat);
      expect(requests.map((e) => e.length), [1, 3]);
      chat.setModel('another-model');
      expect(chat.messages, isEmpty);
      chat.dispose();
    },
  );

  test('app choice resumes the tool task and records the answer', () async {
    var round = 0;
    String? selected;
    final chat = GeminiChatController(
      initializeFirebase: () async {},
      deviceChat: GeminiDeviceChat(
        generate: (_) async => round++ == 0
            ? response(
                Content.model([
                  const FunctionCall('open_app', {'name': 'ตั้งค่า'}),
                ]),
              )
            : response(Content.model([TextPart('เปิดแล้ว')])),
        execute: (_, _) async => {
          'status': 'ambiguous',
          'apps': [
            {'label': 'ตั้งค่า', 'packageName': 'example.settings'},
          ],
        },
        openSelected: (package) async {
          selected = package;
          return {'status': 'opened'};
        },
      ),
    );
    chat.setToolsEnabled(true);
    final phases = <AiTaskPhase>[];
    chat.addListener(() {
      phases.add(chat.phase);
      if (chat.apps.isNotEmpty) chat.resolveChoice('example.settings');
    });
    chat.send('เปิดตั้งค่า');
    await untilIdle(chat);
    expect(selected, 'example.settings');
    expect(chat.messages.last.text, 'เปิดแล้ว');
    expect(
      phases,
      containsAllInOrder([
        AiTaskPhase.thinking,
        AiTaskPhase.usingTool,
        AiTaskPhase.waitingForUser,
        AiTaskPhase.responded,
      ]),
    );
    chat.dispose();
  });
}
