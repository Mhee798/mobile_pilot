import 'package:flutter/services.dart';

import 'dart:async';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/features/ai/application/gemini_chat_controller.dart';
import 'package:mobile_pilot/features/ai/data/gemini_device_chat.dart';

GenerateContentResponse chunk(List<Part> parts) => GenerateContentResponse([
  Candidate(Content.model(parts), null, null, null, null),
], null);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.mobilepilot/settings');
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null),
  );
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  test(
    'cloud attachments preserve image mime and file text in the request',
    () async {
      List<Content>? request;
      final chat = GeminiChatController(
        reply: (_, contents) async {
          request = contents;
          return 'done';
        },
      );
      chat.send(
        'summarize',
        image: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/png',
        fileText: '\nfile contents',
      );
      while (chat.busy) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(
        request!.last.parts.whereType<TextPart>().single.text,
        contains('file contents'),
      );
      final image = request!.last.parts.whereType<InlineDataPart>().single;
      expect(image.mimeType, 'image/png');
      expect(image.bytes, [1, 2, 3]);
      chat.dispose();
    },
  );

  test('cloud displays partial answer before stream finishes and hides thought text', () async {
    final gate = Completer<void>();
    final chat = GeminiChatController(
      initializeFirebase: () async {},
      deviceChat: GeminiDeviceChat(
        generateStream: (_) async* {
          yield chunk([const TextPart('internal thought', isThought: true)]);
          yield chunk([const TextPart('Hello ')]);
          await gate.future;
          yield chunk([const TextPart('world')]);
        },
      ),
    );
    chat.setToolsEnabled(true);
    expect(chat.send('test'), isTrue);
    while (chat.messages.length < 2 || chat.messages.last.text.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(chat.busy, isTrue);
    expect(chat.messages.last.text, 'Hello ');
    gate.complete();
    while (chat.busy) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(chat.messages, hasLength(2));
    expect(chat.messages.last.text, 'Hello world');
    chat.dispose();
  });

  test(
    'streamed function calls execute once and final answer continues streaming',
    () async {
      var round = 0;
      final executed = <String>[];
      final chat = GeminiChatController(
        initializeFirebase: () async {},
        deviceChat: GeminiDeviceChat(
          generateStream: (_) async* {
            if (round++ == 0) {
              yield chunk([FunctionCall('device_info', {})]);
            } else {
              yield chunk([const TextPart('Result ')]);
              yield chunk([const TextPart('received')]);
            }
          },
          execute: (name, args) async {
            executed.add(name);
            return {'status': 'ok'};
          },
        ),
      );
      chat.setToolsEnabled(true);
      chat.send('check device');
      while (chat.busy) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(executed, ['device_info']);
      expect(chat.messages.last.text, 'Result received');
      chat.dispose();
    },
  );

  test('stop still releases cloud task when native Accessibility service is absent', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'cancelScreenActions') {
            throw PlatformException(code: 'SERVICE_UNAVAILABLE');
          }
          return null;
        });
    final source = StreamController<GenerateContentResponse>();
    final chat = GeminiChatController(
      initializeFirebase: () async {},
      deviceChat: GeminiDeviceChat(generateStream: (_) => source.stream),
    );
    chat.setToolsEnabled(true);
    chat.send('test');
    source.add(chunk([const TextPart('Partial')]));
    while (chat.messages.length < 2) {
      await Future<void>.delayed(Duration.zero);
    }
    await chat.stop();
    while (chat.busy) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(chat.messages.last.error, isTrue);
    chat.dispose();
    await source.close();
  });

  test(
    'stop cancels a stalled stream and keeps partial answer marked as failed',
    () async {
      final source = StreamController<GenerateContentResponse>();
      final chat = GeminiChatController(
        initializeFirebase: () async {},
        deviceChat: GeminiDeviceChat(generateStream: (_) => source.stream),
      );
      chat.setToolsEnabled(true);
      chat.send('test');
      source.add(chunk([const TextPart('Partial')]));
      while (chat.messages.length < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      await chat.stop();
      while (chat.busy) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(chat.messages.last.error, isTrue);
      expect(chat.messages.last.text, contains('Partial'));
      chat.dispose();
      await source.close();
    },
  );
}
