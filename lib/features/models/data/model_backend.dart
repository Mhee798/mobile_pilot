import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_builtin_ai/flutter_edge_ai_builtin_ai.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:path_provider/path_provider.dart';

import '../../ai/application/ai_task_controller.dart';
import '../../ai/data/gemini_connection.dart';
import '../../ai/data/model_download.dart';
import '../domain/model_entry.dart';

class ModelLibraryData {
  const ModelLibraryData(this.models, this.selection);
  final List<LocalModelEntry> models;
  final ModelSelection? selection;
}

abstract class ModelBackend {
  Future<ModelLibraryData> load();
  Future<String> nanoAvailability();
  Future<void> exclusive(Future<void> Function() operation);
  Future<LocalModelEntry?> importFile(ModelType type, bool vision);
  Future<LocalModelEntry> download(
    DownloadableModel model,
    void Function(ModelDownloadProgress) progress,
  );
  void cancelDownload();
  Future<void> activateFile(LocalModelEntry entry);
  Future<void> activateNano(void Function(int) progress);
  Future<void> validateCloud(String id);
  Future<void> unload();
  Future<void> saveSelection(ModelSelection? selection);
  Future<void> delete(LocalModelEntry entry);
  bool get localReady;
  int get localRevision;
}

class DeviceModelBackend implements ModelBackend {
  DeviceModelBackend(
    this.tasks, {
    Future<Directory> Function()? supportDirectory,
  }) : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;
  final Future<Directory> Function() _supportDirectory;
  final AiTaskController tasks;
  late Box<dynamic> _box;
  late Directory _directory;
  ModelDownload? _download;
  // Hive locks out other processes; these guards also cover multiple backends in this isolate.
  static final _activeTransfers = <String>{};
  static final _recoveries = <String, Future<void>>{};

  @override
  bool get localReady => tasks.service.isReady;
  @override
  int get localRevision => tasks.service.modelRevision;

  @override
  Future<ModelLibraryData> load() async {
    final support = await _supportDirectory();
    _directory = Directory('${support.path}/model_library');
    await _directory.create(recursive: true);
    _directory = Directory(await _directory.resolveSymbolicLinks());
    _box = await Hive.openBox<dynamic>(
      'model_library_v1',
      path: _directory.path,
    );
    await _recoveries.putIfAbsent(
      _directory.path,
      () => _recoverTransfers().whenComplete(() {
        _recoveries.remove(_directory.path);
      }),
    );
    final models = <LocalModelEntry>[
      for (final key in _box.keys.whereType<String>().where(
        (key) => key.startsWith('model:'),
      ))
        LocalModelEntry.fromJson(_box.get(key) as Map),
    ];
    // Bring the existing debug screen's saved model into the new library.
    // A missing native engine must not prevent cloud selection or opening the library.
    try {
      await tasks.service.initialize().timeout(const Duration(seconds: 5));
      final spec = FlutterEdgeAi.activeModelSpec;
      if (spec != null && spec.fileType == ModelFileType.litertlm) {
        final path = await FlutterEdgeAi.getModelPath(
          spec.files.first.filename,
        );
        if (!models.any((entry) => entry.path == path) &&
            await File(path).exists()) {
          final entry = LocalModelEntry(
            id: 'legacy:${spec.name}',
            name: spec.name,
            path: path,
            type: spec.modelType,
            bytes: await File(path).length(),
            vision: tasks.service.visionEnabled,
            managed: false,
          );
          await _box.put('model:${entry.id}', entry.toJson());
          models.add(entry);
        }
      }
    } catch (error) {
      debugPrint('Saved native model could not be inspected: $error');
    }
    final selection = _box.get('selection');
    return ModelLibraryData(
      models,
      selection is Map ? ModelSelection.fromJson(selection) : null,
    );
  }

  @override
  Future<String> nanoAvailability() async => Platform.isAndroid
      ? (await BuiltInAi.availability()).name
      : 'unavailableDeviceUnsupported';

  @override
  Future<void> exclusive(Future<void> Function() operation) =>
      tasks.changeModel(operation);

  Future<void> _recoverTransfers() async {
    final stagingName = RegExp(r'^(\d+)\.partial$');
    await for (final entity in _directory.list(followLinks: false)) {
      if (entity is! File || _activeTransfers.contains(entity.path)) continue;
      final id = stagingName.firstMatch(entity.uri.pathSegments.last)?.group(1);
      if (id == null) continue;
      final record = _box.get('model:$id');
      final finalPath = '${_directory.path}/$id.litertlm';
      if (record is Map &&
          record['path'] == finalPath &&
          record['bytes'] == await entity.length() &&
          record['bytes'] > 0) {
        if (!await File(finalPath).exists()) {
          await entity.rename(finalPath);
          continue;
        }
      }
      // An unregistered staging file was interrupted before transfer completion.
      await entity.delete();
    }
  }

