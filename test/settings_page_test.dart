import 'helpers/pump_ready_app.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/localized_test_app.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:mobile_pilot/app.dart';
import 'package:mobile_pilot/core/settings/app_settings.dart';
import 'package:mobile_pilot/core/theme/app_theme.dart';
import 'package:mobile_pilot/features/settings/presentation/screen/settings_page.dart';

class MemorySettings extends AppSettings {
  ThemeMode mode = ThemeMode.dark;
  double rate = 0.5;
  @override
  ThemeMode get themeMode => mode;
  @override
  double get speechRate => rate;
  @override
  Future<void> setThemeMode(ThemeMode value) async {
    mode = value;
    notifyListeners();
  }

  @override
  Future<void> setSpeechRate(double value) async {
    rate = value;
    notifyListeners();
  }
}

void main() {
  const platform = MethodChannel('com.mobilepilot/settings');
  const tts = MethodChannel('flutter_tts');
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(platform, null);
    messenger.setMockMethodCallHandler(tts, null);
  });

  testWidgets(
    'permissions, theme and speech settings work on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final calls = <MethodCall>[];
      final speechCalls = <MethodCall>[];
      messenger.setMockMethodCallHandler(platform, (call) async {
        calls.add(call);
        return switch (call.method) {
          'isAccessibilityServiceEnabled' => true,
          'getFloatingControlsEnabled' => false,
          'setFloatingControlsEnabled' => {'enabled': true},
          _ => null,
        };
      });
      messenger.setMockMethodCallHandler(tts, (call) async {
        speechCalls.add(call);
        return call.method == 'isLanguageAvailable' ? true : 1;
      });
      final settings = MemorySettings();
      await tester.pumpWidget(
        AppSettingsScope(
          settings: settings,
          child: ListenableBuilder(
            listenable: settings,
            builder: (_, _) => LocalizedTestApp(
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              themeMode: settings.themeMode,
              home: const SettingsPage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('เปิดอยู่'), findsOneWidget);
      await tester.tap(find.text('การช่วยเหลือพิเศษ'));
      await tester.pumpAndSettle();
      expect(
        calls.any((call) => call.method == 'openAccessibilitySettings'),
        isTrue,
      );
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(calls.last.arguments, {'enabled': true});
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      await tester.tap(find.byTooltip('เลือกธีม'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('สว่าง').last);
      await tester.pumpAndSettle();
      expect(settings.themeMode, ThemeMode.light);
      expect(
        Theme.of(tester.element(find.byType(SettingsPage))).brightness,
        Brightness.light,
      );
      await tester.ensureVisible(find.byTooltip('เลือกความเร็วในการอ่าน'));
      await tester.tap(find.byTooltip('เลือกความเร็วในการอ่าน'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('เร็ว').last);
      await tester.pumpAndSettle();
      expect(settings.speechRate, 0.75);
      await tester.ensureVisible(find.text('ทดลองฟังเสียง'));
      await tester.tap(find.text('ทดลองฟังเสียง'));
      await tester.pumpAndSettle();
      expect(
        speechCalls
            .firstWhere((call) => call.method == 'setSpeechRate')
            .arguments,
        0.75,
      );
      expect(speechCalls.any((call) => call.method == 'speak'), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    },
  );
  testWidgets('sidebar opens settings and back returns to home', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(platform, (call) async => false);
    await pumpReadyApp(
      tester,
      const MobilePilotApp(
        useDebugUi: false,
        translationLoader: TestTranslationLoader(),
      ),
    );
    await tester.tap(find.byIcon(TablerIcons.menu_2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('การตั้งค่า'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    await tester.tap(find.byTooltip('ย้อนกลับ'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsNothing);
    expect(find.text('สวัสดี'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'switches Thai and English immediately and restores saved language',
    (tester) async {
      messenger.setMockMethodCallHandler(platform, (call) async => false);
      final settings = MemorySettings();
      Widget page() => AppSettingsScope(
        settings: settings,
        child: const LocalizedTestApp(home: SettingsPage()),
      );
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(find.text('การตั้งค่า'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('เลือกภาษาแอป'));
      await tester.tap(find.byTooltip('เลือกภาษาแอป'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English').last);
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('App language'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('locale'), 'en');
      await tester.tap(find.byTooltip('Choose app language'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ไทย').last);
      await tester.pumpAndSettle();
      expect(find.text('การตั้งค่า'), findsOneWidget);
      expect(preferences.getString('locale'), 'th');
      await tester.tap(find.byTooltip('เลือกภาษาแอป'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English').last);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await EasyLocalization.ensureInitialized();
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('App language'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
    },
  );
}
