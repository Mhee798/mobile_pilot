import 'package:firebase_ai/firebase_ai.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/features/ai/presentation/screen/gemini_test_page.dart';
import 'package:mobile_pilot/features/ai/data/ai_run_history.dart';

class _History extends AiRunHistory {
  String? request;
  String? answer;
  @override
  Future<String> start(
    String request,
    String model, {
    required bool tools,
    required bool image,
    bool? vision,
  }) async {
    this.request = request;
    return 'test';
  }

  @override
  Future<void> finish(
    String id,
    String state,
    String reason,
    String answer,
    int elapsedMs, {
    String? taskState,
  }) async {
    this.answer = answer;
  }
}

void main() {
  testWidgets('tool settings keep chat usable with keyboard open', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: GeminiTestPage(reply: (_, _) async => 'ok')),
    );
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(find.text('อนุญาตส่งภาพหน้าจอให้ Gemini'), findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('cloud messages are recorded in run history', (tester) async {
    final history = _History();
    await tester.pumpWidget(
      MaterialApp(
        home: GeminiTestPage(history: history, reply: (_, _) async => 'คำตอบ'),
      ),
    );
    await tester.enterText(find.byType(TextField), 'สวัสดี');
    await tester.tap(find.byTooltip('ส่งข้อความ'));
    await tester.pumpAndSettle();
    expect(history.request, 'สวัสดี');
    expect(history.answer, 'คำตอบ');
  });
  testWidgets('cloud chat sends completed conversation and starts a new chat', (
    tester,
  ) async {
    final requests = <List<Content>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: GeminiTestPage(
          reply: (model, history) async {
            requests.add(history);
            return requests.length == 1 ? 'สวัสดี' : 'จำได้';
          },
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'ชื่อบี');
    await tester.tap(find.byTooltip('ส่งข้อความ'));
    await tester.pumpAndSettle();
    expect(find.text('สวัสดี'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'ฉันชื่ออะไร');
    await tester.tap(find.byTooltip('ส่งข้อความ'));
    await tester.pumpAndSettle();
    expect(requests.map((r) => r.length), [1, 3]);
    expect(find.text('จำได้'), findsOneWidget);
    await tester.tap(find.byTooltip('เริ่มแชทใหม่'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ใหม่');
    await tester.tap(find.byTooltip('ส่งข้อความ'));
    await tester.pumpAndSettle();
    expect(requests.last.length, 1);
  });
}
