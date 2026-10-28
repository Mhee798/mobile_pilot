import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';

import '../data/ai_model_service.dart';

import '../data/ai_task_journal.dart';
import '../../../core/platform/ai_task_overlay.dart';
import 'ai_task_state.dart';
export 'ai_task_state.dart';

/// App-owned AI session. Routes subscribe without owning the model lifetime.
class AiTaskController extends Cubit<AiTaskState> {
  AiTaskController(
    this.service, {
    AiTaskOverlay? overlay,
    AiTaskJournal? journal,
  }) : _overlay = overlay,
       // Public injection name stays independent of the private field.
       // ignore: prefer_initializing_formals
       _journal = journal,
       super(const AiTaskState()) {
    overlay?.listen(stopGeneration);
    _publishOverlay(state);
    _overlaySubscription = stream
        .map((state) => (status: state.status, running: state.generating))
        .distinct()
        .listen((value) {
          unawaited(
            _overlay?.publish(status: value.status, running: value.running),
          );
        });
    _checkSaved();
    _restoreInterrupted();
  }
  final AiModelService service;
  final AiTaskJournal? _journal;
  Future<void> _restoreInterrupted() async {
    try {
      final record = await _journal?.readInterrupted();
      if (record != null && state.messages.isEmpty && !state.busy) {
        _update(
          state.copyWith(interruptedRequest: record['request'] as String),
        );
      }
    } catch (_) {
      /* A damaged checkpoint must not prevent using the app. */
    }
  }

  Future<void> dismissInterrupted() async {
    final request = state.interruptedRequest;
    if (request == null || state.busy) return;
    await _journal?.save(request, 'dismissed');
    _update(state.copyWith(clearInterrupted: true));
  }

  final AiTaskOverlay? _overlay;
  StreamSubscription<({String status, bool running})>? _overlaySubscription;
  Future<void>? _operation;
  String? _pendingAppRequest;

  void _publishOverlay(AiTaskState state) {
    unawaited(
      _overlay?.publish(status: state.status, running: state.generating),
    );
  }

  void _update(AiTaskState value) {
    if (!isClosed) emit(value);
  }

  Future<void> _checkSaved() async {
    try {
      final saved = await service.hasSavedModel();
      _update(state.copyWith(saved: saved));
    } catch (_) {
      /* Retried when a model is selected. */
    }
  }

