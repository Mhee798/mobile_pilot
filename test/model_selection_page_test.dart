import 'package:flutter/services.dart';
import 'package:mobile_pilot/core/settings/app_settings.dart';
import 'package:mobile_pilot/features/settings/presentation/screen/settings_page.dart';
import 'package:mobile_pilot/features/ai/presentation/screen/gemini_test_page.dart';
import 'package:mobile_pilot/features/models/presentation/model_selection_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/features/models/application/model_selection_controller.dart';
import 'package:mobile_pilot/features/models/presentation/screen/model_selection_page.dart';
import 'package:mobile_pilot/features/models/presentation/screen/model_downloads_page.dart';

import 'helpers/fake_model_backend.dart';
import 'helpers/localized_test_app.dart';

void main() {
  testWidgets(
    'local and cloud selection, Nano status, and download navigation fit a phone',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final backend = FakeModelBackend()..nano = 'unavailableDeviceUnsupported';
      final controller = ModelSelectionController(backend);
      await controller.initialize();
      await tester.pumpWidget(
        ModelSelectionScope(
          controller: controller,
          child: const LocalizedTestApp(home: ModelSelectionPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Test Gemma'), findsOneWidget);
      await tester.tap(find.text('Test Gemma'));
      await tester.pumpAndSettle();
      expect(controller.ready, isTrue);
      await tester.tap(find.text('คลาวด์'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gemini 3.8 Flash'));
      await tester.pumpAndSettle();
      expect(controller.selection!.id, 'gemini-3.8-flash');
      expect(backend.calls, contains('cloud:gemini-3.8-flash'));
      await tester.tap(find.text('บนเครื่อง'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('ดาวน์โหลดโมเดล'), 200);
      expect(find.textContaining('อุปกรณ์นี้ยังไม่รองรับ'), findsOneWidget);
      await tester.tap(find.text('ดาวน์โหลดโมเดล'));
      await tester.pumpAndSettle();
      expect(find.byType(ModelDownloadsPage), findsOneWidget);
      expect(find.text('Gemma 4 E2B'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('ลิงก์ดาวน์โหลดเอง'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ModelDownloadsPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'ดาวน์โหลดโมเดล').last,
      );
      await tester.tap(
        find.widgetWithText(FilledButton, 'ดาวน์โหลดโมเดล').last,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('ใส่ลิงก์ HTTPS'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets('settings opens the picker using the shared model scope', (
    tester,
  ) async {
    const channel = MethodChannel('com.mobilepilot/settings');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => false);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final controller = ModelSelectionController(FakeModelBackend());
    await controller.initialize();
    final settings = AppSettings();
    await tester.pumpWidget(
      ModelSelectionScope(
        controller: controller,
        child: AppSettingsScope(
          settings: settings,
          child: const LocalizedTestApp(home: SettingsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('โมเดล'));
    await tester.pumpAndSettle();
    expect(find.byType(ModelSelectionPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
    controller.dispose();
  });

  testWidgets('the existing cloud chat starts with the selected cloud model', (
    tester,
  ) async {
    final controller = ModelSelectionController(FakeModelBackend());
    await controller.initialize();
    await controller.selectCloud('gemini-3.8-flash', 'Gemini 3.8 Flash');
    await tester.pumpWidget(
      ModelSelectionScope(
        controller: controller,
        child: LocalizedTestApp(
          home: GeminiTestPage(reply: (_, _) async => 'ok'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
          .value,
      'gemini-3.8-flash',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
