import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/features/device/presentation/screen/command_page.dart';
import 'package:mobile_pilot/features/device/presentation/widgets/screen_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.mobilepilot/settings');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets(
    'Captured point is queued and text taps share busy state with preview',
    (tester) async {
      final calls = <MethodCall>[];
      final tapResult = Completer<Map<String, dynamic>>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'getFloatingControlsEnabled':
            return false;
          case 'armScreenCapture':
            return {'code': 'CAPTURE_ARMED'};
          case 'getCapturedScreen':
            return {
              'jpeg': base64Decode(
                'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jMioAAAAASUVORK5CYII=',
              ),
              'width': 1280,
              'height': 2800,
              'rotation': 0,
              'packageName': 'com.android.settings',
            };
          case 'queuePointTap':
            return {'code': 'TAP_QUEUED', 'message': 'point queued'};
          case 'tapElementByText':
            return tapResult.future;
          case 'getUiTree':
            return [
              {'text': 'Target', 'clickable': true},
            ];
          default:
            return null;
        }
      });

      await tester.pumpWidget(const MaterialApp(home: CommandPage()));
      await tester.pumpAndSettle();
      final capture = find.text('จับภาพแอปอื่นเพื่อเลือกพิกัด');
      await tester.ensureVisible(capture);
      await tester.tap(capture);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      final preview = find.byType(ScreenPreview);
      await tester.ensureVisible(preview);
      await tester.pumpAndSettle();
      final imageFrame = find
          .descendant(of: preview, matching: find.byType(GestureDetector))
          .first;
      await tester.tapAt(tester.getRect(imageFrame).center);
      await tester.pump();
      final queuePoint = find.text('เตรียมแตะพิกัดนี้');
      await tester.ensureVisible(queuePoint);
      await tester.tap(queuePoint);
      await tester.pump();
      final request = calls.singleWhere(
        (call) => call.method == 'queuePointTap',
      );
      expect(request.arguments['x'], closeTo(0.5, 0.000001));
      expect(request.arguments['y'], closeTo(0.5, 0.000001));
      expect(request.arguments['packageName'], 'com.android.settings');
      expect(request.arguments['width'], 1280);
      expect(request.arguments['height'], 2800);

      final target = find.byType(TextField).first;
      await tester.ensureVisible(target);
      await tester.enterText(target, 'Target');
      final textTap = find.text('แตะ element ตามข้อความ');
      await tester.ensureVisible(textTap);
      await tester.tap(textTap);
      await tester.pump();
      final previewButton = find.widgetWithText(
        OutlinedButton,
        'เตรียมแตะพิกัดนี้',
      );
      expect(tester.widget<OutlinedButton>(previewButton).onPressed, isNull);
      tapResult.complete({'message': 'tap accepted'});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(tester.widget<OutlinedButton>(previewButton).onPressed, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Leaving command page stops scheduled capture polling', (
    tester,
  ) async {
    var captureReads = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getFloatingControlsEnabled':
          return false;
        case 'armScreenCapture':
          return {'code': 'CAPTURE_ARMED'};
        case 'getCapturedScreen':
          captureReads++;
          return null;
        default:
          return null;
      }
    });
    await tester.pumpWidget(const MaterialApp(home: CommandPage()));
    await tester.pumpAndSettle();
    final capture = find.text('จับภาพแอปอื่นเพื่อเลือกพิกัด');
    await tester.ensureVisible(capture);
    await tester.tap(capture);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(captureReads, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(captureReads, 1);
    expect(tester.takeException(), isNull);
  });
}
