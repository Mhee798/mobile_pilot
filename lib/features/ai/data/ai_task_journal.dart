import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// A recovery notice, never an executable queue. No screenshots or node IDs.
class AiTaskJournal {
  AiTaskJournal({Future<File> Function()? file}) : _file = file ?? _defaultFile;
  final Future<File> Function() _file;
  Future<void> _tail = Future.value();
  static Future<File> _defaultFile() async => File(
    '${(await getApplicationSupportDirectory()).path}/ai_task_checkpoint.json',
  );

  Future<Map<String, dynamic>?> readInterrupted() async {
    await _tail;
    final file = await _file();
    if (!await file.exists()) return null;
    final data = jsonDecode(await file.readAsString());
    if (data is! Map ||
        data['request'] is! String ||
        !{'running', 'awaiting_choice'}.contains(data['state'])) {
      return null;
    }
    return Map<String, dynamic>.from(data);
  }

  Future<void> save(String request, String state, {String? lastTool}) {
    final operation = _tail.then((_) async {
      final file = await _file();
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(
        jsonEncode({
          'request': request,
          'state': state,
          'last_tool': lastTool,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }),
        flush: true,
      );
      await temp.rename(file.path);
    });
    _tail = operation.catchError((_) {});
    return operation;
  }
}
