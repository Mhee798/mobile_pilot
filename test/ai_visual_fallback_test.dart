import 'dart:typed_data';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/features/ai/data/ai_tool_loop.dart';
import 'package:mobile_pilot/features/ai/data/ai_visual_fallback.dart';

Map<String, dynamic> page({int offset = 0}) => {
  'status': 'ok',
  'offset': offset,
  'elements': [
    {'label': 'ค้นหา', 'can_tap': true},
  ],
};

void main() {
  test('post-action reads and paging are normal; repeated same UI triggers capture', () {
    final policy = AiVisualFallback();
    expect(policy.observe('read_current_ui', page()), isNull);
    expect(
      policy.observe('ui_action', {'verification_required': true}),
      isNull,
    );
    expect(policy.observe('read_current_ui', page()), isNull);
    expect(policy.observe('read_ui_page', page(offset: 10)), isNull);
    expect(policy.observe('read_ui_page', page(offset: 20)), isNull);
    expect(policy.observe('read_current_ui', page()), contains('Repeated UI'));
    policy.captureAttempted();
    expect(policy.observe('read_current_ui', page()), isNull);
    expect(policy.observe('read_current_ui', page()), isNull);
  });

  test('two UI failures trigger a visual strategy; no screenshot for disconnected service', () {
    final policy = AiVisualFallback();
    const stale = {'error': 'screen changed', 'code': 'STALE_SCREEN'};
    expect(policy.observe('ui_action', stale), isNull);
    expect(policy.observe('ui_action', stale), isNotNull);
    final unavailable = AiVisualFallback();
    for (var i = 0; i < 4; i++) {
      expect(
        unavailable.observe('ui_action', {
          'error': 'not ready',
          'code': 'SERVICE_NOT_READY',
        }),
        isNull,
      );
    }
  });

  test('manual capture suppresses automatic duplicates on the same view', () {
    final policy = AiVisualFallback();
    policy.observe('read_current_ui', page());
    policy.observe('capture_screen', {'status': 'captured'});
    expect(policy.observe('read_current_ui', page()), isNull);
    expect(policy.observe('read_current_ui', page()), isNull);
  });

  for (final vision in [true, false]) {
    test(
      'repeated reads add image to next inference only with Vision=$vision',
      () async {
        var turns = 0;
        var captures = 0;
        Uint8List? pending;
        final messages = <Message>[];
        final deliveries = <bool>[];
        final output = await runAiToolLoop(
          generate: () async* {
            turns++;
            if (turns <= 2) {
              yield FunctionCallResponse(
                name: 'read_current_ui',
                args: const {},
                id: 'read$turns',
              );
            } else {
              expect(
                messages.where((m) => m.imageBytes?.isNotEmpty == true).length,
                vision ? 1 : 0,
              );
              if (vision) {
                final observation = messages.last;
                expect(observation.type, isNot(MessageType.toolResponse));
                expect(observation.text, contains('img-real'));
                expect(observation.imageBytes, [1, 2, 3]);
              }
              yield const TextResponse('ต่อจากภาพได้แล้ว');
            }
          },
          addMessage: (message) async => messages.add(message),
          execute: (call) async {
            if (call.name == 'capture_screen') {
              captures++;
              expect(call.args['automatic'], isTrue);
              pending = Uint8List.fromList([1, 2, 3]);
              return {'status': 'captured', 'capture_id': 'img-real'};
            }
            return page();
          },
          takeImage: () {
            final bytes = pending;
            pending = null;
            return bytes;
          },
          restartContext: (_) async {},
          enableVisualFallback: vision,
          onImageAdded: (_, automatic) async => deliveries.add(automatic),
          isCancelled: () => false,
          onLimit: () => fail('unexpected limit'),
        ).toList();
        expect(captures, vision ? 1 : 0);
        expect(deliveries, vision ? [true] : isEmpty);
        expect(
          output.whereType<TextResponse>().single.token,
          'ต่อจากภาพได้แล้ว',
        );
      },
    );
  }

  test('context rotation happens before auto capture, never between image and inference', () async {
    final events = <String>[];
    var turns = 0;
    Uint8List? pending;
    await runAiToolLoop(
      generate: () async* {
        events.add('generate');
        if (++turns <= 2) {
          yield const FunctionCallResponse(name: 'read_current_ui', args: {});
        } else {
          yield const TextResponse('done');
        }
      },
      addMessage: (message) async {
        if (message.imageBytes != null) events.add('image');
      },
      execute: (call) async {
        if (call.name == 'capture_screen') {
          events.add('capture');
          pending = Uint8List.fromList([4]);
          return {'status': 'captured', 'capture_id': 'c1'};
        }
        return page();
      },
      takeImage: () {
        final bytes = pending;
        pending = null;
        return bytes;
      },
      maxResultBytes: 1,
      restartContext: (_) async => events.add('rotate'),
      enableVisualFallback: true,
      isCancelled: () => false,
      onLimit: () => fail('unexpected limit'),
    ).drain<void>();
    expect(events.sublist(events.indexOf('capture')), [
      'capture',
      'image',
      'generate',
    ]);
    expect(events[events.indexOf('capture') - 1], 'rotate');
  });

  test(
    'failed capture reports no image instead of pretending it was seen',
    () async {
      var turns = 0;
      var captures = 0;
      final messages = <Message>[];
      await runAiToolLoop(
        generate: () => ++turns <= 3
            ? Stream.value(
                const FunctionCallResponse(name: 'read_current_ui', args: {}),
              )
            : Stream.value(const TextResponse('cannot see image')),
        addMessage: (message) async => messages.add(message),
        execute: (call) async {
          if (call.name == 'capture_screen') {
            captures++;
            return {'error': 'screen changed', 'code': 'STALE_SCREEN'};
          }
          return page();
        },
        takeImage: () => null,
        restartContext: (_) async {},
        enableVisualFallback: true,
        isCancelled: () => false,
        onLimit: () {},
      ).drain<void>();
      expect(captures, 1);
      expect(messages.where((m) => m.imageBytes != null), isEmpty);
      expect(
        messages.any((m) => m.text.contains('No image was delivered')),
        isTrue,
      );
    },
  );

  test(
    'a model batch cannot act on an image before the next inference sees it',
    () async {
      var turns = 0;
      var actions = 0;
      Uint8List? pending;
      String? blocked;
      await runAiToolLoop(
        generate: () => ++turns == 1
            ? Stream.value(
                const ParallelFunctionCallResponse(
                  calls: [
                    FunctionCallResponse(
                      name: 'capture_screen',
                      args: {},
                      id: 'capture',
                    ),
                    FunctionCallResponse(
                      name: 'screen_action',
                      args: {'capture_id': 'img1', 'action': 'tap'},
                      id: 'tap',
                    ),
                  ],
                ),
              )
            : Stream.value(const TextResponse('image observed')),
        addMessage: (_) async {},
        execute: (call) async {
          if (call.name == 'screen_action') actions++;
          pending = Uint8List.fromList([1]);
          return {'status': 'captured', 'capture_id': 'img1'};
        },
        takeImage: () {
          final bytes = pending;
          pending = null;
          return bytes;
        },
        restartContext: (_) async {},
        enableVisualFallback: true,
        onBlocked: (_, result) => blocked = result['code'] as String?,
        isCancelled: () => false,
        onLimit: () {},
      ).drain<void>();
      expect(actions, 0);
      expect(blocked, 'IMAGE_NOT_OBSERVED');
    },
  );

  test('Stop after triggering fallback prevents capture', () async {
    var calls = 0;
    var cancelled = false;
    await runAiToolLoop(
      generate: () => Stream.value(
        const FunctionCallResponse(name: 'read_current_ui', args: {}),
      ),
      addMessage: (_) async {},
      execute: (call) async {
        expect(call.name, 'read_current_ui');
        if (++calls == 2) cancelled = true;
        return page();
      },
      takeImage: () => null,
      restartContext: (_) async {},
      enableVisualFallback: true,
      isCancelled: () => cancelled,
      onLimit: () {},
    ).drain<void>();
    expect(calls, 2);
  });
}
