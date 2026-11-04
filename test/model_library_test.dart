import 'dart:io';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:mobile_pilot/features/ai/application/ai_task_controller.dart';
import 'package:mobile_pilot/features/ai/data/ai_model_service.dart';
import 'package:mobile_pilot/features/models/data/model_backend.dart';
import 'package:mobile_pilot/features/models/domain/model_entry.dart';

class _Service extends AiModelService {
  final forgotten = <String>[];
  @override
  Future<void> forgetModelFile(String path) async => forgotten.add(path);
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasSavedModel() async => false;
  @override
  Future<void> close() async {}
}

void main() {
  test('library persists selection and only deletes files inside its own directory', () async {
    final root = await Directory.systemTemp.createTemp(
      'mobilepilot_model_library_',
    );
    final service = _Service();
    final tasks = AiTaskController(service);
    final backend = DeviceModelBackend(
      tasks,
      supportDirectory: () async => root,
    );
    await backend.load();
    final box = await Hive.openBox<dynamic>(
      'model_library_v1',
      path: '${root.path}/model_library',
    );
    final owned = File('${root.path}/model_library/safe.litertlm');
    final external = File('${root.path}/outside.litertlm');
    await owned.writeAsBytes([1, 2, 3]);
    await external.writeAsBytes([4, 5, 6]);
    final entry = LocalModelEntry(
      id: 'safe',
      name: 'Safe',
      path: owned.path,
      type: ModelType.gemma4,
      bytes: 3,
      vision: false,
    );
    await box.put('model:safe', entry.toJson());
    const selection = ModelSelection(
      ModelLocation.cloud,
      'gemini-3.8-flash',
      'Gemini 3.8 Flash',
    );
    await backend.saveSelection(selection);
    await box.close();
    final reopened = DeviceModelBackend(
      tasks,
      supportDirectory: () async => root,
    );
    final data = await reopened.load();
    expect(data.selection!.id, selection.id);
    expect(data.models.single.path, owned.path);
    final unsafe = LocalModelEntry(
      id: 'outside',
      name: 'Outside',
      path: external.path,
      type: ModelType.gemma4,
      bytes: 3,
      vision: false,
    );
    await expectLater(reopened.delete(unsafe), throwsStateError);
    expect(await external.exists(), isTrue);
    expect(service.forgotten, isEmpty);
    await reopened.delete(entry);
    expect(await owned.exists(), isFalse);
    expect(service.forgotten, [owned.path]);
    expect(tasks.state.saved, isFalse);
    final metadata = await Hive.openBox<dynamic>(
      'model_library_v1',
      path: '${root.path}/model_library',
    );
    expect(metadata.containsKey('model:safe'), isFalse);
    await metadata.close();
    await tasks.close();
    expect(root.parent.absolute.path, Directory.systemTemp.absolute.path);
    await root.delete(recursive: true);
  });
  test('recovers completed transfers and removes only abandoned numeric staging files', () async {
    final root = await Directory.systemTemp.createTemp(
      'mobilepilot_model_recovery_',
    );
    final directory = Directory('${root.path}/model_library');
    await directory.create();
    final canonical = await directory.resolveSymbolicLinks();
    final box = await Hive.openBox<dynamic>(
      'model_library_v1',
      path: canonical,
    );
    final complete = LocalModelEntry(
      id: '123',
      name: 'Recovered',
      path: '$canonical/123.litertlm',
      type: ModelType.gemma4,
      bytes: 3,
      vision: false,
    );
    await box.put('model:123', complete.toJson());
    await File('$canonical/123.partial').writeAsBytes([1, 2, 3]);
    await File('$canonical/456.partial').writeAsBytes([9]);
    await File('$canonical/user.partial').writeAsBytes([8]);
    await File('$canonical/789.litertlm').writeAsBytes([7]);
    final tasks = AiTaskController(_Service());
    final backend = DeviceModelBackend(
      tasks,
      supportDirectory: () async => root,
    );
    final library = await backend.load();
    expect(library.models.single.id, '123');
    expect(await File(complete.path).readAsBytes(), [1, 2, 3]);
    expect(await File('$canonical/123.partial').exists(), isFalse);
    expect(await File('$canonical/456.partial').exists(), isFalse);
    expect(await File('$canonical/user.partial').exists(), isTrue);
    expect(await File('$canonical/789.litertlm').exists(), isTrue);
    await box.close();
    await tasks.close();
    expect(root.parent.absolute.path, Directory.systemTemp.absolute.path);
    await root.delete(recursive: true);
  });
}
