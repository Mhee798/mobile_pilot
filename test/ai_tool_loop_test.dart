import 'dart:typed_data';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/features/ai/data/ai_tool_loop.dart';

void main() {
  test(
    'a match on the last round gets one reporting turn without more tools',
    () async {
      var round = 0;
      var limited = false;
      final output = await runAiToolLoop(
        generate: () => ++round == 1
            ? Stream.value(
                const FunctionCallResponse(name: 'verify_goal', args: {}),
              )
            : Stream.value(const TextResponse('verified result')),
        addMessage: (_) async {},
        execute: (_) async => {'status': 'matched'},
        isCancelled: () => false,
        takeImage: () => null,
        onLimit: () => limited = true,
        requireGoalCheck: true,
        maxRounds: 1,
      ).toList();
      expect(output.whereType<TextResponse>().single.token, 'verified result');
      expect(limited, isFalse);
    },
  );
  test(
    'a second mutation is blocked until evidence has been assessed',
    () async {
      var round = 0;
      final executed = <String>[];
      final blocked = <String>[];
      final names = [
        'ui_action',
        'ui_action',
        'read_current_ui',
        'verify_goal',
      ];
      await runAiToolLoop(
        generate: () => ++round <= names.length
            ? Stream.value(
                FunctionCallResponse(name: names[round - 1], args: const {}),
              )
            : Stream.value(const TextResponse('done')),
        addMessage: (_) async {},
        execute: (call) async {
          executed.add(call.name);
          if (call.name == 'ui_action') {
            return {'code': 'ACTION_DISPATCHED', 'verification_required': true};
          }
          if (call.name == 'verify_goal') return {'status': 'matched'};
          return {'status': 'ok'};
        },
        isCancelled: () => false,
        takeImage: () => null,
        onLimit: () {},
        requireGoalCheck: true,
        onBlocked: (call, _) => blocked.add(call.name),
      ).drain<void>();
      expect(executed, ['ui_action', 'read_current_ui', 'verify_goal']);
      expect(blocked, ['ui_action']);
    },
  );
  test(
    'context budget balances calls without executing remaining actions',
    () async {
      var executed = 0;
      var limited = false;
      final messages = <Message>[];
      await runAiToolLoop(
        generate: () => Stream.value(
          const ParallelFunctionCallResponse(
            calls: [
              FunctionCallResponse(name: 'a', args: {}),
              FunctionCallResponse(name: 'b', args: {}),
            ],
          ),
        ),
        addMessage: (message) async => messages.add(message),
        execute: (_) async {
          executed++;
          return {'data': 'x' * 100};
        },
        isCancelled: () => false,
        takeImage: () => null,
        onLimit: () => limited = true,
        maxResultBytes: 40,
      ).drain<void>();
      expect(executed, 1);
      expect(limited, isTrue);
      expect(messages.first.text, contains('CONTEXT_BUDGET'));
      expect(messages.last.text, contains('cancelled'));
    },
  );
  test(
    'dispatch without a subsequent screen read cannot finish as verified',
    () async {
      var round = 0;
      String? stalled;
      await runAiToolLoop(
        generate: () => Stream.value(
          ++round == 1
              ? const FunctionCallResponse(name: 'ui_action', args: {})
              : const TextResponse('Done'),
        ),
        addMessage: (_) async {},
        execute: (_) async => {
          'code': 'ACTION_DISPATCHED',
          'verification_required': true,
        },
        isCancelled: () => false,
        takeImage: () => null,
        onLimit: () {},
        onStalled: (reason) => stalled = reason,
      ).drain<void>();
      expect(stalled, contains('not verified'));
    },
  );
  test(
    'stops repeated action failures even when reads succeed between them',
    () async {
      var round = 0;
      var failures = 0;
      String? reason;
      await runAiToolLoop(
        generate: () => Stream.value(
          FunctionCallResponse(
            name: ++round % 2 == 1 ? 'ui_action' : 'read_current_ui',
            args: const {},
          ),
        ),
        addMessage: (_) async {},
        execute: (call) async {
          if (call.name == 'ui_action') {
            failures++;
            return {'error': 'Invalid snapshot', 'code': 'INVALID_ARGUMENT'};
          }
          return {'status': 'ok'};
        },
        isCancelled: () => false,
        takeImage: () => null,
        onLimit: () => fail('should stop before round limit'),
        onStalled: (message) => reason = message,
      ).drain<void>();
      expect(failures, 2);
      expect(round, 3);
      expect(reason, contains('Invalid snapshot'));
    },
  );
  test(
    'feeds screenshot bytes with the tool result before the next inference',
    () async {
      final fed = <Message>[];
      var turns = 0;
      var image = Uint8List.fromList([1, 2, 3]);
      final output = await runAiToolLoop(
        generate: () async* {
          turns++;
          if (turns == 1) {
            yield const FunctionCallResponse(
              name: 'capture_screen',
              args: {},
              id: 'call1',
            );
          } else {
            expect(fed.single.type, MessageType.toolResponse);
            expect(fed.single.toolCallId, 'call1');
            expect(fed.single.imageBytes, [1, 2, 3]);
            expect(fed.single.text, isNot(contains('jpeg')));
            yield const TextResponse('เห็นภาพแล้ว');
          }
        },
        addMessage: (message) async => fed.add(message),
        execute: (_) async => {'status': 'captured', 'capture_id': 'c1'},
        isCancelled: () => false,
        takeImage: () {
          final result = image;
          image = Uint8List(0);
          return result;
        },
        onLimit: () => fail('unexpected limit'),
      ).toList();
      expect(output.single, const TextResponse('เห็นภาพแล้ว'));
    },
  );
  test(
    'stop skips remaining parallel actions and answers committed calls',
    () async {
      var cancelled = false;
      var executions = 0;
      final fed = <Message>[];
      await runAiToolLoop(
        generate: () => Stream.value(
          const ParallelFunctionCallResponse(
            calls: [
              FunctionCallResponse(name: 'ui_action', args: {}, id: '1'),
              FunctionCallResponse(name: 'screen_action', args: {}, id: '2'),
            ],
          ),
        ),
        addMessage: (message) async => fed.add(message),
        execute: (_) async {
          executions++;
          cancelled = true;
          return {'code': 'ACTION_CANCELLED'};
        },
        isCancelled: () => cancelled,
        takeImage: () => null,
        onLimit: () => fail('unexpected limit'),
      ).drain<void>();
      expect(executions, 1);
      expect(fed.map((m) => m.toolCallId), ['1', '2']);
      expect(fed.last.text, contains('cancelled'));
    },
  );
  test('bounds calls even when a model returns a parallel batch', () async {
    var executions = 0;
    var limited = false;
    final fed = <Message>[];
    await runAiToolLoop(
      generate: () => Stream.value(
        const ParallelFunctionCallResponse(
          calls: [
            FunctionCallResponse(name: 'a', args: {}),
            FunctionCallResponse(name: 'b', args: {}),
          ],
        ),
      ),
      addMessage: (message) async => fed.add(message),
      execute: (_) async {
        executions++;
        return {'code': 'dispatched'};
      },
      isCancelled: () => false,
      takeImage: () => null,
      onLimit: () => limited = true,
      maxCalls: 1,
    ).drain<void>();
    expect(executions, 1);
    expect(fed.length, 2);
    expect(fed.last.text, contains('No action was performed'));
    expect(limited, isTrue);
  });
  test(
    'bounds repeated tool turns without automatically retrying a mutation',
    () async {
      var turns = 0;
      var limited = false;
      await runAiToolLoop(
        generate: () {
          turns++;
          return Stream.value(
            const FunctionCallResponse(name: 'read_current_ui', args: {}),
          );
        },
        addMessage: (_) async {},
        execute: (_) async => {'status': 'ok'},
        isCancelled: () => false,
        takeImage: () => null,
        onLimit: () => limited = true,
        maxRounds: 2,
      ).drain<void>();
      expect(turns, 2);
      expect(limited, isTrue);
    },
  );
}
