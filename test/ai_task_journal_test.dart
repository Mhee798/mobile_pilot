import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/features/ai/data/ai_task_journal.dart';

void main() {
  test(
    'restores uncertain work without executing or retaining a native reference',
    () async {
      final dir = await Directory.systemTemp.createTemp('mobilepilot-journal-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/task.json');
      final journal = AiTaskJournal(file: () async => file);
      await journal.save('เปิดแอปแล้วอ่านสถานะ', 'running');
      final restored = await AiTaskJournal(file: () async => file)
          .readInterrupted();
      expect(restored?['request'], 'เปิดแอปแล้วอ่านสถานะ');
      expect(restored?.containsKey('snapshot_id'), isFalse);
      await journal.save('เดิม', 'awaiting_choice');
      expect(await journal.readInterrupted(), isNotNull);
      await journal.save('เดิม', 'ended');
      expect(await journal.readInterrupted(), isNull);
    },
  );
}