  Future<LocalModelEntry> _finishTransfer(
    String id,
    String name,
    File partial,
    ModelType type,
    bool vision,
  ) async {
    final size = await partial.length();
    if (size == 0) throw const FormatException('Empty model file');
    final file = File('${_directory.path}/$id.litertlm');
    final entry = LocalModelEntry(
      id: id,
      name: name,
      path: file.path,
      type: type,
      bytes: size,
      vision: vision,
    );
    // Persist the completed transfer first: after a crash, recovery can finish the rename.
    await _box.put('model:$id', entry.toJson());
    await partial.rename(file.path);
    return entry;
  }

  Future<void> _discardTransfer(String id) async {
    for (final extension in ['partial', 'litertlm']) {
      final file = File('${_directory.path}/$id.$extension');
      if (await file.exists()) await file.delete();
    }
    await _box.delete('model:$id');
  }

  @override
  Future<LocalModelEntry?> importFile(ModelType type, bool vision) async {
    final selected = await FilePicker.pickFile();
    if (selected == null) return null;
    if (!selected.name.toLowerCase().endsWith('.litertlm')) {
      throw const FormatException('Only .litertlm files are supported');
    }
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final partial = File('${_directory.path}/$id.partial');
    _activeTransfers.add(partial.path);
    try {
      final sink = partial.openWrite();
      try {
        await sink.addStream(
          selected.readAsByteStream().map<List<int>>((bytes) => bytes),
        );
      } finally {
        await sink.close();
      }
      return await _finishTransfer(id, selected.name, partial, type, vision);
    } catch (_) {
      await _discardTransfer(id);
      rethrow;
    } finally {
      _activeTransfers.remove(partial.path);
    }
  }

  @override
  Future<LocalModelEntry> download(
    DownloadableModel model,
    void Function(ModelDownloadProgress) progress,
  ) async {
    final uri = parseModelDownloadUri(model.url);
    if (uri == null) {
      throw const FormatException(
        'Use a direct HTTPS link to a .litertlm file',
      );
    }
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final partial = File('${_directory.path}/$id.partial');
    _activeTransfers.add(partial.path);
    final download = ModelDownload();
    _download = download;
    try {
      await download.download(uri, partial, progress);
      return await _finishTransfer(
        id,
        model.name,
        partial,
        model.type,
        model.vision,
      );
    } catch (_) {
      await _discardTransfer(id);
      rethrow;
    } finally {
      _activeTransfers.remove(partial.path);
      _download = null;
    }
  }

  @override
  void cancelDownload() => _download?.cancel();

  @override
  Future<void> activateFile(LocalModelEntry entry) => tasks.service
      .activateFileModel(entry.path, entry.type, entry.name, entry.vision);

  @override
  Future<void> activateNano(void Function(int) progress) =>
      tasks.service.activateNanoModel(progress);

  @override
  Future<void> validateCloud(String id) => (() async {
    await initializeGeminiConnection();
    // Check access without sending conversation data or generating a reply.
    await FirebaseAI.googleAI().generativeModel(model: id).countTokens([
      Content.text('MobilePilot connection check'),
    ]);
  })().timeout(const Duration(seconds: 30));

  @override
  Future<void> unload() => tasks.service.close();

  @override
  Future<void> saveSelection(ModelSelection? selection) =>
      _box.put('selection', selection?.toJson());

  @override
  Future<void> delete(LocalModelEntry entry) async {
    if (!entry.managed) {
      throw StateError('This file is managed outside the model library');
    }
    final file = File(entry.path);
    final root = await _directory.resolveSymbolicLinks();
    if (await file.parent.resolveSymbolicLinks() != root ||
        !entry.path.endsWith('.litertlm')) {
      throw StateError('Model file is outside the app model library');
    }
    if (await file.exists() &&
        File(await file.resolveSymbolicLinks()).parent.path != root) {
      throw StateError('Model file is outside the app model library');
    }
    if (tasks.service.loadedFileName == file.uri.pathSegments.last) {
      throw StateError('Unload this model before deleting it');
    }
    await tasks.service.forgetModelFile(entry.path);
    await tasks.refreshSavedModels();
    if (await file.exists()) await file.delete();
    await _box.delete('model:${entry.id}');
  }
}
