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
        MaterialApp(
          home: Scaffold(
            body: SpeechInputButton(controller: controller, enabled: true),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('mic-level-ring')), findsNothing);
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
      MaterialApp(
        home: Scaffold(
          body: SpeechInputButton(controller: controller, enabled: true),
        ),
      ),
    );
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
      MaterialApp(
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
}
