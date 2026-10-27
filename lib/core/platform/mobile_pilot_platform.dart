import 'package:flutter/services.dart';

class MobilePilotPlatform {
  const MobilePilotPlatform();

  static const _channel = MethodChannel('com.mobilepilot/settings');

  Future<Map<String, dynamic>?> navigateGlobally(String action) => _channel
      .invokeMapMethod<String, dynamic>('navigateGlobally', {'action': action});

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

  Future<void> beginCommandSession(String id, String target) =>
      _channel.invokeMethod<void>('beginCommandSession', {
        'sessionId': id,
        'targetPackage': target,
      });
  Future<void> finishCommandSession(String id) =>
      _channel.invokeMethod<void>('finishCommandSession', {'sessionId': id});
  Future<void> cancelCommandSession(String id) =>
      _channel.invokeMethod<void>('cancelCommandSession', {'sessionId': id});

  Future<Map<String, dynamic>?> waitForUi({
    required String requestId,
    required String targetPackage,
    required String selector,
    required String value,
    required int timeoutMs,
    String? runId,
    String condition = 'present',
  }) => _channel.invokeMapMethod<String, dynamic>('waitForUi', {
    'requestId': requestId,
    'targetPackage': targetPackage,
    'selector': selector,
    'value': value,
    'timeoutMs': timeoutMs,
    'runId': ?runId,
    'condition': condition,
  });

  Future<Map<String, dynamic>?> scrollUntilUi({
    required String requestId,
    required String targetPackage,
    required String selector,
    required String value,
    required int timeoutMs,
    required String direction,
    required int maxScrolls,
    String distance = 'long',
  }) => _channel.invokeMapMethod<String, dynamic>('scrollUntilUi', {
    'requestId': requestId,
    'targetPackage': targetPackage,
    'selector': selector,
    'value': value,
    'timeoutMs': timeoutMs,
    'direction': direction,
    'maxScrolls': maxScrolls,
    'distance': distance,
  });

  Future<void> cancelUiWait(String requestId) =>
      _channel.invokeMethod<void>('cancelUiWait', {'requestId': requestId});

  Future<void> setTargetApp(String packageName) =>
      _channel.invokeMethod<void>('setTargetApp', {'packageName': packageName});

  Future<Map<String, dynamic>?> launchApp(
    String packageName, {
    String? runId,
  }) => _channel.invokeMapMethod<String, dynamic>('launchApp', {
    'packageName': packageName,
    'runId': ?runId,
  });

  Future<List<Map<String, dynamic>>> getUiTree({
    String? targetPackage,
    String? runId,
  }) async {
    final response =
        await _channel.invokeListMethod<dynamic>(
          'getUiTree',
          targetPackage == null && runId == null
              ? null
              : {'targetPackage': ?targetPackage, 'runId': ?runId},
        ) ??
        [];
    return response
        .whereType<Map<dynamic, dynamic>>()
        .map((element) => Map<String, dynamic>.from(element))
        .toList();
  }

  Future<Map<dynamic, dynamic>?> armScreenCapture({String? targetPackage}) =>
      _channel.invokeMapMethod<dynamic, dynamic>(
        'armScreenCapture',
        targetPackage == null ? null : {'targetPackage': targetPackage},
      );

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

  Future<Map<String, dynamic>?> editElementById({
    required String screenId,
    required String nodeId,
    required String targetPackage,
    required String action,
    String text = '',
  }) => _channel.invokeMapMethod<String, dynamic>('editElementById', {
    'screenId': screenId,
    'nodeId': nodeId,
    'targetPackage': targetPackage,
    'action': action,
    'text': text,
  });

  Future<Map<String, dynamic>?> queueDoubleTap({
    required double x,
    required double y,
    required int width,
    required int height,
    required int rotation,
    required String packageName,
  }) => _channel.invokeMapMethod<String, dynamic>('queueDoubleTap', {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'rotation': rotation,
    'packageName': packageName,
  });

  Future<Map<String, dynamic>?> queueLongPress({
    required double x,
    required double y,
    required int width,
    required int height,
    required int rotation,
    required String packageName,
    required int durationMs,
  }) => _channel.invokeMapMethod<String, dynamic>('queueLongPress', {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'rotation': rotation,
    'packageName': packageName,
    'durationMs': durationMs,
  });

  Future<Map<String, dynamic>?> queueDrag({
    required double x,
    required double y,
    required double endX,
    required double endY,
    required int width,
    required int height,
    required int rotation,
    required String packageName,
    required int holdMs,
    required int durationMs,
  }) => _channel.invokeMapMethod<String, dynamic>('queueDrag', {
    'x': x,
    'y': y,
    'endX': endX,
    'endY': endY,
    'width': width,
    'height': height,
    'rotation': rotation,
    'packageName': packageName,
    'holdMs': holdMs,
    'durationMs': durationMs,
  });

  Future<Map<String, dynamic>?> queueSwipe({
    required double x,
    required double y,
    required double endX,
    required double endY,
    required int width,
    required int height,
    required int rotation,
    required String packageName,
    required int durationMs,
  }) => _channel.invokeMapMethod<String, dynamic>('queueSwipe', {
    'x': x,
    'y': y,
    'endX': endX,
    'endY': endY,
    'width': width,
    'height': height,
    'rotation': rotation,
    'packageName': packageName,
    'durationMs': durationMs,
  });

  Future<Map<String, dynamic>?> queuePinch({
    required double x,
    required double y,
    required int width,
    required int height,
    required int rotation,
    required String packageName,
    required int durationMs,
    required double startSpan,
    required double scale,
    required String axis,
  }) => _channel.invokeMapMethod<String, dynamic>('queuePinch', {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'rotation': rotation,
    'packageName': packageName,
    'durationMs': durationMs,
    'startSpan': startSpan,
    'scale': scale,
    'axis': axis,
  });

  Future<void> cancelScreenActions() =>
      _channel.invokeMethod<void>('cancelScreenActions');

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

  Future<Map<String, dynamic>?> tapElementById({
    required String screenId,
    required String nodeId,
    required String targetPackage,
    String? runId,
  }) => _channel.invokeMapMethod<String, dynamic>('tapElementById', {
    'screenId': screenId,
    'nodeId': nodeId,
    'targetPackage': targetPackage,
    'runId': ?runId,
  });

  Future<Map<String, dynamic>?> tapElementByText(
    String text, {
    String? targetPackage,
  }) => _channel.invokeMapMethod<String, dynamic>('tapElementByText', {
    'text': text,
    'targetPackage': ?targetPackage,
  });

  Future<Map<String, dynamic>?> tapElementByTextWithGesture(
    String text, {
    String? targetPackage,
  }) => _channel.invokeMapMethod<String, dynamic>(
    'tapElementByTextWithGesture',
    {'text': text, 'targetPackage': ?targetPackage},
  );
}
