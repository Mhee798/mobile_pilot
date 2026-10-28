import 'package:flutter/services.dart';

/// Dedicated channel so overlay callbacks do not replace device-tool handlers.
class AiTaskOverlay {
  static const _channel = MethodChannel('com.mobilepilot/ai_task');

  void listen(Future<void> Function() stop) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'stopAiTask') throw MissingPluginException();
      await stop();
    });
  }

  Future<void> publish({required String status, required bool running}) async {
    try {
      await _channel.invokeMethod<void>('setAiTaskStatus', {
        'status': status,
        'running': running,
      });
    } on MissingPluginException {
      // Non-Android builds and tests have no accessibility overlay.
    } on PlatformException {
      // An unavailable overlay must not interrupt the AI task.
    }
  }

  void dispose() => _channel.setMethodCallHandler(null);
}