  Future<void> download(String url, ModelType type) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        !uri.path.toLowerCase().endsWith('.litertlm')) {
      _update(
        state.copyWith(status: 'กรุณาใส่ลิงก์ HTTPS ของไฟล์ .litertlm โดยตรง'),
      );
      return Future.value();
    }
    return _run(() async {
      _update(
        state.copyWith(
          busy: true,
          canCancel: true,
          status: 'กำลังดาวน์โหลดโมเดล',
          clearProgress: true,
        ),
      );
      var last = Duration.zero;
      try {
        await service.download(
          uri,
          type,
          (progress) {
            if (progress.received != 0 &&
                progress.elapsed - last < const Duration(milliseconds: 250) &&
                progress.received != progress.total) {
              return;
            }
            last = progress.elapsed;
            _update(state.copyWith(progress: progress));
          },
          () => _update(
            state.copyWith(
              canCancel: false,
              status: 'ดาวน์โหลดเสร็จ กำลังเตรียมโมเดล',
            ),
          ),
        );
        _update(
          state.copyWith(
            saved: true,
            status: 'โมเดลพร้อมใช้งาน',
            answer: '',
            messages: const [],
            clearChoice: true,
          ),
        );
      } catch (error) {
        _update(
          state.copyWith(
            status: service.isCancelled
                ? 'ยกเลิกการดาวน์โหลดแล้ว'
                : 'ดาวน์โหลดหรือโหลดโมเดลไม่สำเร็จ: $error',
          ),
        );
      } finally {
        _update(
          state.copyWith(
            busy: false,
            canCancel: false,
            ready: service.isReady,
            visionReady: service.supportsImages,
            clearProgress: true,
          ),
        );
      }
    });
  }

  void cancelDownload() {
    service.cancelDownload();
    _update(
      state.copyWith(status: 'กำลังยกเลิกการดาวน์โหลด', canCancel: false),
    );
  }

  Future<void> loadSaved() => _run(() async {
    _update(state.copyWith(busy: true, status: 'กำลังโหลดโมเดลที่บันทึกไว้'));
    try {
      await service.loadSaved();
      _update(
        state.copyWith(
          status: 'โมเดลพร้อมใช้งาน',
          answer: '',
          messages: const [],
          clearChoice: true,
        ),
      );
    } catch (error) {
      _update(state.copyWith(status: 'โหลดโมเดลไม่สำเร็จ: $error'));
    } finally {
      _update(
        state.copyWith(
          busy: false,
          ready: service.isReady,
          visionReady: service.supportsImages,
        ),
      );
    }
  });

  Future<void> importModel(ModelType type) => _run(() async {
    _update(state.copyWith(busy: true, status: 'เลือกไฟล์โมเดล'));
    try {
      final name = await service.importModel(
        type,
        () => _update(
          state.copyWith(status: 'กำลังคัดลอกไฟล์โมเดล อาจใช้เวลาหลายนาที'),
        ),
        () => _update(state.copyWith(status: 'กำลังโหลดโมเดล')),
      );
      _update(
        state.copyWith(
          saved: name != null || state.saved,
          status: name == null
              ? (service.isReady ? 'โมเดลพร้อมใช้งาน' : 'ยังไม่ได้โหลดโมเดล')
              : 'โมเดลพร้อมใช้งาน: $name',
          answer: name == null ? state.answer : '',
          messages: name == null ? state.messages : const [],
          clearChoice: name != null,
        ),
      );
    } catch (error) {
      _update(state.copyWith(status: 'โหลดโมเดลไม่สำเร็จ: $error'));
    } finally {
      _update(
        state.copyWith(
          busy: false,
          ready: service.isReady,
          visionReady: service.supportsImages,
        ),
      );
    }
  });

  Future<void> send(String input, {Uint8List? image}) {
    final text = input.trim();
    if (state.busy || !state.ready || (text.isEmpty && image == null)) {
      return Future.value();
    }
    if (image != null && !state.visionReady) {
      _update(
        state.copyWith(
          status: 'โมเดลนี้ไม่ได้เปิดโหมดภาพ กรุณาเปิด Vision และโหลดโมเดลใหม่',
        ),
      );
      return Future.value();
    }
    _pendingAppRequest = null;
    return _run(() => _generateReply(text, image: image));
  }

  Future<void> _generateReply(
    String text, {
    Uint8List? image,
    bool showUserMessage = true,
  }) async {
    service.deviceTools.clearPendingChoice();
    _update(
      state.copyWith(
        busy: true,
        answer: '',
        generating: true,
        status: 'กำลังสร้างคำตอบ',
        clearInterrupted: true,
        toolsUsed: const [],
        toolResults: const [],
        clearChoice: true,
        messages: [
          ...state.messages,
          if (showUserMessage)
            AiChatMessage(isUser: true, text: text, image: image),
          const AiChatMessage(isUser: false, text: ''),
        ],
      ),
    );
    try {
      if (_journal case final journal?) {
        await journal.save(text, 'running');
        if (state.stoppingGeneration) return;
      }
      await service.generate(
        text,
        (token) {
          final answer = state.answer + token;
          _update(
            state.copyWith(
              answer: answer,
              messages: [
                ...state.messages.take(state.messages.length - 1),
                AiChatMessage(
                  isUser: false,
                  text: answer,
                  apps: state.messages.last.apps,
                ),
              ],
            ),
          );
        },
        image: image,
        onToolCall: (name) => _update(
          state.copyWith(
            status:
                {
                  'read_current_ui',
                  'wait_for_ui',
                  'ui_action',
                  'screen_action',
                  'capture_screen',
                  'scroll_until_ui',
                }.contains(name)
                ? 'กำลังรอหน้าจอแอปเป้าหมาย กดเปิดแอปเป้าหมายได้'
                : 'กำลังใช้เครื่องมือ: $name',
            waitingForUi:
                {
                  'read_current_ui',
                  'wait_for_ui',
                  'ui_action',
                  'screen_action',
                  'capture_screen',
                  'scroll_until_ui',
                }.contains(name) &&
                service.deviceTools.targetPackage != null,
            toolsUsed: [...state.toolsUsed, name],
          ),
        ),
        onToolResult: (name, result) => _handleToolResult(text, name, result),
      );
      _update(
        state.copyWith(
          status: state.answer.isEmpty
              ? 'โมเดลไม่ได้ส่งข้อความตอบกลับ'
              : 'ตอบเสร็จแล้ว',
        ),
      );
    } catch (error) {
      final message = state.stoppingGeneration
          ? 'หยุดการสร้างคำตอบแล้ว บทสนทนาของโมเดลถูกเริ่มใหม่'
          : 'สร้างคำตอบไม่สำเร็จ บทสนทนาถูกเริ่มใหม่: $error';
      final answer = state.answer.trim().isEmpty
          ? message
          : '${state.answer}\n\n$message';
      _update(
        state.copyWith(
          status: message,
          answer: answer,
          messages: [
            ...state.messages.take(state.messages.length - 1),
            AiChatMessage(
              isUser: false,
              text: answer,
              apps: state.messages.last.apps,
            ),
          ],
        ),
      );
    } finally {
      try {
        await _journal?.save(
          text,
          state.pendingChoiceIndex != null ? 'awaiting_choice' : 'ended',
        );
      } catch (_) {
        /* Existing running checkpoint will be shown as uncertain after restart. */
      }
      _update(
        state.copyWith(
          busy: false,
          waitingForUi: false,
          generating: false,
          stoppingGeneration: false,
        ),
      );
    }
  }

  void _handleToolResult(
    String text,
    String name,
    Map<String, dynamic> result,
  ) {
    if (name == 'verify_goal' && result['conditions'] is List) {
      final checks = (result['conditions'] as List).whereType<Map>().map(
        (c) =>
            '${c['matched'] == true ? 'ตรง' : 'ไม่ตรง'}: ${c['selector']}=${c['value']} / ${c['property']}=${c['expected']} (พบ ${c['match_count']})',
      );
      _update(state.copyWith(toolResults: [...state.toolResults, ...checks]));
    }
    _update(state.copyWith(waitingForUi: false));
    if (name == 'open_app' && result['status'] == 'opened') {
      _pendingAppRequest = null;
      _update(state.copyWith(clearChoice: true));
    }
    if (name != 'wait_for_ui' &&
        name != 'read_current_ui' &&
        name != 'read_ui_page') {
      final error = result['error'];
      final description = error != null
          ? 'ไม่สำเร็จ${result['code'] != null ? ' (${result['code']})' : ''}: $error'
          : name == 'find_apps' && result['apps'] is List
          ? 'พบ ${(result['apps'] as List).length} แอป'
          : '${result['status'] ?? result['code'] ?? 'ได้รับผลแล้ว'}${result['message'] != null ? ': ${result['message']}' : ''}';
      _update(
        state.copyWith(
          toolResults: [...state.toolResults, '$name: $description'],
        ),
      );
    }
    if (name == 'wait_for_ui') {
      _update(
        state.copyWith(
          waitingForUi: false,
          toolResults: [
            ...state.toolResults,
            'ผลการรอหน้าจอ: ${result['code'] ?? result['error'] ?? 'ไม่ทราบผล'}',
          ],
        ),
      );
    }
    if (name == 'read_current_ui' || name == 'read_ui_page') {
      final text = result['error'] != null
          ? 'อ่านหน้าจอไม่สำเร็จ: ${result['error']}'
          : 'อ่าน UI tree: ${result['total']} รายการ${result['next_offset'] != null ? ' (มีหน้าถัดไป)' : ''}';
      _update(
        state.copyWith(
          waitingForUi: false,
          toolResults: [...state.toolResults, text],
        ),
      );
    }
    if (name != 'find_apps' &&
        !(name == 'open_app' && result['status'] == 'ambiguous')) {
      return;
    }
    final raw = result['apps'];
    if (raw is! List) return;
    final apps = raw
        .whereType<Map>()
        .where((app) => app['label'] is String && app['packageName'] is String)
        .map(
          (app) => <String, String>{
            'label': app['label'] as String,
            'packageName': app['packageName'] as String,
          },
        )
        .toList(growable: false);
    _pendingAppRequest = apps.isNotEmpty ? text : null;
    _update(
      state.copyWith(
        pendingChoiceIndex: apps.isNotEmpty ? state.messages.length - 1 : null,
        clearChoice: apps.isEmpty,
        messages: [
          ...state.messages.take(state.messages.length - 1),
          AiChatMessage(isUser: false, text: state.answer, apps: apps),
        ],
      ),
    );
  }

  Future<void> stopGeneration() async {
    if (!state.generating || state.stoppingGeneration) return;
    _update(
      state.copyWith(
        stoppingGeneration: true,
        status: 'กำลังหยุดการสร้างคำตอบ',
      ),
    );
    try {
      await service.stopGeneration();
    } catch (error) {
      _update(
        state.copyWith(
          stoppingGeneration: false,
          status: 'หยุดการสร้างคำตอบไม่สำเร็จ: $error',
        ),
      );
    }
  }

  Future<void> resetChat() => _run(() async {
    _pendingAppRequest = null;
    _update(state.copyWith(busy: true, status: 'กำลังเริ่มแชทใหม่'));
    try {
      await service.resetChat();
      _update(
        state.copyWith(
          messages: const [],
          toolsUsed: const [],
          toolResults: const [],
          clearChoice: true,
          answer: '',
          status: 'เริ่มแชทใหม่แล้ว',
        ),
      );
    } catch (error) {
      _update(state.copyWith(status: 'เริ่มแชทใหม่ไม่สำเร็จ: $error'));
    } finally {
      _update(state.copyWith(busy: false));
    }
  });

  Future<void> openReadTarget() async {
    if (!state.waitingForUi || state.openingReadTarget) return;
    _update(state.copyWith(openingReadTarget: true));
    try {
      await service.deviceTools.openTargetForReading();
    } catch (error) {
      if (state.waitingForUi) {
        _update(state.copyWith(status: 'เปิดแอปเป้าหมายไม่สำเร็จ: $error'));
      }
    } finally {
      _update(state.copyWith(openingReadTarget: false));
    }
  }

  Future<void> chooseApp(int messageIndex, String packageName) {
    if (state.busy ||
        state.pendingChoiceIndex != messageIndex ||
        messageIndex < 0 ||
        messageIndex >= state.messages.length) {
      return Future.value();
    }
    final matches = state.messages[messageIndex].apps
        .where((app) => app['packageName'] == packageName)
        .toList();
    if (matches.length != 1) return Future.value();
    final app = matches.single;
    final request = _pendingAppRequest;
    _pendingAppRequest = null;
    return _run(() async {
      _update(
        state.copyWith(
          busy: true,
          clearChoice: true,
          status: 'กำลังเปิด ${app['label']}',
          generating: true,
          messages: [
            ...state.messages,
            AiChatMessage(
              isUser: true,
              text: 'เลือก ${app['label']} (${app['packageName']})',
            ),
          ],
        ),
      );
      try {
        final result = await service.openSelectedApp(packageName);
        final resultText = switch (result['status']) {
          'opened' => 'เปิด ${app['label']} แล้ว และยืนยันว่าอยู่ด้านหน้า',
          'unconfirmed' =>
            'ส่งคำสั่งเปิด ${app['label']} แล้ว แต่ยังยืนยันว่าอยู่ด้านหน้าไม่ได้',
          _ =>
            'เปิด ${app['label']} ไม่สำเร็จ: ${result['message'] ?? 'ไม่ทราบข้อผิดพลาด'}',
        };
        service.recordChoiceResult(resultText);
        _update(
          state.copyWith(
            status: resultText,
            messages: [
              ...state.messages,
              AiChatMessage(isUser: false, text: resultText),
            ],
          ),
        );
        if (result['status'] == 'opened' &&
            request != null &&
            !state.stoppingGeneration) {
          await _generateReply(
            'ผู้ใช้เลือก ${app['label']} (${app['packageName']}) และเครื่องมือยืนยันว่าเปิดอยู่ด้านหน้าแล้ว '
            'ทำส่วนที่เหลือของคำขอเดิมต่อโดยใช้แอปนี้ ไม่ต้องค้นหาหรือเปิดแอปซ้ำ '
            'หากคำขอเดิมสำเร็จแล้วให้สรุปผล คำขอเดิม:\n$request',
            showUserMessage: false,
          );
        }
      } catch (error) {
        final resultText = 'เปิด ${app['label']} ไม่สำเร็จ: $error';
        service.recordChoiceResult(resultText);
        _update(
          state.copyWith(
            status: resultText,
            messages: [
              ...state.messages,
              AiChatMessage(isUser: false, text: resultText),
            ],
          ),
        );
      } finally {
        _update(
          state.copyWith(
            busy: false,
            generating: false,
            stoppingGeneration: false,
          ),
        );
      }
    });
  }

  void cancelChoice(int messageIndex) {
    if (state.busy || state.pendingChoiceIndex != messageIndex) return;
    _pendingAppRequest = null;
    const message = 'ยกเลิกการเลือกแอปแล้ว';
    service.deviceTools.clearPendingChoice();
    service.recordChoiceResult(message);
    _update(
      state.copyWith(
        clearChoice: true,
        status: message,
        messages: [
          ...state.messages,
          const AiChatMessage(isUser: true, text: message),
        ],
      ),
    );
  }

  Future<void> _run(Future<void> Function() task) {
    if (_operation != null) return _operation!;
    final future = task();
    _operation = future;
    return future.whenComplete(() => _operation = null);
  }

  @override
  Future<void> close() async {
    await _overlaySubscription?.cancel();
    _overlay?.dispose();
    service.cancelDownload();
    await stopGeneration();
    await _operation;
    await service.close();
    await _overlay?.publish(status: 'ตัวควบคุม AI ปิดแล้ว', running: false);
    return super.close();
  }
}
