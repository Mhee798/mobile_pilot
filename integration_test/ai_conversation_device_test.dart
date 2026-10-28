import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_pilot/features/ai/data/ai_model_service.dart';
import 'package:mobile_pilot/core/platform/mobile_pilot_platform.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('saved model responds to two consecutive messages', (
    tester,
  ) async {
    final service = AiModelService();
    try {
      expect(
        await service.hasSavedModel(),
        isTrue,
        reason: 'A previously installed model is required.',
      );
      await service.loadSaved();
      final first = StringBuffer();
      final second = StringBuffer();
      await service.generate('Hello. Say hello briefly.', first.write);
      await service.generate('What did I just say?', second.write);
      expect(first.toString().trim(), isNotEmpty);
      expect(second.toString().trim(), isNotEmpty);
    } finally {
      await service.close();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('model continues while settings is in the foreground', (
    tester,
  ) async {
    const platform = MobilePilotPlatform();
    final service = AiModelService();
    try {
      var enabled = await platform.isAccessibilityServiceEnabled() == true;
      for (var attempt = 0; attempt < 60 && !enabled; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        enabled = await platform.isAccessibilityServiceEnabled() == true;
      }
      expect(enabled, isTrue, reason: 'Enable MobilePilot Accessibility.');
      await service.loadSaved();
      final first = StringBuffer();
      final second = StringBuffer();
      await service.generate('Hello. Say hello briefly.', first.write);
      final launch = await platform.launchApp('com.android.settings');
      expect(launch?['code'], 'TARGET_READY');
      await service.generate('What did I just say?', second.write);
      expect(first.toString().trim(), isNotEmpty);
      expect(second.toString().trim(), isNotEmpty);
    } finally {
      await service.close();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
