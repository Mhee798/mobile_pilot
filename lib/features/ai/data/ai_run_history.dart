import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Display-only diagnostic records. Never replayed or sent back to the model.
class AiRunHistory extends ChangeNotifier {
  AiRunHistory({Future<File> Function()? file}) : _file = file ?? _defaultFile;
  final Future<File> Function() _file;
  static const maxRuns = 30;
  static const maxSteps = 40;
  final _runs = <Map<String, dynamic>>[];
  Future<void> _tail = Future.value();
  Future<void>? _loading;
  Future<void> flush() => _tail;
  String? error;
  int _sequence = 0;
  List<Map<String, dynamic>> get runs =>
      List.unmodifiable(_runs.map((run) => Map<String, dynamic>.from(run)));

  static Future<File> _defaultFile() async => File(
    '${(await getApplicationSupportDirectory()).path}/ai_run_history.json',
  );

  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! List) throw const FormatException('Invalid history');
        for (final raw in decoded.take(maxRuns).whereType<Map>()) {
          final run = Map<String, dynamic>.from(raw);
          if (run['id'] is! String ||
              run['request'] is! String ||
              run['steps'] is! List) {
            continue;
          }
          run['steps'] = (run['steps'] as List)
              .take(maxSteps)
              .whereType<Map>()
              .map((step) => Map<String, dynamic>.from(step))
              .toList();
          if (run['state'] == 'running') {
            run['state'] = 'interrupted';
            for (final step in (run['steps'] as List).whereType<Map>()) {
              if (step['state'] == 'running') step['state'] = 'unknown';
            }
          }
          _runs.add(run);
        }
      }
    } catch (exception) {
      error = 'อ่านประวัติไม่สำเร็จ: $exception';
    }
    notifyListeners();
  }

  Future<String> start(
    String request,
    String model, {
    required bool tools,
    required bool image,
    bool? vision,
  }) async {
    await load();
    final id = '${DateTime.now().microsecondsSinceEpoch}-${++_sequence}';
    _runs.insert(0, {
      'id': id,
      'request': _clip(request),
      'model': _clip(model),
      'tools': tools,
      'image_attached': image,
      'vision_enabled': ?vision,
      'started_at': DateTime.now().toUtc().toIso8601String(),
      'state': 'running',
      'steps': <Map<String, dynamic>>[],
    });
    if (_runs.length > maxRuns) _runs.removeRange(maxRuns, _runs.length);
    await _save();
    return id;
  }

  int? beginStep(String runId, String tool, Map<String, dynamic> args) {
    final run = _find(runId);
    if (run == null) return null;
    final steps = run['steps'] as List;
    final stepId = run['next_step_id'] as int? ?? steps.length;
    run['next_step_id'] = stepId + 1;
    steps.add({
      'step_id': stepId,
      'tool': tool,
      'arguments': _details(args),
      'state': 'running',
      'started_at': DateTime.now().toUtc().toIso8601String(),
    });
    if (steps.length > maxSteps) {
      steps.removeAt(0);
      run['older_steps_omitted'] =
          (run['older_steps_omitted'] as int? ?? 0) + 1;
    }
    _save();
    return stepId;
  }

  Future<void> endStep(
    String runId,
    int? index,
    Map<String, dynamic> result,
    int elapsedMs,
  ) async {
    final run = _find(runId);
    if (run == null || index == null) return;
    final matches = (run['steps'] as List)
        .whereType<Map<String, dynamic>>()
        .where((step) => step['step_id'] == index);
    if (matches.isEmpty) return;
    final step = matches.single;
    step.addAll({
      'state': 'returned',
      'result': _details(result),
      'elapsed_ms': elapsedMs,
    });
    await _save();
  }

  Future<void> finish(
    String id,
    String state,
    String reason,
    String answer,
    int elapsedMs, {
    String? taskState,
  }) async {
    final run = _find(id);
    if (run == null) return;
    run.addAll({
      'state': state,
      'reason': _clip(reason),
      'answer': _clip(answer),
      'elapsed_ms': elapsedMs,
      'ended_at': DateTime.now().toUtc().toIso8601String(),
      if (taskState != null) 'task_state': _details(taskState),
    });
    for (final step in (run['steps'] as List).whereType<Map>()) {
      if (step['state'] == 'running') step['state'] = 'unknown';
    }
    await _save();
  }

  Future<void> clear() async {
    await load();
    if (_runs.any((run) => run['state'] == 'running')) return;
    _runs.clear();
    await _save();
  }

  /// An immutable snapshot of retained diagnostics, including unfinished runs.
  Future<String> exportJson({String? runId}) async {
    await load();
    final selected = runId == null ? _runs : [_find(runId)];
    if (selected.any((run) => run == null)) {
      throw StateError('ไม่พบงานนี้ในประวัติแล้ว');
    }
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'mobilepilot.ai_run_history',
      'schema_version': 1,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'note': 'Retained diagnostic snapshot; details may be truncated. No screenshots. Not a replay queue.',
      'runs': selected,
    });
  }

  Map<String, dynamic>? _find(String id) {
    for (final run in _runs) {
      if (run['id'] == id) return run;
    }
    return null;
  }

  Future<void> _save() {
    // Keep total write cost bounded, not just the number of entries.
    while (_runs.length > 1 &&
        utf8.encode(jsonEncode(_runs)).length > 512 * 1024) {
      _runs.removeLast();
    }
    // Snapshot before queueing: later mutations cannot alter an earlier write.
    final data = jsonEncode(_runs);
    notifyListeners();
    _tail = _tail.then((_) async {
      try {
        final file = await _file();
        await file.parent.create(recursive: true);
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(data, flush: true);
        await temp.rename(file.path);
        error = null;
      } catch (exception) {
        error = 'บันทึกประวัติไม่สำเร็จ: $exception';
      }
      notifyListeners();
    });
    return _tail;
  }

  static String _clip(String value) =>
      value.length > 2000 ? '${value.substring(0, 2000)} [ตัดข้อความ]' : value;

  static Object? _details(Object? value) {
    final result = _bounded(value);
    final encoded = jsonEncode(result);
    return utf8.encode(encoded).length > 6000 ? _clip(encoded) : result;
  }

  static Object? _bounded(Object? value, [int depth = 0]) {
    if (depth > 4) return '[ตัดรายละเอียด]';
    if (value == null || value is bool || value is num) return value;
    if (value is String) return _clip(value);
    if (value is List<int>) return '[ไม่เก็บข้อมูลไบนารี]';
    if (value is List) {
      return value.take(12).map((v) => _bounded(v, depth + 1)).toList();
    }
    if (value is Map) {
      return {
        for (final entry in value.entries.take(24))
          if (!{
            'jpeg',
            'image',
            'imageBytes',
            'icon',
            'iconBase64',
            'file_text',
          }.contains(entry.key))
            entry.key.toString(): _bounded(entry.value, depth + 1),
      };
    }
    return '[ไม่เก็บข้อมูลชนิดนี้]';
  }
}
