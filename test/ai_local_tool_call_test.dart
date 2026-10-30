import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/features/ai/data/ai_local_tool_call.dart';
import 'package:mobile_pilot/features/ai/data/ai_tool_loop.dart';

void main() {
  const allowed = {'read_current_ui', 'keyboard_action'};
  test('accepts the exact observed local marker and strict JSON arguments', () {
    expect(
      parseLocalToolCall('call:read_current_ui{}<tool_call|>', allowed)?.name,
      'read_current_ui',
    );
    expect(
      parseLocalToolCall(
        'call:keyboard_action{"key":"search"}<tool_call|>',
        allowed,
      )?.args,
      {'key': 'search'},
    );
  });
  test('does not interpret prose, fences, unknown tools or malformed JSON as commands', () {
    for (final text in [
      'ตัวอย่าง call:read_current_ui{}<tool_call|>',
      '```call:read_current_ui{}<tool_call|>```',
      'call:unknown{}<tool_call|>',
      'call:keyboard_action{key:search}<tool_call|>',
      'call:read_current_ui{}',
      'call:read_current_ui{}<tool_call|>call:read_current_ui{}<tool_call|>',
    ]) {
      expect(parseLocalToolCall(text, allowed), isNull, reason: text);
    }
  });
  test('normalized marker executes once and receives a controller result, not orphan tool output', () async {
    var turns = 0;
    var calls = 0;
    final messages = <Message>[];
    final output = await runAiToolLoop(
      generate: () async* {
        if (++turns == 1) {
          yield const TextResponse('call:read_');
          yield const TextResponse('current_ui{}<tool_call|>');
        } else {
          expect(messages.single.type, isNot(MessageType.toolResponse));
          expect(messages.single.text, contains('CONTROLLER TOOL RESULT'));
          yield const TextResponse('อ่านหน้าจอแล้ว');
        }
      },
      addMessage: (message) async => messages.add(message),
      execute: (call) async {
        calls++;
        expect(call.name, 'read_current_ui');
        return {'status': 'ok'};
      },
      restartContext: (_) async {},
      localToolNames: allowed,
      isCancelled: () => false,
      takeImage: () => null,
      onLimit: () => fail('unexpected limit'),
    ).toList();
    expect(calls, 1);
    expect(output.whereType<TextResponse>().single.token, 'อ่านหน้าจอแล้ว');
  });
  test(
    'invalid wire calls are corrected then stopped without executing anything',
    () async {
      var calls = 0;
      String? stopped;
      await runAiToolLoop(
        generate: () =>
            Stream.value(const TextResponse('call:unknown{}<tool_call|>')),
        addMessage: (_) async {},
        execute: (_) async {
          calls++;
          return {};
        },
        restartContext: (_) async {},
        localToolNames: allowed,
        isCancelled: () => false,
        takeImage: () => null,
        onLimit: () {},
        onStalled: (reason) => stopped = reason,
      ).drain<void>();
      expect(calls, 0);
      expect(stopped, contains('Invalid local tool-call format'));
    },
  );
}
