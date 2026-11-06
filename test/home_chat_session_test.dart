import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:mobile_pilot/features/home/application/home_chat_session.dart';
import 'package:mobile_pilot/features/ai/application/ai_task_state.dart';
import 'package:mobile_pilot/features/models/domain/model_entry.dart';

void main() {
  test(
    'transcript, failure, attachment, run and draft survive reopening storage',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'mobilepilot-chat-store-',
      );
      Future<Box<dynamic>> open() =>
          Hive.openBox<dynamic>('chat-test', path: directory.path);
      final first = HomeChatSession(openStore: open);
      await first.initialize();
      first.sync(
        const [
          AiChatMessage(isUser: true, text: 'open app'),
          AiChatMessage(isUser: false, text: 'partial'),
        ],
        selection: const ModelSelection(ModelLocation.file, 'first', 'Gemma'),
        lastFailed: false,
      );
      first.attachToLastUser(
        ChatAttachment(
          name: 'photo.png',
          bytes: Uint8List.fromList([1, 2, 3]),
          mime: 'image/png',
        ),
      );
      first.setRun(0, {
        'id': 'run1',
        'state': 'running',
        'steps': [
          {'tool': 'open_app', 'state': 'running'},
        ],
      });
      first.updateDraft(
        'next request',
        const ChatAttachment(
          name: 'notes.txt',
          text: 'saved contents',
          mime: 'text/plain',
        ),
      );
      await first.flush();
      final id = first.id!;
      first.dispose();
      await first.flush();
      await Hive.box<dynamic>('chat-test').close();
      final restored = HomeChatSession(openStore: open);
      await restored.initialize();
      expect(restored.conversations, hasLength(1));
      expect(restored.draft, 'next request');
      expect(restored.draftAttachment!.text, 'saved contents');
      expect(restored.open(id), isTrue);
      expect(restored.messages.map((m) => m.text), ['open app', 'partial']);
      expect(restored.failed.last, isTrue);
      expect(restored.attachments[0]!.mime, 'image/png');
      expect(restored.attachments[0]!.bytes, [1, 2, 3]);
      expect(restored.runs[0]!['state'], 'interrupted');
      expect((restored.runs[0]!['steps'] as List).first['state'], 'unknown');
      restored.startNew();
      await restored.flush();
      await restored.delete(id);
      expect(restored.conversations, isEmpty);
      restored.dispose();
      await restored.flush();
      await Hive.box<dynamic>('chat-test').close();
      final parent = await directory.parent.resolveSymbolicLinks();
      expect(parent, await Directory.systemTemp.resolveSymbolicLinks());
      expect(
        directory.uri.pathSegments.where((s) => s.isNotEmpty).last,
        startsWith('mobilepilot-chat-store-'),
      );
      await directory.delete(recursive: true);
    },
  );
}
