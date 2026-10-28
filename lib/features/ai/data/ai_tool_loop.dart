import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';

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
  void Function()? onContextLimit,
  void Function(FunctionCallResponse, Map<String, dynamic>)? onBlocked,
  int maxRounds = 8,
  int maxCalls = 12,
  bool requireGoalCheck = false,
  int maxResultBytes = 4000,
}) async* {
  var calls = 0;
  var limited = false;
  var resultBytes = 0;
  var stalled = false;
  final failures = <String, int>{};
  final deadline = DateTime.now().add(const Duration(minutes: 3));
  Duration remaining() {
    final value = deadline.difference(DateTime.now());
    if (value <= Duration.zero) {
      throw TimeoutException('AI task exceeded three minutes');
    }
    return value;
  }

  var needsVerification = false;
  var assessed = false;
  var goalMatched = false;
  var remindedVerification = false;
  // A match on the last tool round still needs one text-only reporting turn.
  for (
    var round = 0;
    round < maxRounds || (round == maxRounds && goalMatched);
    round++
  ) {
    if (isCancelled()) return;
    final pending = <FunctionCallResponse>[];
    final text = <ModelResponse>[];
    await for (final response in generate().timeout(remaining())) {
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
    if (pending.isEmpty) {
      if (needsVerification) {
        if (!remindedVerification && round + 1 < maxRounds) {
          remindedVerification = true;
          await addMessage(
            Message.text(
              text: 'Task controller: the action result has not been verified. Before answering, call verify_goal with label copied exactly from the latest UI identifying the requested destination. If no current UI is available, read_current_ui first. Do not repeat the action.',
              isUser: true,
            ),
          );
          continue;
        }
        onStalled?.call('Action dispatched but screen result was not verified');
      } else {
        yield* Stream.fromIterable(text);
      }
      return;
    }
    if (round == maxRounds) {
      onLimit();
      return;
    }
    for (final call in pending) {
      final Map<String, dynamic> result;
      if (isCancelled() || stalled || limited) {
        result = {'status': 'cancelled'};
      } else if (calls >= maxCalls) {
        limited = true;
        result = {
          'error': 'Tool-call budget exhausted. No action was performed.',
        };
      } else {
        calls++;
        final changesScreen = {
          'open_app',
          'ui_action',
          'screen_action',
          'navigate',
          'scroll_until_ui',
        }.contains(call.name);
        if (requireGoalCheck &&
            changesScreen &&
            (goalMatched || (needsVerification && !assessed))) {
          result = {
            'error': goalMatched
                ? 'Goal already checked. Do not perform further actions; report the observed result.'
                : 'Before another action: read_current_ui, then verify_goal(label=one unique label from that read). No action performed.',
            'code': 'VERIFY_BEFORE_ACTION',
          };
          onBlocked?.call(call, result);
        } else {
          result = await execute(call).timeout(remaining());
        }
        if (requireGoalCheck &&
            needsVerification &&
            {'read_current_ui', 'read_ui_page'}.contains(call.name) &&
            result['status'] == 'ok') {
          result['next'] = 'Now call verify_goal(label=one unique label copied exactly from this read that identifies the destination). Do not tap again before checking.';
        }
        if (call.name == 'verify_goal' && result['status'] == 'matched') {
          result['next'] =
              'Report the observed result. Do not perform more actions.';
        }
        if (result['verification_required'] == true &&
            result['error'] == null) {
          needsVerification = true;
          assessed = false;
          goalMatched = false;
        }
        if (call.name == 'verify_goal' &&
            {'matched', 'not_matched'}.contains(result['status'])) {
          assessed = true;
        }
        if ((!requireGoalCheck &&
                call.name == 'read_current_ui' &&
                result['status'] == 'ok') ||
            (call.name == 'verify_goal' && result['status'] == 'matched')) {
          needsVerification = false;
          if (call.name == 'verify_goal') goalMatched = true;
        }
        if (result['error'] != null) {
          final key = '${call.name}:${result['code'] ?? result['error']}';
          failures[key] = (failures[key] ?? 0) + 1;
          if (failures[key]! >= 2) {
            stalled = true;
            onStalled?.call('${call.name}: ${result['error']}');
          }
        } else {
          failures.removeWhere((key, _) => key.startsWith('${call.name}:'));
        }
      }
      // Feed the result before the next inference. Image bytes stay outside JSON.
      final image = isCancelled() ? null : takeImage();
      final bytes = utf8.encode(jsonEncode(result)).length;
      resultBytes += bytes;
      if (resultBytes > maxResultBytes && !limited) {
        limited = true;
        onContextLimit?.call();
      }
      final message = Message.toolResponse(
        toolName: call.name,
        response:
            resultBytes > maxResultBytes && result['status'] != 'cancelled'
            ? {
                'error': 'Context result budget reached. Tool may already have run; inspect actual state before continuing.',
                'code': 'CONTEXT_BUDGET',
              }
            : result,
        toolCallId: call.id,
      );
      await addMessage(
        image == null ? message : message.copyWith(imageBytes: image),
      );
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
