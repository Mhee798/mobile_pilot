import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_pilot/core/platform/mobile_pilot_platform.dart';
import 'package:mobile_pilot/features/ai/data/ai_device_tools.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const target = String.fromEnvironment(
    'SETTINGS_PACKAGE',
    defaultValue: 'com.android.settings',
  );
  const platform = MobilePilotPlatform();

  testWidgets('reads the actual foreground settings screen', (tester) async {
    var enabled = await platform.isAccessibilityServiceEnabled() == true;
    for (var attempt = 0; attempt < 120 && !enabled; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      enabled = await platform.isAccessibilityServiceEnabled() == true;
    }
    expect(
      enabled,
      isTrue,
      reason: 'Enable MobilePilot Accessibility before running this test.',
    );
    final launch = await platform.launchApp(target);
    expect(launch?['code'], 'TARGET_READY');
    final result = await AiDeviceTools(targetPackage: target)
        .execute('read_current_ui', {});
    expect(result['status'], 'ok', reason: '${result['error']}');
    expect(result['packageName'], target);
    expect(result['total'] as int, greaterThan(0));
    expect(result['snapshot_id'], isNotEmpty);
  });
}
