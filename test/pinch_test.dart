import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:mobile_pilot/features/device/presentation/widgets/pinch_controls_section.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/features/device/presentation/controllers/device_controller.dart';
import 'package:mobile_pilot/features/device/presentation/controllers/screen_capture_controller.dart';
import 'package:mobile_pilot/features/device/presentation/controllers/pinch_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.mobilepilot/settings');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  ScreenCaptureController capture(CommandFeedback f) =>
      ScreenCaptureController(f)
        ..packageName = 'target.app'
        ..width = 1280
        ..height = 2800
        ..rotation = 0
        ..selectedX = .5
        ..selectedY = .5;
  testWidgets(
    'Shrink preset updates visible values and sends the wide contraction',
    (tester) async {
      MethodCall? request;
      messenger.setMockMethodCallHandler(channel, (call) async {
        request = call;
        return {'message': 'queued'};
      });
      final f = CommandFeedback();
      final c = capture(f);
      final p = PinchController(f, c);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AnimatedBuilder(
                animation: p,
                builder: (_, _) =>
                    PinchControlsSection(controller: p, busy: f.isTapping),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('สองนิ้วขยาย/ย่อ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ตั้งค่าย่อมาก'));
      await tester.pumpAndSettle();
      final fields = find.byType(DropdownButtonFormField<double>);
      expect(
        tester
            .widget<DropdownButtonFormField<double>>(fields.at(0))
            .initialValue,
        .25,
      );
      expect(
        tester
            .widget<DropdownButtonFormField<double>>(fields.at(1))
            .initialValue,
        .8,
      );
      await p.queue();
      expect(request!.arguments['scale'], .25);
      expect(request!.arguments['startSpan'], .8);
      expect(request!.arguments['durationMs'], 1000);
      await tester.pumpWidget(const SizedBox.shrink());
      p.dispose();
      c.dispose();
    },
  );
  test(
    'Strong presets use wide meaningful finger travel in both directions',
    () {
      final f = CommandFeedback();
      final c = capture(f);
      final p = PinchController(f, c);
      addTearDown(p.dispose);
      addTearDown(c.dispose);
      p.strongExpand();
      expect(p.scale, 4);
      expect(p.startSpan, .2);
      expect(p.durationMs, 1000);
      p.strongShrink();
      expect(p.scale, .25);
      expect(p.startSpan, .8);
      expect(p.durationMs, 1000);
    },
  );
  test(
    'Pinch forwards center span scale axis duration and captured target',
    () async {
      MethodCall? request;
      messenger.setMockMethodCallHandler(channel, (call) async {
        request = call;
        return {'message': 'queued'};
      });
      final f = CommandFeedback()..targetPackage = 'target.app';
      final c = capture(f);
      final p = PinchController(f, c);
      addTearDown(p.dispose);
      addTearDown(c.dispose);
      p.setScale(.5);
      p.setSpan(.15);
      p.setAxis('vertical');
      p.setDuration(750);
      await p.queue();
      expect(request!.method, 'queuePinch');
      expect(request!.arguments, {
        'x': .5,
        'y': .5,
        'width': 1280,
        'height': 2800,
        'rotation': 0,
        'packageName': 'target.app',
        'durationMs': 750,
        'startSpan': .15,
        'scale': .5,
        'axis': 'vertical',
      });
    },
  );
  test(
    'Native out-of-bounds explanation is retained and busy state clears',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(
          code: 'INVALID_PINCH',
          message: 'choose center',
        ),
      );
      final f = CommandFeedback();
      final c = capture(f);
      final p = PinchController(f, c);
      addTearDown(p.dispose);
      addTearDown(c.dispose);
      await p.queue();
      expect(f.message, 'choose center');
      expect(f.isTapping, isFalse);
    },
  );
  test('Pinch blocks a screenshot from another selected target', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return null;
    });
    final f = CommandFeedback()..targetPackage = 'other.app';
    final c = capture(f);
    final p = PinchController(f, c);
    addTearDown(p.dispose);
    addTearDown(c.dispose);
    await p.queue();
    expect(calls, 0);
  });
  test('Pinch requires a center point', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return null;
    });
    final f = CommandFeedback();
    final c = capture(f)..selectedX = null;
    final p = PinchController(f, c);
    addTearDown(p.dispose);
    addTearDown(c.dispose);
    await p.queue();
    expect(calls, 0);
  });
  test('Choose center switches to red point without moving it', () {
    final f = CommandFeedback();
    final c = capture(f)..selectingSwipeEnd = true;
    final p = PinchController(f, c);
    addTearDown(p.dispose);
    addTearDown(c.dispose);
    p.chooseCenter();
    expect(c.selectingSwipeEnd, isFalse);
    expect(c.selectedX, .5);
  });
}
