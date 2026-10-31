import 'dart:io';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:mobile_pilot/features/ai/application/gemini_chat_controller.dart';
import 'package:mobile_pilot/features/ai/data/conversation_store.dart';
import 'package:mobile_pilot/features/ai/data/gemini_device_chat.dart';

class _DeviceChat extends GeminiDeviceChat {
  String? name;
  @override
  void selectTextFile(String? name, String? content) {
    this.name = name;
  }
}

void main() {
  test(
    'saved conversation can be reopened and continued with visible messages',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'mobilepilot_conversations_test_',
      );
      final box = await Hive.openBox<dynamic>(
        'conversation_test',
        path: dir.path,
      );
      final store = ConversationStore(box);
      final requests = <List<Content>>[];
      Future<String?> reply(String model, List<Content> history) async {
        requests.add(history);
        return 'คำตอบ';
      }

      final first = GeminiChatController(store: store, reply: reply);
      first.send('สวัสดี');
      while (first.busy) {
        await Future<void>.delayed(Duration.zero);
      }
      final id = first.conversationId!;
      expect(store.read(id)!['messages'], hasLength(2));
      first.dispose();
      await box.close();
      final reopened = await Hive.openBox<dynamic>(
        'conversation_test',
        path: dir.path,
      );
      final device = _DeviceChat();
      final second = GeminiChatController(
        store: ConversationStore(reopened),
        reply: reply,
        deviceChat: device,
      );
      second.selectTextFile('private.txt', 'private');
      expect(device.name, 'private.txt');
      second.openConversation(id);
      expect(device.name, isNull);
      expect(second.messages.map((m) => m.text), ['สวัสดี', 'คำตอบ']);
      second.send('ต่อ');
      while (second.busy) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(requests.last, hasLength(3));
      second.dispose();
      await reopened.close();
      await dir.delete(recursive: true);
    },
  );
}
