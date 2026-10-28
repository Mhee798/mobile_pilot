import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_pilot/core/platform/mobile_pilot_platform.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const platform = MobilePilotPlatform();
  const settingsPackage = String.fromEnvironment(
    'SETTINGS_PACKAGE',
    defaultValue: 'com.android.settings',
  );

  testWidgets('finds device settings in Thai and English', (tester) async {
    for (final query in ['ตั้งค่า', 'Settings']) {
      final apps = await platform.findLaunchableApps(query);
      expect(apps.any((app) => app['packageName'] == settingsPackage), isTrue,
          reason: 'Settings package not found for query "$query"');
    }
  });
}
