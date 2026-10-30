import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/features/ai/presentation/widgets/answer_speech_controls.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_tts');
  final calls = <MethodCall>[];

  test('long speech is split without losing characters or breaking emoji', () {
    final text = '${'ก' * 999}😀 ข้อความต่อ';
    final chunks = speechChunks(text, 1000);
    expect(chunks.join(), text);
    expect(chunks.every((chunk) => chunk.length <= 1000), isTrue);
    expect(chunks.first, isNot(endsWith('\ud83d')));
  });

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'isLanguageAvailable') return true;
          return 1;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  testWidgets('reads completed answer and can enable automatic reading', (
    tester,
  ) async {
    Widget page(bool generating, String answer) => MaterialApp(
      home: Scaffold(
        body: AnswerSpeechControls(
          answer: answer,
          generating: generating,
          completed: !generating,
        ),
      ),
    );
    await tester.pumpWidget(page(false, 'สวัสดี'));
    await tester.tap(find.byTooltip('เสียงอ่านคำตอบ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('อ่านคำตอบ'));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'speak').single.arguments, 'สวัสดี');
    await tester.tap(find.byTooltip('เสียงอ่านคำตอบ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('อ่านอัตโนมัติ'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(page(true, ''));
    await tester.pumpWidget(page(false, 'ตอบเสร็จ'));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'speak').last.arguments, 'ตอบเสร็จ');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reports when Thai voice is unavailable', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => call.method == 'isLanguageAvailable' ? false : 1,
        );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AnswerSpeechControls(
            answer: 'สวัสดี',
            generating: false,
            completed: true,
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('เสียงอ่านคำตอบ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('อ่านคำตอบ'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ไม่พบเสียงภาษาไทย'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
