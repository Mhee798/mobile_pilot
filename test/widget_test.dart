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

  testWidgets(
    'Disabled accessibility shows setup and can refresh into commands',
    (tester) async {
      await tester.pumpWidget(const MobilePilotApp());
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
      await tester.pumpWidget(const MobilePilotApp());
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
}
