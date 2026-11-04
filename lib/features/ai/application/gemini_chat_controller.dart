import '../../../core/ai/model_catalog.dart';

import 'dart:async';
import 'dart:collection';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';

import '../data/gemini_connection.dart';
import '../data/ai_run_history.dart';
import '../data/gemini_device_chat.dart';
import '../data/conversation_store.dart';
import 'ai_task_controller.dart';
import 'ai_task_phase.dart';

typedef GeminiReply = Future<String?> Function(
  String model,
  List<Content> history,
);

class GeminiMessage {
  const GeminiMessage(this.text, {required this.user, this.error = false});
  final String text;
  final bool user;
  final bool error;
}

/// Owns cloud conversation and task state independently of any particular UI.
class GeminiChatController extends ChangeNotifier {
  GeminiChatController({
    this.reply,
    this.history,
    this.taskController,
    GeminiDeviceChat? deviceChat,
    Future<void> Function()? initializeFirebase,
    this.store,
  }) : _deviceChat = deviceChat ?? GeminiDeviceChat(),
       _initializeOverride = initializeFirebase;

  final GeminiReply? reply;
  final AiRunHistory? history;
  final AiTaskController? taskController;
  final GeminiDeviceChat _deviceChat;
  final Future<void> Function()? _initializeOverride;
  ConversationStore? store;
  String? conversationId;
  String? storageError;
  String? _createdAt;
  final _messages = <GeminiMessage>[];
  late final List<GeminiMessage> _messageView = UnmodifiableListView(_messages);
  final _savedMessages = <GeminiMessage>[];
  final _runIds = <String>[];
  final _history = <Content>[];
  List<GeminiMessage> get messages => _messageView;
  bool busy = false;
  bool toolsEnabled = false;
  bool allowImages = false;
  bool stopRequested = false;
  bool accessibilityNeeded = false;
  String progress = '';
  AiTaskPhase phase = AiTaskPhase.idle;
  String model = defaultCloudModel;
  List<Map<String, String>> apps = [];
  Completer<String?>? _choice;
  bool _disposed = false;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _setPhase(AiTaskPhase value) {
    phase = value;
    taskController?.setExternalPhase(value);
    _changed();
  }

  void attachStore(ConversationStore value) {
    if (_disposed) return;
    store = value;
    storageError = null;
    if (_savedMessages.isNotEmpty) unawaited(_saveConversation());
    _changed();
  }

  void reportStoreUnavailable() {
    storageError = 'เปิดที่เก็บแชทไม่สำเร็จ แชทรอบนี้จะไม่ถูกบันทึก';
    _changed();
  }

  void updateAccessibility(bool? enabled) {
    if (enabled == true && accessibilityNeeded) {
      accessibilityNeeded = false;
      _changed();
    }
  }

  void reset() {
    if (busy) return;
    _history.clear();
    _messages.clear();
    _savedMessages.clear();
    _runIds.clear();
    conversationId = null;
    _createdAt = null;
    _changed();
  }

  List<Map<String, dynamic>> get savedConversations => store?.list() ?? [];

  void openConversation(String id) {
    if (busy || store == null) return;
    final data = store!.read(id);
    if (data == null || data['messages'] is! List) return;
    _deviceChat.selectTextFile(null, null);
    final loaded = <GeminiMessage>[];
    final restored = <Content>[];
    for (final item in (data['messages'] as List).whereType<Map>()) {
      if (item['text'] is! String || item['user'] is! bool) continue;
      final text = item['text'] as String;
      final user = item['user'] as bool;
      loaded.add(GeminiMessage(text, user: user));
      restored.add(user ? Content.text(text) : Content.model([TextPart(text)]));
    }
    _messages
      ..clear()
      ..addAll(loaded);
    _savedMessages
      ..clear()
      ..addAll(loaded);
    _runIds
      ..clear()
      ..addAll((data['runIds'] as List? ?? []).whereType<String>());
    _history
      ..clear()
      ..addAll(restored);
    model = data['model'] as String? ?? model;
    conversationId = id;
    _createdAt = data['createdAt'] as String?;
    storageError = null;
    _changed();
  }

  Future<void> _saveConversation() async {
    if (store == null) return;
    final successful = _savedMessages;
    if (successful.isEmpty) return;
    final now = DateTime.now().toUtc();
    conversationId ??= '${now.microsecondsSinceEpoch}';
    _createdAt ??= now.toIso8601String();
    try {
      await store!.save({
        'version': 1,
        'id': conversationId,
        'createdAt': _createdAt,
        'updatedAt': now.toIso8601String(),
        'model': model,
        'title': successful.first.text,
        'runIds': List<String>.of(_runIds),
        'messages': successful
            .map((message) => {'user': message.user, 'text': message.text})
            .toList(),
      });
      storageError = null;
    } catch (_) {
      storageError = 'บันทึกแชทไม่สำเร็จ ข้อมูลอาจหายเมื่อปิดแอป';
    }
    _changed();
  }

  void setModel(String value) {
    if (busy || value == model) return;
    model = value;
    reset();
  }

  void setToolsEnabled(bool value) {
    if (busy) return;
    toolsEnabled = value;
    if (!value) allowImages = false;
    reset();
  }

  void setAllowImages(bool value) {
    if (busy) return;
    allowImages = value;
    reset();
  }

  void selectTextFile(String? name, String? content) {
    if (busy) return;
    _deviceChat.selectTextFile(name, content);
    reset();
  }

  void resolveChoice(String? packageName) {
    final choice = _choice;
    _choice = null;
    if (choice != null && !choice.isCompleted) choice.complete(packageName);
    apps = [];
    _changed();
  }

