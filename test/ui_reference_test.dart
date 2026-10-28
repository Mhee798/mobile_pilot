import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/features/device/presentation/controllers/device_controller.dart';
import 'package:mobile_pilot/features/device/presentation/controllers/ui_tree_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.mobilepilot/settings');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  Map<String, dynamic> item() => {
    'screenId': 'screen-1',
    'nodeId': 'node-0.1',
    'packageName': 'target.app',
    'clickable': true,
    'visible': true,
    'enabled': true,
  };
  test('Reference tap passes exact IDs and consumes displayed list', () async {
    MethodCall? request;
    messenger.setMockMethodCallHandler(channel, (call) async {
      request = call;
      return {'message': 'accepted'};
    });
    final tree = UiTreeController(
      CommandFeedback()..targetPackage = 'target.app',
    );
    addTearDown(tree.dispose);
    tree.elements = [item()];
    await tree.tapReference(tree.elements.first);
    expect(request!.method, 'tapElementById');
    expect(request!.arguments, {
      'screenId': 'screen-1',
      'nodeId': 'node-0.1',
      'targetPackage': 'target.app',
    });
    expect(tree.elements, isEmpty);
  });
  test(
    'Stale screen response clears references and explains fresh read',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(
          code: 'STALE_SCREEN',
          message: 'read again',
        ),
      );
      final feedback = CommandFeedback()..targetPackage = 'target.app';
      final tree = UiTreeController(feedback);
      addTearDown(tree.dispose);
      tree.elements = [item()];
      await tree.tapReference(tree.elements.first);
      expect(tree.elements, isEmpty);
      expect(feedback.message, 'read again');
      expect(feedback.isTapping, isFalse);
    },
  );
  test(
    'Wrong target or nonactionable entries cannot issue a reference tap',
    () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (_) async {
        calls++;
        return null;
      });
      final tree = UiTreeController(
        CommandFeedback()..targetPackage = 'other.app',
      );
      addTearDown(tree.dispose);
      await tree.tapReference(item());
      expect(calls, 0);
      expect(tree.canTapReference(item()..['visible'] = false), isFalse);
    },
  );
}
