import 'helpers/localized_test_app.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/features/home/presentation/widgets/chat_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugin.csdcorp.com/speech_to_text');
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('does not initialize on mount or listen after disposal', (
    tester,
  ) async {
    final initialization = Completer<bool>();
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'initialize') return initialization.future;
      return true;
    });
    await tester.pumpWidget(
      const LocalizedTestApp(home: Scaffold(body: ChatBar())),
    );
    await tester.pump();
    expect(calls, isEmpty);
    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(calls, contains('initialize'));
    await tester.pumpWidget(const SizedBox());
    initialization.complete(true);
    await tester.pump();
    expect(calls, isNot(contains('listen')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('preserves draft and ignores late results after disabling', (
    tester,
  ) async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return true;
    });
    final controller = TextEditingController(text: 'draft');
    Future<void> show({bool enabled = true}) => tester.pumpWidget(
      LocalizedTestApp(
        home: Scaffold(
          body: ChatBar(controller: controller, enabled: enabled),
        ),
      ),
    );
    Future<void> result(String text, int type) =>
        messenger.handlePlatformMessage(
          channel.name,
          codec.encodeMethodCall(
            MethodCall(
              'textRecognition',
              jsonEncode({
                'alternates': [
                  {'recognizedWords': text, 'confidence': 1.0},
                ],
                'resultType': type,
              }),
            ),
          ),
          (_) {},
        );
    await show();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(IconButton));
    await tester.pump();
    await result('partial', 0);
    await tester.pump();
    expect(controller.text, 'draft');
    await result('spoken words', 2);
    await tester.pump();
    expect(controller.text, 'draft spoken words');
    await show(enabled: false);
    expect(calls, contains('cancel'));
    await result('late words', 2);
    await tester.pump();
    expect(controller.text, 'draft spoken words');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 9));
    controller.dispose();
  });
}
