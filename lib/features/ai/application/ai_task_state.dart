import 'dart:typed_data';

import '../data/model_download.dart';

class AiChatMessage {
  const AiChatMessage({
    required this.isUser,
    required this.text,
    this.image,
    this.apps = const [],
  });
  final bool isUser;
  final String text;
  final Uint8List? image;
  final List<Map<String, String>> apps;
}

class AiTaskState {
  const AiTaskState({
    this.busy = false,
    this.ready = false,
    this.visionReady = false,
    this.waitingForUi = false,
    this.openingReadTarget = false,
    this.generating = false,
    this.stoppingGeneration = false,
    this.accessibilityNeeded = false,
    this.saved = false,
    this.canCancel = false,
    this.status = 'ยังไม่ได้โหลดโมเดล',
    this.answer = '',
    this.messages = const [],
    this.toolsUsed = const [],
    this.toolResults = const [],
    this.pendingChoiceIndex,
    this.progress,
    this.interruptedRequest,
  });
  final bool busy,
      ready,
      saved,
      canCancel,
      visionReady,
      waitingForUi,
      openingReadTarget,
      generating,
      stoppingGeneration;
  final bool accessibilityNeeded;
  final String status, answer;
  final List<AiChatMessage> messages;
  final List<String> toolsUsed;
  final List<String> toolResults;
  final int? pendingChoiceIndex;
  final ModelDownloadProgress? progress;
  final String? interruptedRequest;

  AiTaskState copyWith({
    bool? busy,
    bool? ready,
    bool? visionReady,
    bool? waitingForUi,
    bool? openingReadTarget,
    bool? generating,
    bool? stoppingGeneration,
    bool? accessibilityNeeded,
    bool? saved,
    bool? canCancel,
    String? status,
    String? answer,
    List<AiChatMessage>? messages,
    List<String>? toolsUsed,
    List<String>? toolResults,
    int? pendingChoiceIndex,
    bool clearChoice = false,
    ModelDownloadProgress? progress,
    bool clearProgress = false,
    String? interruptedRequest,
    bool clearInterrupted = false,
  }) => AiTaskState(
    busy: busy ?? this.busy,
    ready: ready ?? this.ready,
    visionReady: visionReady ?? this.visionReady,
    waitingForUi: waitingForUi ?? this.waitingForUi,
    openingReadTarget: openingReadTarget ?? this.openingReadTarget,
    generating: generating ?? this.generating,
    stoppingGeneration: stoppingGeneration ?? this.stoppingGeneration,
    accessibilityNeeded: accessibilityNeeded ?? this.accessibilityNeeded,
    saved: saved ?? this.saved,
    canCancel: canCancel ?? this.canCancel,
    status: status ?? this.status,
    answer: answer ?? this.answer,
    messages: messages ?? this.messages,
    toolsUsed: toolsUsed ?? this.toolsUsed,
    toolResults: toolResults ?? this.toolResults,
    pendingChoiceIndex: clearChoice
        ? null
        : pendingChoiceIndex ?? this.pendingChoiceIndex,
    progress: clearProgress ? null : progress ?? this.progress,
    interruptedRequest: clearInterrupted
        ? null
        : interruptedRequest ?? this.interruptedRequest,
  );
}

///
