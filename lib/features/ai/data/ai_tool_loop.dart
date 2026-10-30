import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';

import 'ai_task_memory.dart';
import 'ai_visual_fallback.dart';
import 'ai_local_tool_call.dart';

/// Bounded, sequential tool execution. Callers discard the chat on exceptions,
/// since its native history may contain an unfinished tool turn.
Stream<ModelResponse> runAiToolLoop({
  required Stream<ModelResponse> Function() generate,
  required Future<void> Function(Message) addMessage,
  required Future<Map<String, dynamic>> Function(FunctionCallResponse) execute,
  required bool Function() isCancelled,
  required Uint8List? Function() takeImage,
  required void Function() onLimit,
  void Function(String)? onStalled,
  void Function()? onUnverifiedCompletion,
  void Function()? onContextLimit,
  void Function(FunctionCallResponse, Map<String, dynamic>)? onBlocked,
  int maxRounds = 8,
  int maxCalls = 12,
  bool requireGoalCheck = false,
  bool finishOnModelResponse = false,
  int maxResultBytes = 4000,
  bool proactiveContextRotation = true,
  AiTaskMemory? taskMemory,
  Future<void> Function(String checkpoint)? restartContext,
  void Function(String checkpoint)? onTaskState,
  bool enableVisualFallback = false,
  Future<void> Function(String? captureId, bool automatic)? onImageAdded,
  Set<String> localToolNames = const {},
}) async* {
  final continuous = restartContext != null;
  final memory =
      taskMemory ?? AiTaskMemory('Continue the current user request');
  var rotateContext = false;
  var recoverCapacity = false;
  var recoveredWithoutStep = false;
  var imageAwaitingInference = false;
  var emptyReplies = 0;
  var malformedLocalCalls = 0;
  final visualFallback = continuous && enableVisualFallback
      ? AiVisualFallback()
      : null;
  String? pendingVisualReason;
  var calls = 0;
  var limited = false;
  var resultBytes = 0;
  var stalled = false;
  final failures = <String, int>{};
  final deadline = DateTime.now().add(const Duration(minutes: 3));
  Duration remaining() {
    if (continuous) return const Duration(seconds: 90);
    final value = deadline.difference(DateTime.now());
    if (value <= Duration.zero) {
      throw TimeoutException('AI task exceeded three minutes');
    }
    return value;
  }

  var needsVerification = false;
  var assessed = false;
  var goalMatched = false;
  var finalEvidenceMatched = false;
  var remindedVerification = false;
  var reviewedCompletion = false;
  var verificationRecoveries = 0;
  String? observationReport;
  var reportingObservation = false;
  String? pendingFreshUiReason;
  // A match on the last tool round still needs one text-only reporting turn.
  for (
    var round = 0;
    continuous || round < maxRounds || (round == maxRounds && goalMatched);
    round++
  ) {
    if (isCancelled()) return;
    if (observationReport != null) {
      yield TextResponse(observationReport);
      return;
    }
    if (continuous &&
        !imageAwaitingInference &&
        (recoverCapacity ||
            (proactiveContextRotation &&
                (rotateContext || round >= maxRounds || calls >= maxCalls)))) {
      await restartContext(memory.checkpoint()).timeout(remaining());
      if (isCancelled()) return;
      memory.rotations++;
      resultBytes = 0;
      calls = 0;
      round = 0;
      rotateContext = false;
      recoverCapacity = false;
      // A new chat must inspect the current device, never act from a summary.
      assessed = false;
      if (memory.targetPackage != null) {
        needsVerification = true;
        if (pendingVisualReason == null) {
          // The new chat gets an actual observation, not only stale summaries.
          final args = <String, dynamic>{
            'automatic': true,
            'reason': 'context_handoff',
          };
          final observation = await execute(
            FunctionCallResponse(name: 'read_current_ui', args: args),
          ).timeout(remaining());
          if (isCancelled()) return;
          memory.record('read_current_ui', args, observation);
          pendingVisualReason = visualFallback?.observe(
            'read_current_ui',
            observation,
          );
          assessed = observation['status'] == 'ok';
          if (assessed) pendingFreshUiReason = null;
          final message =
              'CONTROLLER CURRENT UI AFTER CONTEXT HANDOFF. '
              'Original request: ${jsonEncode(memory.goal)}. Continue remaining steps, not just the last completed step.\n${jsonEncode(observation)}';
          await addMessage(Message.text(text: message, isUser: true));
          if (isCancelled()) return;
          resultBytes = utf8.encode(message).length;
          calls++;
          onTaskState?.call(memory.checkpoint());
        }
      }
    }
    if (continuous && pendingFreshUiReason != null && !imageAwaitingInference) {
      final reason = pendingFreshUiReason;
      pendingFreshUiReason = null;
      final args = <String, dynamic>{'automatic': true, 'reason': reason};
      final observation = await execute(
        FunctionCallResponse(name: 'read_current_ui', args: args),
      ).timeout(remaining());
      if (isCancelled()) return;
      memory.record('read_current_ui', args, observation);
      assessed = observation['status'] == 'ok';
      final message =
          'CONTROLLER: fresh UI after $reason. Use current editable=true elements for typing; focus may fail, so do not reuse failed references. ${jsonEncode(observation)}';
      await addMessage(Message.text(text: message, isUser: true));
      if (isCancelled()) return;
      calls++;
      resultBytes += utf8.encode(message).length;
      if (resultBytes > maxResultBytes) rotateContext = true;
      onTaskState?.call(memory.checkpoint());
    }
    if (pendingVisualReason != null &&
        !imageAwaitingInference &&
        visualFallback != null) {
      final reason = pendingVisualReason;
      pendingVisualReason = null;
      visualFallback.captureAttempted();
      if (isCancelled()) return;
      final args = <String, dynamic>{'automatic': true, 'reason': reason};
      final result = await execute(
        FunctionCallResponse(name: 'capture_screen', args: args),
      ).timeout(remaining());
      if (isCancelled()) return;
      memory.record('capture_screen', args, result);
      final image = takeImage();
      final hasImage =
          result['status'] == 'captured' && image != null && image.isNotEmpty;
      final explanation =
          'CONTROLLER VISUAL OBSERVATION: $reason. Continue the SAME task. '
          '${hasImage ? 'Inspect this fresh image. For ui_action use the refreshed ui_after_capture labels/refs, not older snapshots. For coordinates use its actual capture_id and 0..1 normalized values. Image and UI are separate observations; check changes before acting.' : 'No image was delivered. Use UI alternatives or explain this capture failure; do not guess coordinates.'}\n'
          '${jsonEncode(result)}';
      await addMessage(
        hasImage
            ? Message.withImage(
                text: explanation,
                imageBytes: image,
                isUser: true,
              )
            : Message.text(text: explanation, isUser: true),
      );
      if (isCancelled()) return;
      if (hasImage) {
        imageAwaitingInference = true;
        assessed = true;
        memory.stagnantSteps = 0; // One bounded attempt with a new strategy.
        final ui = result['ui_after_capture'];
        if (ui is Map<String, dynamic> && ui['status'] == 'ok') {
          memory.record('read_current_ui', {'source': 'after_capture'}, ui);
        }
        await onImageAdded?.call(result['capture_id'] as String?, true);
      }
      onTaskState?.call(memory.checkpoint());
      resultBytes += utf8.encode(explanation).length;
      if (resultBytes > maxResultBytes) rotateContext = true;
    }
    final pending = <FunctionCallResponse>[];
    final text = <ModelResponse>[];
    var repairedTextCall = false;
    final inferenceHasImage = imageAwaitingInference;
    imageAwaitingInference = false;
    try {
      await for (final response in generate().timeout(remaining())) {
        if (isCancelled()) return;
        remaining();
        switch (response) {
          case FunctionCallResponse():
            pending.add(response);
          case ParallelFunctionCallResponse():
            pending.addAll(response.calls);
          case TextResponse() || ThinkingResponse():
            text.add(response);
        }
      }
    } catch (error) {
      final description = error.toString().toLowerCase();
      final capacityError =
          description.contains('prefill input length') ||
          description.contains('context length exceeded') ||
          description.contains('context window exceeded');
      if (!continuous || !capacityError || recoveredWithoutStep) rethrow;
      // No pending function call has executed yet. Never replay a tool on error.
      recoveredWithoutStep = true;
      recoverCapacity = true;
      if (inferenceHasImage &&
          visualFallback != null &&
          visualFallback.canRecaptureAfterContextReset) {
        pendingVisualReason = 'Previous image context overflowed; recapture after context handoff';
      }
      continue;
    }
    if (continuous && pending.isEmpty && localToolNames.isNotEmpty) {
      final rawText = text
          .whereType<TextResponse>()
          .map((part) => part.token)
          .join();
      final parsed = parseLocalToolCall(rawText, localToolNames);
      if (parsed != null) {
        pending.add(
          FunctionCallResponse(
            name: parsed.name,
            args: parsed.args,
            id: 'local-text-$round-$calls',
          ),
        );
        repairedTextCall = true;
        text.clear();
      } else if (rawText.trim().startsWith('call:') &&
          rawText.trim().endsWith('<tool_call|>')) {
        if (malformedLocalCalls++ < 2) {
          await addMessage(
            Message.text(
              text: 'Controller: the emitted local tool marker was not executed. Use a declared tool name and a valid JSON object with quoted keys/strings, or a native function call. Do not claim the action happened.',
              isUser: true,
            ),
          );
          continue;
        }
        onStalled?.call(
          'Invalid local tool-call format after two correction prompts',
        );
        return;
      }
    }
    if (pending.isEmpty) {
      if (continuous &&
          !text.whereType<TextResponse>().any(
            (response) => response.token.trim().isNotEmpty,
          )) {
        if (emptyReplies++ < 2) {
          await addMessage(
            Message.text(
              text:
                  'Task controller: no answer or tool call was received. The original task is still active. '
                  'Use the latest observed state to choose the next remaining step or explain the concrete blocker. '
                  'Do not replay dispatched actions. Read fresh UI if necessary.',
              isUser: true,
            ),
          );
          continue;
        }
        onStalled?.call(
          'Model emitted no answer or tool call after two recovery prompts',
        );
        return;
      }
      if (continuous &&
          finishOnModelResponse &&
          text.whereType<TextResponse>().any(
            (response) => response.token.trim().isNotEmpty,
          )) {
        if (memory.hasDispatchedActions && !finalEvidenceMatched) {
          onUnverifiedCompletion?.call();
          yield const TextResponse(
            'รายงานจาก AI — ส่งคำสั่งแล้ว แต่ระบบยังไม่ได้ยืนยันผลทั้งหมด:\n',
          );
        }
        yield* Stream.fromIterable(text);
        return;
      }
      if (continuous && memory.hasDispatchedActions && !reviewedCompletion) {
        reviewedCompletion = true;
        await addMessage(
          Message.text(
            text:
                'CONTROLLER COMPLETION REVIEW. Original user request: ${jsonEncode(memory.goal)}. '
                'Check ALL requested actions against observed results before ending. Opening an app, entering text, '
                'or seeing search results are intermediate steps if further actions were requested. '
                'If the requested goal is only to search and current UI shows search results, stop navigating and verify result evidence. A query in an editable field is not evidence of search results. '
                'If anything remains, use tools to continue. Read the current UI if needed. '
                'For a read/list/explain request, use report_observation with the answer; the app attaches UI evidence; this does not require verify_goal. '
                'For action requests, continue all remaining actions, then verify concrete final evidence; if genuinely blocked, explain the blocker.',
            isUser: true,
          ),
        );
        continue;
      }
      if (needsVerification && !(continuous && goalMatched)) {
        if (!remindedVerification && (continuous || round + 1 < maxRounds)) {
          remindedVerification = true;
          await addMessage(
            Message.text(
              text: 'Task controller: the action result has not been verified. Before answering, call verify_goal with ref or exact unique label from the latest UI identifying the requested final evidence. If no current UI is available, read_current_ui first. Do not repeat the action.',
              isUser: true,
            ),
          );
          continue;
        }
        if (continuous && verificationRecoveries < 2) {
          verificationRecoveries++;
          final args = <String, dynamic>{
            'automatic': true,
            'reason': 'unverified_completion',
          };
          final observation = await execute(
            FunctionCallResponse(name: 'read_current_ui', args: args),
          ).timeout(remaining());
          if (isCancelled()) return;
          memory.record('read_current_ui', args, observation);
          assessed = observation['status'] == 'ok';
          pendingVisualReason = visualFallback?.observe(
            'read_current_ui',
            observation,
          );
          final recovery =
              'CONTROLLER VERIFICATION RECOVERY $verificationRecoveries/2. '
              'Original request: ${jsonEncode(memory.goal)}. The task is not confirmed complete. '
              'Inspect this fresh observation and continue remaining steps or verify concrete final evidence. '
              'Do not blindly replay actions. If blocked, explain the actual blocker.\n${jsonEncode(observation)}';
          await addMessage(Message.text(text: recovery, isUser: true));
          if (isCancelled()) return;
          calls++;
          resultBytes += utf8.encode(recovery).length;
          if (resultBytes > maxResultBytes) rotateContext = true;
          onTaskState?.call(memory.checkpoint());
          continue;
        }
        onStalled?.call('Action dispatched but screen result was not verified');
      } else {
        yield* Stream.fromIterable(text);
      }
      return;
    }
    emptyReplies = 0;
    malformedLocalCalls = 0;
    if (!continuous && round == maxRounds) {
      onLimit();
      return;
    }
    for (final call in pending) {
      final Map<String, dynamic> result;
      if (isCancelled() || stalled || limited) {
        result = {'status': 'cancelled'};
      } else if (!continuous && calls >= maxCalls) {
        limited = true;
        result = {
          'error': 'Tool-call budget exhausted. No action was performed.',
        };
      } else {
        calls++;
        final changesScreen = {
          'keyboard_action',
          'open_app',
          'open_link',
          'open_map',
          'prepare_alarm',
          'open_system_settings',
          'ui_action',
          'screen_action',
          'navigate',
          'scroll_until_ui',
        }.contains(call.name);
        if (continuous &&
            call.name == 'keyboard_action' &&
            needsVerification &&
            !assessed &&
            !reportingObservation) {
          final args = <String, dynamic>{
            'automatic': true,
            'reason': 'before_keyboard_action',
          };
          final observation = await execute(
            FunctionCallResponse(name: 'read_current_ui', args: args),
          ).timeout(remaining());
          if (isCancelled()) return;
          memory.record('read_current_ui', args, observation);
          assessed = observation['status'] == 'ok';
          final message =
              'CONTROLLER: fresh UI before keyboard action. ${jsonEncode(observation)}';
          await addMessage(Message.text(text: message, isUser: true));
          if (isCancelled()) return;
          calls++;
          resultBytes += utf8.encode(message).length;
          onTaskState?.call(memory.checkpoint());
        }
        if (call.name == 'report_observation') reportingObservation = true;
        if (continuous && finalEvidenceMatched && changesScreen) {
          result = {
            'code': 'FINAL_EVIDENCE_MATCHED',
            'error': 'Final evidence was checked. Do not perform another device action. Report what was observed and its limits.',
          };
          onBlocked?.call(call, result);
        } else if (reportingObservation && changesScreen) {
          result = {
            'code': 'REPORT_REPAIR_ONLY',
            'error': 'No action performed. Finish or correct report_observation using the observed UI. Reading is allowed; do not navigate, tap, type or scroll to repair a report.',
          };
          onBlocked?.call(call, result);
        } else if (imageAwaitingInference && call.name == 'screen_action') {
          result = {
            'error': 'Inspect the captured image in the next inference before requesting a screen action.',
            'code': 'IMAGE_NOT_OBSERVED',
          };
          onBlocked?.call(call, result);
        } else if (requireGoalCheck &&
            changesScreen &&
            !(continuous &&
                {'open_app', 'open_system_settings'}.contains(call.name)) &&
            ((!continuous && goalMatched) ||
                (needsVerification && !assessed))) {
          result = {
            'error': !continuous && goalMatched
                ? 'Goal already checked. Do not perform further actions; report the observed result.'
                : continuous
                ? 'Read the current UI (or capture_screen for coordinates) after the last action before the next action. No action performed. Final goal verification is only needed when all requested steps are complete.'
                : 'Before another action: read_current_ui, then verify_goal(label=one unique label from that read). No action performed.',
            'code': 'VERIFY_BEFORE_ACTION',
          };
          onBlocked?.call(call, result);
        } else {
          result = await execute(call).timeout(remaining());
          if (!continuous) recoveredWithoutStep = false;
        }
        if (requireGoalCheck &&
            needsVerification &&
            {'read_current_ui', 'read_ui_page'}.contains(call.name) &&
            result['status'] == 'ok') {
          result['next'] = continuous
              ? 'Fresh UI observed. Continue the next remaining step of the original request. Use verify_goal only to check evidence; a match does not complete unrelated remaining steps.'
              : 'Now call verify_goal(label=one unique label copied exactly from this read that identifies the destination). Do not tap again before checking.';
        }
        if (call.name == 'report_observation' &&
            result['status'] == 'observation_report' &&
            pending.length == 1 &&
            assessed) {
          observationReport = result['summary'] as String;
        }
        if (call.name == 'verify_goal' && result['status'] == 'matched') {
          if (continuous && call.args['complete'] == true) {
            finalEvidenceMatched = true;
          }
          result['next'] = continuous
              ? (finalEvidenceMatched
                    ? 'Final evidence matched. Stop device actions and report the observed evidence and its limits.'
                    : 'Evidence matched. Continue any remaining steps in the original request; report only when the whole request is complete.')
              : 'Report the observed result. Do not perform more actions.';
        }
        if (result['verification_required'] == true &&
            result['error'] == null) {
          needsVerification = true;
          assessed = false;
          goalMatched = false;
          remindedVerification = false;
          reviewedCompletion = false;
          if (continuous && finishOnModelResponse && changesScreen) {
            pendingFreshUiReason = 'after_${call.name}';
          }
        }
        if (continuous &&
            call.name == 'keyboard_action' &&
            result['code'] == 'IME_DISPATCHED') {
          pendingFreshUiReason = 'keyboard_action';
          pendingVisualReason = null;
        } else if (continuous &&
            call.name == 'ui_action' &&
            result['code'] == 'INPUT_REJECTED') {
          pendingFreshUiReason = 'input_rejected';
          pendingVisualReason = null;
        }
        if (call.name == 'verify_goal' &&
            {'matched', 'not_matched'}.contains(result['status'])) {
          assessed = true;
        }
        if (continuous &&
            (({'read_current_ui', 'read_ui_page'}.contains(call.name) &&
                    result['status'] == 'ok') ||
                (call.name == 'capture_screen' &&
                    result['status'] == 'captured'))) {
          assessed = true;
        }
        if ((!requireGoalCheck &&
                call.name == 'read_current_ui' &&
                result['status'] == 'ok') ||
            (call.name == 'verify_goal' && result['status'] == 'matched')) {
          needsVerification = false;
          if (call.name == 'verify_goal') goalMatched = true;
        }
        if (!continuous && result['error'] != null) {
          final key = '${call.name}:${result['code'] ?? result['error']}';
          failures[key] = (failures[key] ?? 0) + 1;
          if (failures[key]! >= 2) {
            stalled = true;
            onStalled?.call('${call.name}: ${result['error']}');
          }
        } else if (!continuous) {
          failures.removeWhere((key, _) => key.startsWith('${call.name}:'));
        }
        if (continuous) {
          memory.record(call.name, call.args, result);
          if (call.name == 'capture_screen') {
            final ui = result['ui_after_capture'];
            if (ui is Map<String, dynamic> && ui['status'] == 'ok') {
              memory.record('read_current_ui', {'source': 'after_capture'}, ui);
            }
          }
          if (result['error'] == null &&
              ((changesScreen &&
                      (result['verification_required'] == true ||
                          result['status'] == 'opened')) ||
                  ({'read_current_ui', 'read_ui_page'}.contains(call.name) &&
                      memory.stagnantSteps == 0))) {
            recoveredWithoutStep = false;
          }
          final visualReason = visualFallback?.observe(call.name, result);
          if (call.name == 'capture_screen' ||
              (changesScreen &&
                  result['error'] == null &&
                  (result['verification_required'] == true ||
                      result['status'] == 'opened')) ||
              (call.name == 'verify_goal' && result['status'] == 'matched')) {
            pendingVisualReason = null;
          } else {
            pendingVisualReason ??= visualReason;
          }
          onTaskState?.call(memory.checkpoint());
          if ((memory.sameAttempt >= 4 &&
                  !{'read_current_ui', 'read_ui_page'}.contains(call.name)) ||
              memory.stagnantSteps >= 12) {
            if (pendingVisualReason == null) {
              stalled = true;
              onStalled?.call(
                'No progress: repeated attempts on the same observed screen. ${call.name}: ${result['error'] ?? result['code'] ?? result['status']}',
              );
            }
          } else if (result['error'] != null) {
            result['recovery'] = 'The attempted action did not complete. Read fresh UI and choose a corrected argument or different supported approach. Do not repeat a dispatched action blindly.';
          }
        }
      }
      // Feed the result before the next inference. Image bytes stay outside JSON.
      final receivedImage = isCancelled() ? null : takeImage();
      final image = receivedImage != null && receivedImage.isNotEmpty
          ? receivedImage
          : null;
      if (image != null) imageAwaitingInference = true;
      final bytes = utf8.encode(jsonEncode(result)).length;
      resultBytes += bytes;
      if (continuous && resultBytes > maxResultBytes) {
        rotateContext = true;
      } else if (resultBytes > maxResultBytes && !limited) {
        limited = true;
        onContextLimit?.call();
      }
      final responsePayload =
          !continuous &&
              resultBytes > maxResultBytes &&
              result['status'] != 'cancelled'
          ? <String, dynamic>{
              'error': 'Context result budget reached. Tool may already have run; inspect actual state before continuing.',
              'code': 'CONTEXT_BUDGET',
            }
          : result;
      final message = repairedTextCall
          ? Message.text(
              text:
                  'CONTROLLER TOOL RESULT (normalized local tool marker): ${jsonEncode({'tool': call.name, 'arguments': call.args, 'result': responsePayload})}',
              isUser: true,
            )
          : Message.toolResponse(
              toolName: call.name,
              response: responsePayload,
              toolCallId: call.id,
            );
      await addMessage(
        image == null
            ? message
            : repairedTextCall
            ? Message.withImage(
                text: message.text,
                imageBytes: image,
                isUser: true,
              )
            : message.copyWith(imageBytes: image),
      );
      if (image != null && image.isNotEmpty && call.name == 'capture_screen') {
        await onImageAdded?.call(result['capture_id'] as String?, false);
      }
    }
    if (isCancelled()) return;
    if (stalled) return;
    if (limited) {
      onLimit();
      return;
    }
  }
  onLimit();
}
