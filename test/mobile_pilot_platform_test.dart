import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/core/platform/mobile_pilot_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.mobilepilot/settings');
  const platform = MobilePilotPlatform();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'UI tree retains entries, filters non-maps and treats null as empty',
    () async {
      Object? response = [
        {
          'text': 'Settings',
          'clickable': true,
          'bounds': {'left': 10},
        },
        'not a node',
      ];
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'getUiTree');
        expect(call.arguments, isNull);
        return response;
      });
      expect(await platform.getUiTree(), [
        {
          'text': 'Settings',
          'clickable': true,
          'bounds': {'left': 10},
        },
      ]);
      response = null;
      expect(await platform.getUiTree(), isEmpty);
    },
  );

  test(
    'Screenshot retrieval is called once and null remains pending',
    () async {
      var reads = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'getCapturedScreen');
        reads++;
        return null;
      });
      expect(await platform.getCapturedScreen(), isNull);
      expect(reads, 1);
    },
  );

  test(
    'Queued point and text actions preserve the native argument contracts',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return {'code': 'QUEUED', 'message': 'waiting'};
      });
      await platform.queuePointTap(
        x: 0.25,
        y: 0.75,
        width: 1280,
        height: 2800,
        rotation: 0,
        packageName: 'com.android.settings',
      );
      await platform.queueScreenAction(
        action: 'type_text',
        packageName: 'com.android.chrome',
        width: 1280,
        height: 2800,
        rotation: 0,
        text: 'MP_SAFE_TEST',
      );
      expect(calls[0].method, 'queuePointTap');
      expect(calls[0].arguments, {
        'x': 0.25,
        'y': 0.75,
        'width': 1280,
        'height': 2800,
        'rotation': 0,
        'packageName': 'com.android.settings',
      });
      expect(calls[1].method, 'queueScreenAction');
      expect(calls[1].arguments, {
        'action': 'type_text',
        'packageName': 'com.android.chrome',
        'width': 1280,
        'height': 2800,
        'rotation': 0,
        'text': 'MP_SAFE_TEST',
      });
    },
  );

  test('Native errors retain their code, message and details', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(
        code: 'ACTION_IN_PROGRESS',
        message: 'Wait',
        details: 42,
      );
    });
    await expectLater(
      platform.tapElementByText('Battery'),
      throwsA(
        isA<PlatformException>()
            .having((e) => e.code, 'code', 'ACTION_IN_PROGRESS')
            .having((e) => e.message, 'message', 'Wait')
            .having((e) => e.details, 'details', 42),
      ),
    );
  });
}
