import 'package:flutter/services.dart';

class MobilePilotPlatform {
  const MobilePilotPlatform();

  static const _channel = MethodChannel('com.mobilepilot/settings');

  Future<bool?> isAccessibilityServiceEnabled() =>
      _channel.invokeMethod<bool>('isAccessibilityServiceEnabled');

  Future<void> openAccessibilitySettings() =>
      _channel.invokeMethod<void>('openAccessibilitySettings');

  Future<bool?> getFloatingControlsEnabled() =>
      _channel.invokeMethod<bool>('getFloatingControlsEnabled');

  Future<Map<String, dynamic>?> setFloatingControlsEnabled(bool enabled) =>
      _channel.invokeMapMethod<String, dynamic>('setFloatingControlsEnabled', {
        'enabled': enabled,
      });

  Future<Map<String, dynamic>?> getSettingsTapTestResult() =>
      _channel.invokeMapMethod<String, dynamic>('getSettingsTapTestResult');

  Future<Map<String, dynamic>?> startSettingsTapTest(String text) => _channel
      .invokeMapMethod<String, dynamic>('startSettingsTapTest', {'text': text});

  Future<List<Map<String, String>>> findLaunchableApps(String query) async {
    final response =
        await _channel.invokeListMethod<dynamic>('findLaunchableApps', {
          'query': query,
        }) ??
        [];
    return response
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (entry) => <String, String>{
            'label': entry['label']?.toString() ?? '',
            'packageName': entry['packageName']?.toString() ?? '',
          },
        )
        .where(
          (app) => app['label']!.isNotEmpty && app['packageName']!.isNotEmpty,
        )
        .toList();
  }

  Future<Map<String, dynamic>?> launchApp(String packageName) =>
      _channel.invokeMapMethod<String, dynamic>('launchApp', {
        'packageName': packageName,
      });

  Future<List<Map<String, dynamic>>> getUiTree() async {
    final response =
        await _channel.invokeListMethod<dynamic>('getUiTree') ?? [];
    return response
        .whereType<Map<dynamic, dynamic>>()
        .map((element) => Map<String, dynamic>.from(element))
        .toList();
  }

  Future<Map<dynamic, dynamic>?> armScreenCapture() =>
      _channel.invokeMapMethod<dynamic, dynamic>('armScreenCapture');

  Future<Map<dynamic, dynamic>?> getCapturedScreen() =>
      _channel.invokeMapMethod<dynamic, dynamic>('getCapturedScreen');

  Future<void> cancelScreenCapture() =>
      _channel.invokeMethod<void>('cancelScreenCapture');

  Future<Map<String, dynamic>?> queuePointTap({
    required double x,
    required double y,
    required int width,
    required int height,
    required int rotation,
    required String packageName,
  }) => _channel.invokeMapMethod<String, dynamic>('queuePointTap', {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'rotation': rotation,
    'packageName': packageName,
  });

  Future<Map<String, dynamic>?> getPointTapResult() =>
      _channel.invokeMapMethod<String, dynamic>('getPointTapResult');

  Future<Map<String, dynamic>?> queueScreenAction({
    required String action,
    required String packageName,
    required int width,
    required int height,
    required int rotation,
    String? text,
  }) => _channel.invokeMapMethod<String, dynamic>('queueScreenAction', {
    'action': action,
    'packageName': packageName,
    'width': width,
    'height': height,
    'rotation': rotation,
    'text': text,
  });

  Future<Map<String, dynamic>?> tapElementByText(String text) => _channel
      .invokeMapMethod<String, dynamic>('tapElementByText', {'text': text});

  Future<Map<String, dynamic>?> tapElementByTextWithGesture(String text) =>
      _channel.invokeMapMethod<String, dynamic>('tapElementByTextWithGesture', {
        'text': text,
      });
}
