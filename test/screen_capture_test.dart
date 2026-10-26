import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/main.dart';

void main() {
  testWidgets('Capture timeout cancels the native request and allows retry', (
    tester,
  ) async {
    const channel = MethodChannel('com.mobilepilot/settings');
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      return switch (call.method) {
        'getFloatingControlsEnabled' => false,
        'armScreenCapture' => {'code': 'CAPTURE_ARMED'},
        _ => null,
      };
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });

    await tester.pumpWidget(const MaterialApp(home: CommandPage()));
    await tester.pumpAndSettle();
    final captureButton = find.text('จับภาพแอปอื่นเพื่อเลือกพิกัด');
    await tester.ensureVisible(captureButton);
    await tester.tap(captureButton);
    await tester.pump();

    // Returning from the target app starts polling for its screenshot.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    for (var attempt = 0; attempt < 40; attempt++) {
      await tester.pump(const Duration(milliseconds: 700));
    }

    expect(
      calls.where((method) => method == 'cancelScreenCapture'),
      hasLength(1),
    );
    expect(find.textContaining('ไม่พบภาพจากแอปอื่น'), findsOneWidget);
    await tester.ensureVisible(captureButton);
    await tester.tap(captureButton);
    await tester.pump();
    expect(calls.where((method) => method == 'armScreenCapture'), hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