  Future<String?> _chooseApp(List<Map<String, String>> choices) {
    if (_disposed || stopRequested || choices.isEmpty) {
      return Future.value(null);
    }
    final choice = Completer<String?>();
    _choice = choice;
    apps = choices;
    progress = 'เลือกแอปเพื่อทำงานต่อ';
    _setPhase(AiTaskPhase.waitingForUser);
    taskController?.updateExternalTask('รอเลือกแอป');
    _changed();
    return choice.future;
  }

  Future<void> _initializeFirebase() async {
    if (_initializeOverride != null) return _initializeOverride();
    await initializeGeminiConnection();
  }

  Future<String?> _cloudReply(String model, List<Content> conversation) async {
    await _initializeFirebase();
    final response = await FirebaseAI.googleAI()
        .generativeModel(model: model)
        .generateContent(conversation);
    return response.text;
  }

  /// Returns false when another task owns the shared device controls.
  bool send(String input) {
    final text = input.trim();
    if (_disposed || busy || text.isEmpty) return false;
    if (taskController != null && !taskController!.beginExternalTask(stop)) {
      return false;
    }
    busy = true;
    stopRequested = false;
    accessibilityNeeded = false;
    progress = 'Gemini กำลังตอบ...';
    _setPhase(AiTaskPhase.thinking);
    _messages.add(GeminiMessage(text, user: true));
    _changed();
    taskController?.updateExternalTask('Gemini กำลังตอบ');
    unawaited(_run(text));
    return true;
  }

  Future<void> _run(String text) async {
    final userContent = Content.text(text);
    final timer = Stopwatch()..start();
    String? runId;
    var runState = 'responded';
    var runReason = '';
    var runAnswer = '';
    try {
      runId = await history?.start(
        text,
        'Gemini Cloud · $model',
        tools: toolsEnabled,
        image: false,
      );
      if (stopRequested) throw StateError('ยกเลิกแล้ว');
      String? result;
      List<Content>? toolHistory;
      if (toolsEnabled && reply == null) {
        await _initializeFirebase();
        if (stopRequested) throw StateError('ยกเลิกแล้ว');
        final output = await _deviceChat.run(
          model: model,
          history: [..._history, userContent],
          allowImages: allowImages,
          progress: (value) {
            progress = value;
            taskController?.updateExternalTask(value);
            _changed();
          },
          onInference: () => _setPhase(AiTaskPhase.thinking),
          onToolStart: (_) => _setPhase(AiTaskPhase.usingTool),
          onOutcome: (state, reason) {
            runState = state;
            runReason = reason;
          },
          chooseApp: _chooseApp,
          onStepStart: (name, args) =>
              runId == null ? null : history?.beginStep(runId, name, args),
          onStepEnd: (step, result, elapsed) async {
            if (result['code'] == 'ACCESSIBILITY_DISABLED') {
              accessibilityNeeded = true;
              _changed();
            }
            if (runId != null) {
              await history?.endStep(runId, step, result, elapsed);
            }
          },
        );
        result = output.$1;
        toolHistory = output.$2;
      } else {
        result = await (reply ?? _cloudReply)(model, [
          ..._history,
          userContent,
        ]).timeout(const Duration(seconds: 60));
      }
      if (stopRequested) throw StateError('ยกเลิกแล้ว');
      final answer = result?.trim();
      runAnswer = answer ?? '';
      if (_disposed) return;
      if (answer == null || answer.isEmpty) {
        runState = 'failed';
        runReason = 'empty_response';
        _messages.add(
          const GeminiMessage(
            'โมเดลไม่ได้ส่งข้อความตอบ ลองส่งใหม่อีกครั้ง',
            user: false,
            error: true,
          ),
        );
      } else {
        if (toolHistory != null && toolHistory.length > _history.length) {
          _history
            ..clear()
            ..addAll(toolHistory);
        } else {
          _history.addAll([
            userContent,
            Content.model([TextPart(answer)]),
          ]);
        }
        _messages.add(GeminiMessage(answer, user: false));
        _savedMessages.addAll([
          GeminiMessage(text, user: true),
          GeminiMessage(answer, user: false),
        ]);
        if (runId != null) _runIds.add(runId);
        await _saveConversation();
      }
      _changed();
    } catch (error) {
      runState = stopRequested ? 'cancelled' : 'failed';
      runReason = '$error';
      if (!_disposed) {
        _messages.add(
          GeminiMessage(
            'ส่งข้อความไม่สำเร็จ: $error',
            user: false,
            error: true,
          ),
        );
        _changed();
      }
    } finally {
      try {
        if (runId != null) {
          await history?.finish(
            runId,
            runState,
            runReason,
            runAnswer,
            timer.elapsedMilliseconds,
          );
        }
      } catch (_) {
        // Diagnostics must not prevent releasing the shared task controls.
      }
      _setPhase(
        stopRequested
            ? AiTaskPhase.stopped
            : runState == 'failed'
            ? AiTaskPhase.failed
            : runState == 'stopped'
            ? AiTaskPhase.stopped
            : AiTaskPhase.responded,
      );
      taskController?.endExternalTask(
        stopRequested
            ? 'หยุดงาน Gemini แล้ว'
            : runState == 'failed'
            ? 'งาน Gemini ไม่สำเร็จ'
            : 'Gemini ตอบแล้ว',
      );
      busy = false;
      _changed();
    }
  }

  Future<void> stop() async {
    if (!busy || stopRequested) return;
    stopRequested = true;
    _setPhase(AiTaskPhase.stopping);
    resolveChoice(null);
    if (toolsEnabled) _deviceChat.cancel();
    progress = 'กำลังหยุด...';
    taskController?.updateExternalTask('กำลังหยุด Gemini');
    _changed();
  }

  @override
  void dispose() {
    if (busy) unawaited(stop());
    _disposed = true;
    super.dispose();
  }
}
