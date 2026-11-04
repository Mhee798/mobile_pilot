import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/features/ai/application/ai_task_controller.dart';
import 'package:mobile_pilot/features/ai/data/ai_model_service.dart';

class _Service extends AiModelService {
  bool ready = false;
  int revision = 0;
  @override
  bool get isReady => ready;
  @override
  int get modelRevision => revision;
  @override
  bool get supportsImages => false;
  @override
  Future<bool> hasSavedModel() async => false;
  @override
  Future<void> generate(
    String text,
    void Function(String) onToken, {
    Uint8List? image,
    void Function(String)? onToolCall,
    void Function(String, Map<String, dynamic>)? onToolResult,
  }) async => onToken('answer');
  @override
  Future<void> close() async {}
}

void main() {
  test(
    'model changes cannot overlap another model change or cloud task',
    () async {
      final service = _Service();
      final tasks = AiTaskController(service);
      final gate = Completer<void>();
      final operation = tasks.changeModel(() => gate.future);
      expect(tasks.state.busy, isTrue);
      await expectLater(tasks.changeModel(() async {}), throwsStateError);
      gate.complete();
      await operation;
      expect(tasks.state.busy, isFalse);
      expect(tasks.beginExternalTask(() async {}), isTrue);
      await expectLater(tasks.changeModel(() async {}), throwsStateError);
      tasks.endExternalTask('done');
      await tasks.close();
    },
  );

  test(
    'library-only operations retain chat; replacing a runtime starts fresh',
    () async {
      final service = _Service();
      final tasks = AiTaskController(service);
      await tasks.changeModel(() async {
        service.ready = true;
        service.revision++;
      });
      await tasks.send('hello');
      expect(tasks.state.messages, hasLength(2));
      final status = tasks.state.status;
      await tasks.changeModel(() async {});
      expect(tasks.state.messages, hasLength(2));
      expect(tasks.state.status, status);
      await tasks.changeModel(() async {
        service.revision++;
      });
      expect(tasks.state.messages, isEmpty);
      await tasks.close();
    },
  );
}
