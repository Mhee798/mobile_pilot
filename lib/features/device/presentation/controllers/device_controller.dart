import 'package:flutter/foundation.dart';

import '../../../../core/platform/mobile_pilot_platform.dart';

// These two values are shared by commands from different sections of the page.
// Updates notify the command's controller; the page listens to all controllers.
class CommandFeedback {
  String? message;
  String? targetPackage;
  bool isTapping = false;
}

abstract class DeviceController extends ChangeNotifier {
  DeviceController(this.feedback);

  final CommandFeedback feedback;
  final platform = const MobilePilotPlatform();
  bool _isDisposed = false;
  // Controllers live for the owning page's lifetime, including async callbacks.
  bool get mounted => !_isDisposed;

  void update(VoidCallback change) {
    change();
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
