import 'package:flutter/foundation.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';

import '../../ai/data/model_download.dart';
import '../data/model_backend.dart';
import '../domain/model_entry.dart';

class ModelSelectionController extends ChangeNotifier {
  ModelSelectionController(this.backend);
  final ModelBackend backend;
  List<LocalModelEntry> _models = [];
  List<LocalModelEntry> get models => List.unmodifiable(_models);
  ModelSelection? selection;
  bool loaded = false, busy = false, canCancel = false;
  bool _ready = false;
  int? _readyRevision;
  bool get ready =>
      _ready &&
      (selection?.location == ModelLocation.cloud ||
          backend.localReady && _readyRevision == backend.localRevision);

  void refreshNativeStatus() {
    if (!busy && _ready && !ready) {
      _ready = false;
      _changed();
    }
  }

  String nanoStatus = 'checking';
  String phase = 'idle';
  String? error, errorKey;
  ModelDownloadProgress? progress;
  int? nanoProgress;
  bool _disposed = false;
  bool _cancelRequested = false;
  Future<void>? _initialization;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() => _initialization ??= _load();
  Future<void> _load() async {
    error = null;
    errorKey = null;
    _changed();
    try {
      final library = await backend.load();
      if (_disposed) return;
      _models = library.models;
      selection = library.selection;
      loaded = true;
      await _restoreSelection();
    } catch (failure) {
      errorKey = 'models.library_error';
      error = failure.toString();
      _initialization = null;
    }
    _changed();
  }

  Future<void> _restoreSelection() async {
    final saved = selection;
    if (saved == null || _disposed) return;
    switch (saved.location) {
      case ModelLocation.file:
        final entry = _models
            .where((model) => model.id == saved.id)
            .firstOrNull;
        if (entry == null) {
          errorKey = 'models.saved_missing';
          _changed();
          return;
        }
        await selectFile(entry);
      case ModelLocation.nano:
        await selectNano();
      case ModelLocation.cloud:
        await selectCloud(saved.id, saved.label);
    }
  }

  Future<void> probeNano() async {
    if (busy || _disposed) return;
    nanoStatus = 'checking';
    _changed();
    try {
      nanoStatus = await backend.nanoAvailability();
    } catch (_) {
      nanoStatus = 'unavailableOther';
    }
    _changed();
  }

  Future<void> _perform(
    String operation,
    Future<void> Function() action,
  ) async {
    if (busy || !loaded || _disposed) return;
    final wasReady = ready;
    busy = true;
    error = null;
    errorKey = null;
    phase = operation;
    _cancelRequested = false;
    _changed();
    try {
      await backend.exclusive(action);
    } catch (failure) {
      if (!_cancelRequested) {
        error = failure.toString();
        errorKey = 'models.operation_error';
      }
      if (selection != null && selection!.location != ModelLocation.cloud) {
        _ready = wasReady && backend.localReady;
        _readyRevision = backend.localRevision;
      }
    } finally {
      busy = false;
      canCancel = false;
      progress = null;
      nanoProgress = null;
      phase = _cancelRequested ? 'cancelled' : 'idle';
      _changed();
    }
  }

  Future<void> _commit(ModelSelection? value) async {
    // Runtime state is authoritative even if persisting the preference fails.
    selection = value;
    _ready = value != null;
    _readyRevision = backend.localRevision;
    _changed();
    try {
      await backend.saveSelection(value);
    } catch (failure) {
      errorKey = 'models.save_error';
      error = failure.toString();
    }
  }

  Future<void> _activate(LocalModelEntry entry) async {
    phase = 'loading';
    canCancel = false;
    _changed();
    await backend.activateFile(entry);
    await _commit(ModelSelection(ModelLocation.file, entry.id, entry.name));
  }

  Future<void> selectFile(LocalModelEntry entry) {
    if (ready &&
        selection?.location == ModelLocation.file &&
        selection?.id == entry.id) {
      return Future.value();
    }
    return _perform('loading', () => _activate(entry));
  }

  Future<void> importFile(ModelType type, bool vision) =>
      _perform('importing', () async {
        final entry = await backend.importFile(type, vision);
        if (entry == null || _disposed) return;
        _models.add(entry);
        _changed();
        await _activate(entry);
      });

  Future<void> download(DownloadableModel model) =>
      _perform('downloading', () async {
        canCancel = true;
        var last = Duration.zero;
        _changed();
        final entry = await backend.download(model, (value) {
          if (value.received != 0 &&
              value.received != value.total &&
              value.elapsed - last < const Duration(milliseconds: 200)) {
            return;
          }
          last = value.elapsed;
          progress = value;
          _changed();
        });
        _models.add(entry);
        if (_disposed || _cancelRequested) return;
        await _activate(entry);
      });

  void cancelDownload() {
    if (!busy || !canCancel) return;
    _cancelRequested = true;
    canCancel = false;
    backend.cancelDownload();
    _changed();
  }

  Future<void> selectNano() => _perform('nano', () async {
    await backend.activateNano((value) {
      nanoProgress = value;
      _changed();
    });
    nanoStatus = 'available';
    await _commit(
      const ModelSelection(ModelLocation.nano, 'nano', 'Gemini Nano'),
    );
  });

  Future<void> selectCloud(String id, String label) =>
      _perform('connecting', () async {
        await backend.validateCloud(id);
        await backend.unload();
        await _commit(ModelSelection(ModelLocation.cloud, id, label));
      });

  Future<void> unload() => _perform('loading', () async {
    await backend.unload();
    await _commit(null);
  });

  Future<void> delete(LocalModelEntry entry) => _perform('deleting', () async {
    if (selection?.location == ModelLocation.file &&
        selection?.id == entry.id) {
      throw StateError('Unload or choose another model before deleting');
    }
    await backend.delete(entry);
    _models.removeWhere((value) => value.id == entry.id);
  });

  @override
  void dispose() {
    _disposed = true;
    backend.cancelDownload();
    super.dispose();
  }
}
