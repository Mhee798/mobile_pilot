import 'dart:async';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:mobile_pilot/features/ai/data/model_download.dart';
import 'package:mobile_pilot/features/models/data/model_backend.dart';
import 'package:mobile_pilot/features/models/domain/model_entry.dart';

const testModel = LocalModelEntry(
  id: 'first',
  name: 'Test Gemma',
  path: '/library/first.litertlm',
  type: ModelType.gemma4,
  bytes: 2600000000,
  vision: true,
);
const secondModel = LocalModelEntry(
  id: 'second',
  name: 'Second model',
  path: '/library/second.litertlm',
  type: ModelType.qwen3,
  bytes: 600000000,
  vision: false,
);

class FakeModelBackend implements ModelBackend {
  List<LocalModelEntry> entries = [testModel];
  ModelSelection? saved;
  bool ready = false,
      failActivation = false,
      failCloud = false,
      failSave = false;
  bool cancelRequested = false;
  bool failLoad = false, restoredAfterFailure = false;
  String nano = 'available';
  LocalModelEntry? imported = secondModel;
  Completer<void>? activationGate, downloadGate;
  final calls = <String>[];
  @override
  bool get localReady => ready;
  int revision = 0;
  @override
  int get localRevision => revision;
  @override
  Future<ModelLibraryData> load() async {
    if (failLoad) throw StateError('storage temporarily unavailable');
    return ModelLibraryData(List.of(entries), saved);
  }

  @override
  Future<String> nanoAvailability() async => nano;
  @override
  Future<void> exclusive(Future<void> Function() operation) async =>
      operation();
  @override
  Future<LocalModelEntry?> importFile(ModelType type, bool vision) async {
    calls.add('import');
    return imported;
  }

  @override
  Future<LocalModelEntry> download(
    DownloadableModel model,
    void Function(ModelDownloadProgress) progress,
  ) async {
    calls.add('download');
    progress(const ModelDownloadProgress(100, 1000, Duration(seconds: 1)));
    await downloadGate?.future;
    if (cancelRequested) throw StateError('cancelled');
    return secondModel;
  }

  @override
  void cancelDownload() {
    cancelRequested = true;
  }

  @override
  Future<void> activateFile(LocalModelEntry entry) async {
    calls.add('activate:${entry.id}');
    await activationGate?.future;
    if (failActivation) {
      if (restoredAfterFailure) revision++;
      throw StateError('incompatible model');
    }
    ready = true;
  }

  @override
  Future<void> activateNano(void Function(int) progress) async {
    calls.add('nano');
    progress(50);
    ready = true;
  }

  @override
  Future<void> validateCloud(String id) async {
    calls.add('cloud:$id');
    if (failCloud) throw StateError('cloud access denied');
  }

  @override
  Future<void> unload() async {
    calls.add('unload');
    ready = false;
  }

  @override
  Future<void> saveSelection(ModelSelection? selection) async {
    if (failSave) throw StateError('storage unavailable');
    saved = selection;
  }

  @override
  Future<void> delete(LocalModelEntry entry) async {
    calls.add('delete:${entry.id}');
  }
}
