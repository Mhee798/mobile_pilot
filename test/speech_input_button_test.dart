import 'dart:async';

import 'helpers/localized_test_app.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/features/ai/presentation/widgets/speech_input_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugin.csdcorp.com/speech_to_text');
  const codec = StandardMethodCodec();

  testWidgets(
    'microphone ring follows reported sound level and disappears after listening',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'initialize' || call.method == 'listen') return true;
        return null;
      });
      final controller = TextEditingController();
      await tester.pumpWidget(
        LocalizedTestApp(
          home: Scaffold(
            body: SpeechInputButton(controller: controller, enabled: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mic-level-ring')), findsNothing);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('พูดเป็นข้อความ'));
      await tester.pumpAndSettle();
      await messenger.handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(const MethodCall('notifyStatus', 'listening')),
        (_) {},
      );
      expect(find.byKey(const ValueKey('mic-level-ring')), findsOneWidget);
      final initialWidth = tester
          .getSize(find.byKey(const ValueKey('mic-level-ring')))
          .width;
      await messenger.handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(const MethodCall('soundLevelChange', 10.0)),
        (_) {},
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        tester.getSize(find.byKey(const ValueKey('mic-level-ring'))).width,
        greaterThan(initialWidth),
      );
      await tester.tap(find.byTooltip('หยุดฟังเสียง'));
      await tester.pump();
      await messenger.handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(
          const MethodCall('notifyStatus', 'notListening'),
        ),
        (_) {},
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('mic-level-ring')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
      controller.dispose();
      messenger.setMockMethodCallHandler(channel, null);
    },
  );

  testWidgets('reports failure when recognition does not start', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'initialize') return true;
      if (call.method == 'listen') return false;
      return null;
    });
    final controller = TextEditingController();
    await tester.pumpWidget(
      LocalizedTestApp(
        home: Scaffold(
          body: SpeechInputButton(controller: controller, enabled: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('พูดเป็นข้อความ'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(find.byTooltip('พูดเป็นข้อความ'), findsOneWidget);
    expect(find.text('เริ่มฟังเสียงไม่สำเร็จ กรุณาลองใหม่'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  testWidgets('leaving the route cancels active recognition', (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'initialize' || call.method == 'listen') return true;
      return null;
    });
    final controller = TextEditingController();
    await tester.pumpWidget(
      LocalizedTestApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                SpeechInputButton(controller: controller, enabled: true),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(body: Text('next')),
                    ),
                  ),
                  child: const Text('next page'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('พูดเป็นข้อความ'));
    await tester.pump();
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(const MethodCall('notifyStatus', 'listening')),
      (_) {},
    );
    await tester.pump();
    await tester.tap(find.text('next page'));
    await tester.pumpAndSettle();
    expect(calls, contains('cancel'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 9));
    controller.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });
  testWidgets('stopping cancels the pending start-failure timeout', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'initialize') return true;
      if (call.method == 'listen') return false;
      return null;
    });
    final controller = TextEditingController();
    await tester.pumpWidget(
      LocalizedTestApp(
        home: Scaffold(
          body: SpeechInputButton(controller: controller, enabled: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('พูดเป็นข้อความ'));
    await tester.pump();
    await tester.tap(find.byTooltip('หยุดฟังเสียง'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('เริ่มฟังเสียงไม่สำเร็จ กรุณาลองใหม่'), findsNothing);
    expect(find.byTooltip('พูดเป็นข้อความ'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  testWidgets('a delayed stop cannot reset a newer listening session', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final stopped = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'initialize' || call.method == 'listen') return true;
      if (call.method == 'stop') await stopped.future;
      return null;
    });
    final controller = TextEditingController();
    Widget page(bool enabled) => LocalizedTestApp(
      home: Scaffold(
        body: SpeechInputButton(controller: controller, enabled: enabled),
      ),
    );
    Future<void> status(String value) => messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(MethodCall('notifyStatus', value)),
      (_) {},
    );
    await tester.pumpWidget(page(true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('พูดเป็นข้อความ'));
    await tester.pump();
    await status('listening');
    await tester.pump();
    await tester.tap(find.byTooltip('หยุดฟังเสียง'));
    await tester.pump();
    await status('notListening');
    await tester.pump();
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
    await tester.pumpWidget(page(false));
    await tester.pumpWidget(page(true));
    await tester.tap(find.byTooltip('พูดเป็นข้อความ'));
    await tester.pump();
    await status('listening');
    await tester.pump();
    stopped.complete();
    await tester.pump();
    expect(find.byTooltip('หยุดฟังเสียง'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 9));
    controller.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });
}
