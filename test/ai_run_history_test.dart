import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/features/ai/data/ai_run_history.dart';
import 'package:mobile_pilot/features/ai/data/ai_model_service.dart';
import 'package:mobile_pilot/features/ai/data/ai_device_tools.dart';
import 'package:mobile_pilot/features/ai/presentation/screen/ai_history_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.mobilepilot/settings');
  late Directory directory;
  late File file;
  late AiRunHistory history;
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    directory = await Directory.systemTemp.createTemp('mp-history-');
    file = File('${directory.path}/history.json');
    history = AiRunHistory(file: () async => file);
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  test('selected file contents are excluded from diagnostics', () async {
    final id = await history.start(
      'อ่านไฟล์',
      'model',
      tools: true,
      image: false,
    );
    final step = history.beginStep(id, 'read_selected_file', {});
    await history.endStep(id, step, {
      'name': 'notes.txt',
      'file_text': 'private file body',
    }, 1);
    final exported = await history.exportJson();
    expect(exported, isNot(contains('private file body')));
    expect(exported, contains('notes.txt'));
  });

  test(
    'stores actual arguments/results and timing without binary images',
    () async {
      final id = await history.start(
        'เปิดตั้งค่า',
        'model-file',
        tools: true,
        image: true,
      );
      final step = history.beginStep(id, 'ui_action', {
        'label': 'Wi-Fi',
        'action': 'tap',
      });
      await history.endStep(id, step, {
        'error': 'ambiguous',
        'jpeg': Uint8List(100),
      }, 321);
      await history.finish(
        id,
        'stopped',
        'repeated_error',
        'ยังไม่สำเร็จ',
        1000,
      );
      final restored = AiRunHistory(file: () async => file);
      await restored.load();
      final run = restored.runs.single;
      expect(run['state'], 'stopped');
      final saved = (run['steps'] as List).single;
      expect(saved['arguments']['label'], 'Wi-Fi');
      expect(saved['result']['error'], 'ambiguous');
      expect(saved['result'].containsKey('jpeg'), isFalse);
      expect(saved['elapsed_ms'], 321);
    },
  );

  test('interrupted work is displayed as uncertain, never replayed', () async {
    final id = await history.start(
      'request',
      'model',
      tools: true,
      image: false,
    );
    history.beginStep(id, 'open_app', {'name': 'Settings'});
    await history.flush();
    final restored = AiRunHistory(file: () async => file);
    await restored.load();
    expect(restored.runs.single['state'], 'interrupted');
    expect((restored.runs.single['steps'] as List).single['state'], 'unknown');
  });

  test(
    'clear persists and later completion cannot restore deleted history',
    () async {
      final id = await history.start(
        'request',
        'model',
        tools: false,
        image: false,
      );
      await history.finish(id, 'responded', '', 'hello', 1);
      await history.clear();
      await history.finish(id, 'responded', '', 'late', 2);
      expect(jsonDecode(await file.readAsString()), isEmpty);
    },
  );

  test('retention and detail bounds apply before disk writes', () async {
    for (var i = 0; i <= AiRunHistory.maxRuns; i++) {
      final id = await history.start('$i', 'model', tools: false, image: false);
      final step = history.beginStep(id, 'read_current_ui', {
        'text': 'x' * 100000,
      });
      await history.endStep(id, step, {'text': 'y' * 100000}, 1);
      await history.finish(id, 'responded', '', '', 1);
    }
    expect(history.runs, hasLength(AiRunHistory.maxRuns));
    expect(history.runs.last['request'], '1');
    expect(await file.length(), lessThan(200000));
  });

  test(
    'persistence errors do not prevent model failure from being reported',
    () async {
      final broken = AiRunHistory(
        file: () async => throw FileSystemException('unavailable'),
      );
      final service = AiModelService(history: broken);
      await expectLater(service.generate('hello', (_) {}), throwsStateError);
      expect(broken.runs.single['state'], 'failed');
      expect(broken.error, contains('บันทึกประวัติไม่สำเร็จ'));
    },
  );

  testWidgets('history exposes steps and supports confirmed clear', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final id = await history.start(
        'เปิดตั้งค่า',
        'model',
        tools: true,
        image: false,
      );
      final step = history.beginStep(id, 'ui_action', {'label': 'Wi-Fi'});
      await history.endStep(id, step, {'error': 'ambiguous'}, 5);
      await history.finish(id, 'stopped', 'repeated_error', 'not verified', 10);
    });
    await tester.pumpWidget(MaterialApp(home: AiHistoryPage(history: history)));
    await tester.tap(find.text('เปิดตั้งค่า'));
    await tester.pumpAndSettle();
    expect(find.text('1. ui_action'), findsOneWidget);
    await tester.tap(find.byTooltip('ล้างประวัติ'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'ล้างประวัติ'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('ยังไม่มีประวัติการทำงาน'), findsOneWidget);
  });

  test(
    'export includes Thai arguments, model, result and a stable snapshot',
    () async {
      final id = await history.start(
        'ค้นหาแอปตั้งค่า',
        'model-4b',
        tools: true,
        image: false,
      );
      final step = history.beginStep(id, 'find_apps', {'query': 'ตั้งค่า'});
      await history.endStep(id, step, {
        'apps': [
          {'label': 'การตั้งค่า'},
        ],
      }, 20);
      final snapshot = await history.exportJson();
      await history.finish(id, 'responded', '', 'พบแอป', 50);
      final data = jsonDecode(utf8.decode(utf8.encode(snapshot)));
      expect(data['schema_version'], 1);
      final run = (data['runs'] as List).single;
      expect(run['state'], 'running');
      expect(run['model'], 'model-4b');
      expect(run['steps'][0]['arguments']['query'], 'ตั้งค่า');
      expect(run['steps'][0]['result']['apps'][0]['label'], 'การตั้งค่า');
      expect(history.runs.single['state'], 'responded');
    },
  );

  test(
    'single-run export excludes other tasks and rejects an expired task',
    () async {
      final id = await history.start(
        'first',
        'model',
        tools: false,
        image: false,
      );
      await history.finish(id, 'responded', '', '', 1);
      await history.start('second', 'model', tools: false, image: false);
      final data = jsonDecode(await history.exportJson(runId: id));
      expect((data['runs'] as List).single['request'], 'first');
      await expectLater(history.exportJson(runId: 'missing'), throwsStateError);
    },
  );

  test('long tasks retain latest steps with stable IDs, not results on wrong steps', () async {
    final id = await history.start(
      'long task',
      'model',
      tools: true,
      image: false,
      vision: true,
    );
    final old = history.beginStep(id, 'old', {});
    int? latest;
    for (var i = 0; i < AiRunHistory.maxSteps + 2; i++) {
      latest = history.beginStep(id, 'step-$i', {'i': i});
    }
    await history.endStep(id, old, {'error': 'late old result'}, 1);
    await history.endStep(id, latest, {'status': 'correct latest result'}, 2);
    final run = history.runs.single;
    final steps = run['steps'] as List;
    expect(steps, hasLength(AiRunHistory.maxSteps));
    expect(run['older_steps_omitted'], 3);
    expect(run['vision_enabled'], isTrue);
    expect(steps.last['result']['status'], 'correct latest result');
    expect(
      steps.any(
        (step) =>
            step['result'] is Map &&
            step['result']['error'] == 'late old result',
      ),
      isFalse,
    );
  });

  test('manual app choice is traced with the actual result', () async {
    final service = AiModelService(
      history: history,
      deviceTools: _ChoiceTools(),
    );
    final result = await service.openSelectedApp('app.target');
    expect(result['status'], 'opened');
    final step = (history.runs.single['steps'] as List).single;
    expect(step['tool'], 'open_selected_app');
    expect(step['arguments']['packageName'], 'app.target');
    expect(step['result']['status'], 'opened');
  });

  test(
    'Stop during history initialization prevents generation and tools',
    () async {
      final gate = Completer<File>();
      final delayed = AiRunHistory(file: () => gate.future);
      final service = AiModelService(history: delayed);
      final pending = service.generate('do something', (_) {});
      final expectation = expectLater(
        pending,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('ผู้ใช้หยุด'),
          ),
        ),
      );
      await service.stopGeneration();
      gate.complete(file);
      await expectation;
      expect(delayed.runs.single['state'], 'cancelled');
      expect(delayed.runs.single['steps'], isEmpty);
    },
  );
}

class _ChoiceTools extends AiDeviceTools {
  @override
  Future<Map<String, dynamic>> openSelected(String packageName) async => {
    'status': 'opened',
  };
}
