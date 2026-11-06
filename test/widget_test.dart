import 'helpers/pump_ready_app.dart';
import 'helpers/localized_test_app.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_pilot/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.mobilepilot/settings');
  var accessibilityEnabled = false;

  setUp(() {
    accessibilityEnabled = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return switch (call.method) {
            'isAccessibilityServiceEnabled' => accessibilityEnabled,
            'getFloatingControlsEnabled' => false,
            _ => null,
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('production entry is separate from existing debug screens', (
    tester,
  ) async {
    await pumpReadyApp(
      tester,
      const MobilePilotApp(
        translationLoader: TestTranslationLoader(),
        useDebugUi: false,
      ),
    );
    expect(find.text('สวัสดี'), findsOneWidget);
    expect(find.byType(AccessibilitySetupPage), findsNothing);
    expect(find.byType(CommandPage), findsNothing);
  });

  testWidgets(
    'Disabled accessibility shows setup and can refresh into commands',
    (tester) async {
      await tester.pumpWidget(
        const MobilePilotApp(translationLoader: TestTranslationLoader()),
      );
      await tester.pumpAndSettle();
      expect(find.text('ยังไม่ได้เปิดใช้งาน'), findsOneWidget);
      expect(find.text('เปิดการตั้งค่า Accessibility'), findsOneWidget);

      accessibilityEnabled = true;
      await tester.tap(find.byTooltip('ตรวจสอบอีกครั้ง'));
      await tester.pumpAndSettle();
      expect(find.text('สั่งงาน'), findsOneWidget);
      expect(find.byType(AccessibilitySetupPage), findsNothing);
    },
  );

  testWidgets(
    'Enabled accessibility opens commands and manual tap still works',
    (tester) async {
      accessibilityEnabled = true;
      await tester.pumpWidget(
        const MobilePilotApp(translationLoader: TestTranslationLoader()),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CommandPage), findsOneWidget);
      expect(find.text('ผลทดสอบ: ถูกแตะ 0 ครั้ง'), findsOneWidget);

      final tapButton = find.text('ปุ่มทดสอบการแตะ');
      await tester.ensureVisible(tapButton);
      await tester.tap(tapButton);
      await tester.pump();
      expect(find.text('ผลทดสอบ: ถูกแตะ 1 ครั้ง'), findsOneWidget);
    },
  );

  testWidgets('AI test page can be opened and returns to commands', (
    tester,
  ) async {
    accessibilityEnabled = true;
    await tester.pumpWidget(
      const MobilePilotApp(translationLoader: TestTranslationLoader()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('ทดสอบ AI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('จัดการโมเดล'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('เลือกและโหลดโมเดล'));
    expect(find.text('เลือกและโหลดโมเดล'), findsOneWidget);
    expect(find.text('ยังไม่ได้โหลดโมเดล'), findsOneWidget);
    await tester.tap(find.text('Gemma 4 E2B · Vision (ประมาณ 2.6 GB)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ระบุลิงก์เอง').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ดาวน์โหลดโมเดล'));
    await tester.tap(find.text('ดาวน์โหลดโมเดล'));
    await tester.pump();
    expect(
      find.text('กรุณาใส่ลิงก์ HTTPS ของไฟล์ .litertlm โดยตรง'),
      findsOneWidget,
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(CommandPage), findsOneWidget);
  });
}
