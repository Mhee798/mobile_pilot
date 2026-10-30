import 'dart:convert';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/features/ai/data/ai_task_memory.dart';
import 'package:mobile_pilot/features/ai/data/ai_tool_loop.dart';

void main() {
  test('long-context mode still recovers from a capacity error', () async {
    var turn = 0;
    var rotations = 0;
    final output = await runAiToolLoop(
      generate: () => turn++ == 0
          ? Stream.error(StateError('context length exceeded'))
          : Stream.value(const TextResponse('continued')),
      addMessage: (_) async {},
      execute: (_) async => {'status': 'ok'},
      restartContext: (_) async {
        rotations++;
      },
      proactiveContextRotation: false,
      finishOnModelResponse: true,
      isCancelled: () => false,
      takeImage: () => null,
      onLimit: () {},
    ).toList();
    expect(rotations, 1);
    expect(output.whereType<TextResponse>().single.token, 'continued');
  });
  for (final proactive in [true, false]) {
    test('context rotation policy proactive=$proactive', () async {
      var turn = 0;
      var rotations = 0;
      await runAiToolLoop(
        generate: () => turn++ == 0
            ? Stream.value(
                const FunctionCallResponse(name: 'read_current_ui', args: {}),
              )
            : Stream.value(const TextResponse('done')),
        addMessage: (_) async {},
        execute: (_) async => {'status': 'ok'},
        restartContext: (_) async {
          rotations++;
        },
        proactiveContextRotation: proactive,
        maxRounds: 1,
        maxCalls: 1,
        maxResultBytes: 1,
        finishOnModelResponse: true,
        isCancelled: () => false,
        takeImage: () => null,
        onLimit: () {},
      ).toList();
      expect(rotations, proactive ? 1 : 0);
    });
  }
  for (final example in [
    'Shopee search results',
    'music playback unverified',
  ]) {
    test(
      'model response ends $example after fresh observation without further actions',
      () async {
        var turn = 0;
        var unverified = false;
        final calls = <String>[];
        final output = await runAiToolLoop(
          generate: () => turn++ == 0
              ? Stream.value(
                  const FunctionCallResponse(name: 'ui_action', args: {}),
                )
              : Stream.value(const TextResponse('ดำเนินการแล้ว')),
          execute: (call) async {
            calls.add(call.name);
            return call.name == 'read_current_ui'
                ? {'status': 'ok'}
                : {'verification_required': true};
          },
          addMessage: (_) async {},
          taskMemory: AiTaskMemory(example),
          restartContext: (_) async {},
          finishOnModelResponse: true,
          requireGoalCheck: true,
          onUnverifiedCompletion: () => unverified = true,
          isCancelled: () => false,
          takeImage: () => null,
          onLimit: () => fail('unexpected limit'),
        ).toList();
        expect(calls, ['ui_action', 'read_current_ui']);
        expect(unverified, isTrue);
        expect(
          output.whereType<TextResponse>().first.token,
          contains('ยังไม่ได้ยืนยัน'),
        );
        expect(turn, 2);
      },
    );
  }
  test(
    'final evidence blocks later actions while intermediate matches do not',
    () async {
      var turn = 0;
      final executed = <String>[];
      final blocked = <String>[];
      await runAiToolLoop(
        generate: () {
          final calls = [
            const FunctionCallResponse(
              name: 'verify_goal',
              args: {'complete': false},
            ),
            const FunctionCallResponse(name: 'ui_action', args: {}),
            const FunctionCallResponse(name: 'read_current_ui', args: {}),
            const FunctionCallResponse(
              name: 'verify_goal',
              args: {'complete': true},
            ),
            const FunctionCallResponse(name: 'ui_action', args: {}),
          ];
          return turn < calls.length
              ? Stream.value(calls[turn++])
              : Stream.value(const TextResponse('observed'));
        },
        addMessage: (_) async {},
        execute: (call) async {
          executed.add(call.name);
          if (call.name == 'verify_goal') return {'status': 'matched'};
          if (call.name == 'read_current_ui') return {'status': 'ok'};
          return {'verification_required': true};
        },
        restartContext: (_) async {},
        isCancelled: () => false,
        takeImage: () => null,
        onLimit: () {},
        onBlocked: (_, result) => blocked.add(result['code'] as String),
      ).toList();
      expect(executed.where((name) => name == 'ui_action'), hasLength(1));
      expect(blocked, contains('FINAL_EVIDENCE_MATCHED'));
    },
  );
  for (final reason in ['keyboard_action', 'input_rejected']) {
    test('fresh UI is supplied after $reason before next inference', () async {
      var turn = 0;
      var reads = 0;
      final messages = <String>[];
      final output = await runAiToolLoop(
        generate: () {
          if (turn++ == 0) {
            return Stream.value(
              FunctionCallResponse(
                name: reason == 'keyboard_action'
                    ? 'keyboard_action'
                    : 'ui_action',
                args: const {},
              ),
            );
          }
          expect(reads, 1);
          return Stream.value(const TextResponse('observed'));
        },
        execute: (call) async {
          if (call.name == 'read_current_ui') {
            reads++;
            return {
              'status': 'ok',
              'elements': [
                {'ref': 'A', 'editable': true},
              ],
            };
          }
          return reason == 'keyboard_action'
              ? {'code': 'IME_DISPATCHED'}
              : {'code': 'INPUT_REJECTED', 'error': 'focus rejected'};
        },
        addMessage: (message) async {
          messages.add(message.text);
        },
        restartContext: (_) async {},
        isCancelled: () => false,
        takeImage: () => null,
        onLimit: () {},
      ).take(1).toList();
      expect(reads, 1);
      expect(messages.any((m) => m.contains('fresh UI after $reason')), isTrue);
      expect(output, isNotEmpty);
    });
  }
  test(
    'reads fresh UI before executing the requested keyboard action',
    () async {
      var turn = 0;
      final calls = <String>[];
      await runAiToolLoop(
        generate: () => turn < 3
            ? Stream.value(
                FunctionCallResponse(
                  name: ['ui_action', 'keyboard_action', 'verify_goal'][turn++],
                  args: const {},
                ),
              )
            : Stream.value(const TextResponse('done')),
        addMessage: (_) async {},
        execute: (call) async {
          calls.add(call.name);
          if (call.name == 'ui_action') return {'verification_required': true};
          if (call.name == 'read_current_ui') return {'status': 'ok'};
          if (call.name == 'keyboard_action') {
            return {'verification_required': true};
          }
          return {'status': 'matched'};
        },
        restartContext: (_) async {},
        requireGoalCheck: true,
        isCancelled: () => false,
        takeImage: () => null,
        onLimit: () {},
        onStalled: (_) {},
      ).toList();
      expect(calls.take(3), [
        'ui_action',
        'read_current_ui',
        'keyboard_action',
      ]);
    },
  );
  test('failed report repairs the answer without navigating away', () async {
    var turn = 0;
    var reports = 0;
    var blocked = 0;
    final calls = <String>[];
    final output = await runAiToolLoop(
      generate: () => Stream.value(
        FunctionCallResponse(
          name: [
            'read_current_ui',
            'report_observation',
            'navigate',
            'report_observation',
          ][turn++],
          args: const {},
        ),
      ),
      addMessage: (_) async {},
      execute: (call) async {
        calls.add(call.name);
        if (call.name == 'read_current_ui') return {'status': 'ok'};
        return reports++ == 0
            ? {'code': 'INVALID_ARGUMENT', 'error': 'Correct summary'}
            : {'status': 'observation_report', 'summary': 'อ่านข้อมูลแล้ว'};
      },
      restartContext: (_) async {},
      isCancelled: () => false,
      takeImage: () => null,
      onLimit: () => fail('unexpected limit'),
      onBlocked: (_, result) {
        expect(result['code'], 'REPORT_REPAIR_ONLY');
        blocked++;
      },
    ).toList();
    expect(calls, isNot(contains('navigate')));
    expect(blocked, 1);
    expect(output.whereType<TextResponse>().single.token, 'อ่านข้อมูลแล้ว');
  });
  test(
    'fresh UI report answers a reading task without goal verification',
    () async {
      var turn = 0;
      final output = await runAiToolLoop(
        generate: () => Stream.value(
          FunctionCallResponse(
            name: turn++ == 0 ? 'read_current_ui' : 'report_observation',
            args: const {},
          ),
        ),
        addMessage: (_) async {},
        execute: (call) async => call.name == 'read_current_ui'
            ? {'status': 'ok', 'elements': []}
            : {
                'status': 'observation_report',
                'summary': 'พบรายการ Wi-Fi ที่อ่านได้',
              },
        restartContext: (_) async {},
        requireGoalCheck: true,
        isCancelled: () => false,
        takeImage: () => null,
        onLimit: () => fail('unexpected limit'),
        onStalled: (_) => fail('reading must not require goal verification'),
      ).toList();
      expect(output.whereType<TextResponse>().single.token, contains('Wi-Fi'));
      expect(turn, 2);
    },
  );
  for (final canRecover in [true, false]) {
    test(
      'unverified completion rereads UI and recovery succeeds=$canRecover',
      () async {
        var turns = 0;
        var recoveries = 0;
        var reads = 0;
        var verified = false;
        String? stalled;
        final output = await runAiToolLoop(
          generate: () {
            turns++;
            if (turns == 1) {
              return Stream.value(
                const FunctionCallResponse(
                  name: 'ui_action',
                  args: {'ref': 1, 'action': 'tap'},
                ),
              );
            }
            if (recoveries > 0 && canRecover && !verified) {
              return Stream.value(
                const FunctionCallResponse(
                  name: 'verify_goal',
                  args: {'ref': 2},
                ),
              );
            }
            return Stream.value(const TextResponse('done'));
          },
          addMessage: (message) async {
            if (message.text.contains('CONTROLLER VERIFICATION RECOVERY')) {
              recoveries++;
            }
          },
          execute: (call) async {
            if (call.name == 'ui_action') {
              return {'verification_required': true};
            }
            if (call.name == 'read_current_ui') {
              reads++;
              return {'status': 'ok'};
            }
            // Stop emitting the verification call after its matched result.
            if (call.name == 'verify_goal') {
              verified = true;
              return {'status': 'matched'};
            }
            throw StateError('unexpected tool');
          },
          taskMemory: AiTaskMemory('Play the song'),
          restartContext: (_) async {},
          requireGoalCheck: true,
          isCancelled: () => false,
          takeImage: () => null,
          onLimit: () => fail('unexpected limit'),
          onStalled: (reason) => stalled = reason,
        ).toList();
        expect(reads, canRecover ? 1 : 2);
        expect(stalled, canRecover ? isNull : contains('not verified'));
        expect(output.whereType<TextResponse>().length, canRecover ? 1 : 0);
      },
    );
  }
  test('premature found-result answer is reviewed against the full request before stopping', () async {
    var stage = 0;
    var actions = 0;
    final output = await runAiToolLoop(
      generate: () {
        if (stage == 0) {
          stage = 1;
          return Stream.value(
            const FunctionCallResponse(
              name: 'ui_action',
              args: {'label': 'Search'},
            ),
          );
        }
        if (stage == 1) {
          return Stream.value(const TextResponse('found results'));
        }
        if (stage == 2) {
          stage = 3;
          return Stream.value(
            const FunctionCallResponse(name: 'read_current_ui', args: {}),
          );
        }
        if (stage == 3) {
          stage = 4;
          return Stream.value(
            const FunctionCallResponse(
              name: 'ui_action',
              args: {'label': 'Play'},
            ),
          );
        }
        if (stage == 4) {
          stage = 5;
          return Stream.value(
            const FunctionCallResponse(name: 'read_current_ui', args: {}),
          );
        }
        if (stage == 5) {
          stage = 6;
          return Stream.value(
            const FunctionCallResponse(name: 'verify_goal', args: {}),
          );
        }
        return Stream.value(const TextResponse('playing'));
      },
      addMessage: (message) async {
        if (stage == 1 &&
            message.text.contains('CONTROLLER COMPLETION REVIEW')) {
          stage = 2;
        }
      },
      execute: (call) async {
        if (call.name == 'ui_action') {
          actions++;
          return {'verification_required': true};
        }
        return {'status': call.name == 'verify_goal' ? 'matched' : 'ok'};
      },
      taskMemory: AiTaskMemory('Find the song and play it'),
      restartContext: (_) async {},
      requireGoalCheck: true,
      isCancelled: () => false,
      takeImage: () => null,
      onLimit: () => fail('unexpected limit'),
    ).toList();
    expect(actions, 2);
    expect(output.whereType<TextResponse>().map((part) => part.token), [
      'playing',
    ]);
  });

  test(
    'context handoff supplies fresh UI before the next model inference',
    () async {
      var turns = 0;
      var freshReads = 0;
      final messages = <Message>[];
      await runAiToolLoop(
        generate: () {
          turns++;
          if (turns == 1) {
            return Stream.value(
              const FunctionCallResponse(name: 'ui_action', args: {}),
            );
          }
          expect(freshReads, greaterThan(0));
          expect(
            messages.any(
              (message) =>
                  message.text.contains('CURRENT UI AFTER CONTEXT HANDOFF'),
            ),
            isTrue,
          );
          if (turns == 2) {
            return Stream.value(
              const FunctionCallResponse(name: 'verify_goal', args: {}),
            );
          }
          return Stream.value(const TextResponse('done'));
        },
        addMessage: (message) async => messages.add(message),
        execute: (call) async {
          if (call.name == 'read_current_ui') {
            freshReads++;
            expect(call.args['automatic'], isTrue);
            return {'status': 'ok'};
          }
          return call.name == 'ui_action'
              ? {'verification_required': true}
              : {'status': 'matched'};
        },
        taskMemory: AiTaskMemory('Finish original goal')
          ..targetPackage = 'app.target',
        restartContext: (_) async {},
        maxRounds: 1,
        requireGoalCheck: true,
        isCancelled: () => false,
        takeImage: () => null,
        onLimit: () => fail('unexpected limit'),
      ).drain<void>();
      expect(freshReads, greaterThan(0));
    },
  );
  test('an empty model turn receives a recovery prompt instead of ending immediately', () async {
    var generations = 0;
    var prompts = 0;
    final output = await runAiToolLoop(
      generate: () => ++generations == 1
          ? const Stream.empty()
          : Stream.value(const TextResponse('recovered')),
      addMessage: (_) async {
        prompts++;
      },
      execute: (_) async => {},
      restartContext: (_) async {},
      isCancelled: () => false,
      takeImage: () => null,
      onLimit: () => fail('unexpected limit'),
    ).toList();
    expect(generations, 2);
    expect(prompts, 1);
    expect(output.whereType<TextResponse>().single.token, 'recovered');
  });
  test(
    'target can be reopened when a fresh read is unavailable after rollover',
    () async {
      final names = [
        'read_current_ui',
        'open_app',
        'read_current_ui',
        'verify_goal',
      ];
      var round = 0;
      var opened = false;
      await runAiToolLoop(
        generate: () => Stream.value(
          round < names.length
              ? FunctionCallResponse(name: names[round++], args: {})
              : const TextResponse('done'),
        ),
        addMessage: (_) async {},
        execute: (call) async {
          if (call.name == 'open_app') {
            opened = true;
            return {'status': 'opened'};
          }
          if (call.name == 'verify_goal') return {'status': 'matched'};
          return opened
              ? {'status': 'ok'}
              : {'code': 'TARGET_NOT_READY', 'error': 'not foreground'};
        },
        taskMemory: AiTaskMemory('continue')..targetPackage = 'app.target',
        maxRounds: 1,
        restartContext: (_) async {},
        requireGoalCheck: true,
        isCancelled: () => false,
        takeImage: () => null,
        onLimit: () => fail('unexpected task limit'),
        onBlocked: (_, _) => fail('reopening must be allowed'),
      ).drain<void>();
      expect(opened, isTrue);
    },
  );
  test(
    'one task passes old round/call limits across context rotations',
    () async {
      var actions = 0;
      var needRead = true;
      var verified = false;
      var rotations = 0;
      final checkpoints = <String>[];
      final memory = AiTaskMemory('ทำงานเดิมทั้งหมด 20 ขั้น')
        ..targetPackage = 'app.target';
      final output = await runAiToolLoop(
        generate: () => Stream.value(
          needRead
              ? const FunctionCallResponse(name: 'read_current_ui', args: {})
              : actions < 20
              ? FunctionCallResponse(
                  name: 'ui_action',
                  args: {'label': 'ขั้น $actions', 'action': 'tap'},
                )
              : !verified
              ? const FunctionCallResponse(
                  name: 'verify_goal',
                  args: {'label': 'เสร็จแล้ว'},
                )
              : const TextResponse('ครบทุกขั้นแล้ว'),
        ),
        addMessage: (_) async {},
        execute: (call) async {
          switch (call.name) {
            case 'read_current_ui':
              needRead = false;
              return {
                'status': 'ok',
                'offset': 0,
                'elements': [
                  {'label': 'ขั้น $actions'},
                ],
              };
            case 'ui_action':
              actions++;
              needRead = true;
              return {
                'code': 'ACTION_DISPATCHED',
                'verification_required': true,
              };
            default:
              verified = true;
              return {'status': 'matched'};
          }
        },
        isCancelled: () => false,
        takeImage: () => null,
        onLimit: () => fail('A context limit must not end a progressing task'),
        onStalled: (reason) => fail(reason),
        requireGoalCheck: true,
        maxRounds: 4,
        maxCalls: 4,
        maxResultBytes: 700,
        taskMemory: memory,
        onTaskState: checkpoints.add,
        restartContext: (checkpoint) async {
          final state = jsonDecode(checkpoint);
          expect(state['original_request'], 'ทำงานเดิมทั้งหมด 20 ขั้น');
          expect(state['target_package'], 'app.target');
          rotations++;
          needRead = true;
        },
      ).toList();
      expect(actions, 20);
      expect(rotations, greaterThan(1));
      expect(checkpoints, isNotEmpty);
      expect(output.whereType<TextResponse>().single.token, 'ครบทุกขั้นแล้ว');
    },
  );

  test('fresh read allows next action; matched intermediate evidence does not end task', () async {
    final names = [
      'ui_action',
      'read_current_ui',
      'verify_goal',
      'ui_action',
      'read_current_ui',
      'verify_goal',
    ];
    var round = 0;
    var actions = 0;
    await runAiToolLoop(
      generate: () => Stream.value(
        round < names.length
            ? FunctionCallResponse(name: names[round++], args: {})
            : const TextResponse('done'),
      ),
      addMessage: (_) async {},
      execute: (call) async {
        if (call.name == 'ui_action') {
          actions++;
          return {'verification_required': true, 'code': 'ACTION_DISPATCHED'};
        }
        return {'status': call.name == 'verify_goal' ? 'matched' : 'ok'};
      },
      requireGoalCheck: true,
      restartContext: (_) async {},
      isCancelled: () => false,
      takeImage: () => null,
      onLimit: () => fail('unexpected limit'),
    ).drain<void>();
    expect(actions, 2);
  });

  test(
    'context capacity error rolls context once without replaying a mutation',
    () async {
      var generation = 0;
      var executions = 0;
      var rotations = 0;
      final output = await runAiToolLoop(
        generate: () {
          generation++;
          if (generation == 1) {
            return Stream.value(
              const FunctionCallResponse(name: 'ui_action', args: {}),
            );
          }
          if (generation == 2) {
            return Stream.error(
              StateError(
                'Prefill input length exceeds available state entries',
              ),
            );
          }
          if (generation == 3) {
            return Stream.value(
              const FunctionCallResponse(name: 'read_current_ui', args: {}),
            );
          }
          if (generation == 4) {
            return Stream.value(
              const FunctionCallResponse(name: 'verify_goal', args: {}),
            );
          }
          return Stream.value(const TextResponse('done'));
        },
        addMessage: (_) async {},
        execute: (call) async {
          if (call.name == 'ui_action') {
            executions++;
            return {'verification_required': true};
          }
          return {'status': call.name == 'verify_goal' ? 'matched' : 'ok'};
        },
        requireGoalCheck: true,
        restartContext: (_) async {
          rotations++;
        },
        isCancelled: () => false,
        takeImage: () => null,
        onLimit: () {},
      ).toList();
      expect(executions, 1);
      expect(rotations, 1);
      expect(output.whereType<TextResponse>().single.token, 'done');
    },
  );

  test(
    'unchanged screen errors get retries but eventually stop without progress',
    () async {
      var attempts = 0;
      var round = 0;
      String? stopped;
      await runAiToolLoop(
        generate: () => Stream.value(
          FunctionCallResponse(
            name: round++ % 2 == 0 ? 'read_current_ui' : 'ui_action',
            args: {},
          ),
        ),
        addMessage: (_) async {},
        execute: (call) async {
          if (call.name == 'read_current_ui') {
            return {
              'status': 'ok',
              'elements': [
                {'label': 'same'},
              ],
            };
          }
          attempts++;
          return {'code': 'STALE_SCREEN', 'error': 'changed'};
        },
        restartContext: (_) async {},
        isCancelled: () => false,
        takeImage: () => null,
        onLimit: () => fail('unexpected limit'),
        onStalled: (reason) => stopped = reason,
      ).drain<void>();
      expect(attempts, 4);
      expect(stopped, contains('No progress'));
    },
  );

  test('Stop during context handoff executes no subsequent tools', () async {
    var cancelled = false;
    var calls = 0;
    await runAiToolLoop(
      generate: () => Stream.value(
        const FunctionCallResponse(name: 'read_current_ui', args: {}),
      ),
      addMessage: (_) async {},
      execute: (_) async {
        calls++;
        return {'status': 'ok'};
      },
      maxRounds: 1,
      restartContext: (_) async {
        cancelled = true;
      },
      isCancelled: () => cancelled,
      takeImage: () => null,
      onLimit: () {},
    ).drain<void>();
    expect(calls, 1);
  });
}
