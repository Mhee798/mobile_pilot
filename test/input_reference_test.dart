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
  test(
    'Editable reference sends exact ids then clears consumed list',
    () async {
      MethodCall? request;
      messenger.setMockMethodCallHandler(channel, (call) async {
        request = call;
        return {'message': 'accepted'};
      });
      final feedback = CommandFeedback()..targetPackage = 'target.app';
      final tree = UiTreeController(feedback);
      addTearDown(tree.dispose);
      final item = <String, dynamic>{
        'screenId': 'screen-1',
        'nodeId': 'node-2',
        'packageName': 'target.app',
        'editable': true,
        'visible': true,
        'enabled': true,
      };
      tree.elements = [item];
      tree.inputTextController.text = 'replacement';
      await tree.editReference(item, 'replace');
      expect(request!.method, 'editElementById');
      expect(request!.arguments['nodeId'], 'node-2');
      expect(request!.arguments['text'], 'replacement');
      expect(tree.elements, isEmpty);
      expect(tree.canEditReference({...item, 'password': true}), isFalse);
      feedback.targetPackage = 'other.app';
      expect(tree.canEditReference(item), isFalse);
    },
  );
}
