import 'dart:typed_data';

import '../../../../core/platform/mobile_pilot_platform.dart';

/// Keeps icon requests scoped to the chat page that displays them.
class AppIconCache {
  final _icons = <String, Future<Uint8List?>>{};

  Future<Uint8List?> get(String packageName) =>
      _icons.putIfAbsent(packageName, () async {
        try {
          return await const MobilePilotPlatform().getAppIcon(packageName);
        } catch (_) {
          return null;
        }
      });
}
