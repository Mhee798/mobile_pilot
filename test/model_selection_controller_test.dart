import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/features/models/application/model_selection_controller.dart';
import 'package:mobile_pilot/features/models/domain/model_entry.dart';

import 'helpers/fake_model_backend.dart';

void main() {
  late FakeModelBackend backend;
  late ModelSelectionController controller;
  setUp(() async {
    backend = FakeModelBackend();
    controller = ModelSelectionController(backend);
    await controller.initialize();
  });
  tearDown(() => controller.dispose());

  test('commits a new selection only after loading and prevents concurrent changes', () async {
    await controller.selectFile(testModel);
    backend.activationGate = Completer<void>();
    final changing = controller.selectFile(secondModel);
    expect(controller.busy, isTrue);
    expect(controller.selection!.id, testModel.id);
    await controller.selectCloud('cloud', 'Cloud');
    expect(backend.calls, isNot(contains('cloud:cloud')));
    backend.activationGate!.complete();
    await changing;
    expect(controller.selection!.id, secondModel.id);
    expect(backend.saved!.id, secondModel.id);
    expect(controller.ready, isTrue);
  });

  test(
    'failed file or cloud checks retain the previous usable selection',
    () async {
      await controller.selectFile(testModel);
      backend.failActivation = true;
      await controller.selectFile(secondModel);
      expect(controller.selection!.id, testModel.id);
      expect(controller.ready, isTrue);
      backend.failCloud = true;
      await controller.selectCloud('cloud', 'Cloud');
      expect(controller.selection!.id, testModel.id);
      expect(backend.calls, isNot(contains('unload')));
      expect(controller.errorKey, 'models.operation_error');
    },
  );

  test('cancelling a download preserves selection and does not activate a partial file', () async {
    await controller.selectFile(testModel);
    backend.downloadGate = Completer<void>();
    final downloading = controller.download(downloadableModels.first);
    expect(controller.canCancel, isTrue);
    expect(controller.progress!.received, 100);
    controller.cancelDownload();
    backend.downloadGate!.complete();
    await downloading;
    expect(controller.models, hasLength(1));
    expect(controller.selection!.id, testModel.id);
    expect(backend.calls, isNot(contains('activate:second')));
    expect(controller.phase, 'cancelled');
    expect(controller.error, isNull);
  });

  test('import cancellation is harmless and failed activation keeps a complete file in the library', () async {
    backend.imported = null;
    await controller.importFile(testModel.type, true);
    expect(controller.selection, isNull);
    expect(controller.models, hasLength(1));
    backend.imported = secondModel;
    backend.failActivation = true;
    await controller.importFile(secondModel.type, false);
    expect(controller.models, hasLength(2));
    expect(controller.selection, isNull);
    expect(controller.errorKey, 'models.operation_error');
  });

  test('active files cannot be deleted; unloading permits deletion', () async {
    await controller.selectFile(testModel);
    await controller.delete(testModel);
    expect(backend.calls, isNot(contains('delete:first')));
    await controller.unload();
    await controller.delete(testModel);
    expect(backend.calls, contains('delete:first'));
    expect(controller.models, isEmpty);
  });

  test(
    'restores saved configuration without claiming a runtime is ready',
    () async {
      backend.saved = const ModelSelection(
        ModelLocation.cloud,
        'cloud',
        'Cloud',
      );
      final restored = ModelSelectionController(backend);
      await restored.initialize();
      expect(restored.selection!.id, 'cloud');
      expect(restored.ready, isFalse);
      restored.dispose();
    },
  );

  test(
    'storage failure leaves the actual runtime selection visible with an error',
    () async {
      backend.failSave = true;
      await controller.selectFile(testModel);
      expect(controller.selection!.id, testModel.id);
      expect(controller.ready, isTrue);
      expect(controller.errorKey, 'models.save_error');
    },
  );
  test('an external runtime replacement stops advertising the old selection as ready', () async {
    await controller.selectFile(testModel);
    expect(controller.ready, isTrue);
    backend.revision++;
    controller.refreshNativeStatus();
    expect(controller.ready, isFalse);
    expect(controller.selection!.id, testModel.id);
  });
  test(
    'successful rollback remains ready at the restored runtime revision',
    () async {
      await controller.selectFile(testModel);
      backend.failActivation = true;
      backend.restoredAfterFailure = true;
      await controller.selectFile(secondModel);
      expect(backend.revision, 1);
      expect(controller.ready, isTrue);
      expect(controller.selection!.id, testModel.id);
    },
  );

  test('retrying library initialization clears an earlier error', () async {
    final storage = FakeModelBackend()..failLoad = true;
    final retrying = ModelSelectionController(storage);
    await retrying.initialize();
    expect(retrying.errorKey, 'models.library_error');
    storage.failLoad = false;
    await retrying.initialize();
    expect(retrying.loaded, isTrue);
    expect(retrying.errorKey, isNull);
    expect(retrying.error, isNull);
    retrying.dispose();
  });
}
