import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_pilot/core/platform/mobile_pilot_platform.dart';

// Serve fixtures/ on port 8768, adb reverse tcp:8768 tcp:8768, and open
// http://127.0.0.1:8768/index.html in Chrome before running on an unlocked device.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const platform = MobilePilotPlatform();
  const target = 'com.android.chrome';
  setUpAll(() async {
    runApp(const MaterialApp(home: Scaffold(body: Text('Device tool test'))));
    for (
      var i = 0;
      i < 120 && await platform.isAccessibilityServiceEnabled() != true;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    for (var i = 0; i < 20; i++) {
      try {
        await platform.getUiTree();
        break;
      } on PlatformException {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    await platform.launchApp(target);
    final fixture = await platform.getUiTree(targetPackage: target);
    expect(
      fixture.any((n) => n['text'] == 'MobilePilot tool fixture'),
      isTrue,
      reason: 'Unlock phone and open the local fixture before running',
    );
  });
  testWidgets('presence does not match a node below the viewport', (
    tester,
  ) async {
    final nodes = await platform.getUiTree(targetPackage: target);
    expect(nodes.any((node) => node['resourceId'] == 'offscreen-test'), isTrue);
    final result = await platform.waitForUi(
      requestId: 'offscreen-device',
      targetPackage: target,
      selector: 'resourceId',
      value: 'offscreen-test',
      timeoutMs: 1500,
    );
    expect(result?['code'], 'UI_TIMEOUT');
    debugPrint('DEVICE VERIFIED: Offscreen node did not satisfy visible wait');
  });
  testWidgets('double tap changes the real fixture', (tester) async {
    await platform.launchApp(target);
    final nodes = await platform.getUiTree(targetPackage: target);
    expect(
      nodes.any((n) => n['text'] == 'Ready'),
      isTrue,
      reason: 'Reload fixture before each run',
    );
    final node = nodes.firstWhere((n) => n['text'] == 'Double tap target');
    await platform.armScreenCapture(targetPackage: target);
    Map<dynamic, dynamic>? screen;
    for (var i = 0; i < 30 && screen == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      screen = await platform.getCapturedScreen();
    }
    expect(screen, isNotNull);
    final bounds = node['bounds'] as Map;
    await platform.queueDoubleTap(
      x:
          ((bounds['left'] as num) + (bounds['right'] as num)) /
          2 /
          (screen!['width'] as int),
      y:
          ((bounds['top'] as num) + (bounds['bottom'] as num)) /
          2 /
          (screen['height'] as int),
      width: screen['width'] as int,
      height: screen['height'] as int,
      rotation: screen['rotation'] as int,
      packageName: target,
    );
    final found = await platform.waitForUi(
      requestId: 'double-tap-device',
      targetPackage: target,
      selector: 'text',
      value: 'Double tap passed',
      timeoutMs: 10000,
    );
    expect(found?['code'], 'UI_FOUND');
    debugPrint('DEVICE VERIFIED: Double tap passed');
  });
  testWidgets('hold then drag reaches the real drop target', (tester) async {
    final nodes = await platform.getUiTree(targetPackage: target);
    final start =
        nodes.firstWhere((n) => n['text'] == 'Drag source')['bounds'] as Map;
    final end =
        nodes.firstWhere((n) => n['text'] == 'Drop target')['bounds'] as Map;
    await platform.armScreenCapture(targetPackage: target);
    Map<dynamic, dynamic>? screen;
    for (var i = 0; i < 30 && screen == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      screen = await platform.getCapturedScreen();
    }
    expect(screen, isNotNull);
    double x(Map b) =>
        ((b['left'] as num) + (b['right'] as num)) /
        2 /
        (screen!['width'] as int);
    double y(Map b) =>
        ((b['top'] as num) + (b['bottom'] as num)) /
        2 /
        (screen!['height'] as int);
    await platform.queueDrag(
      x: x(start),
      y: y(start),
      endX: x(end),
      endY: y(end),
      width: screen!['width'] as int,
      height: screen['height'] as int,
      rotation: screen['rotation'] as int,
      packageName: target,
      holdMs: 750,
      durationMs: 800,
    );
    final result = await platform.waitForUi(
      requestId: 'drag-device',
      targetPackage: target,
      selector: 'text',
      value: 'Drag passed',
      timeoutMs: 10000,
    );
    expect(result?['code'], 'UI_FOUND');
    debugPrint('DEVICE VERIFIED: Drag passed');
  });
  testWidgets('stopping during hold releases without dragging', (tester) async {
    final nodes = await platform.getUiTree(targetPackage: target);
    final start =
        nodes.firstWhere((n) => n['text'] == 'Drag source')['bounds'] as Map;
    final end =
        nodes.firstWhere((n) => n['text'] == 'Drop target')['bounds'] as Map;
    await platform.armScreenCapture(targetPackage: target);
    Map<dynamic, dynamic>? screen;
    for (var i = 0; i < 30 && screen == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      screen = await platform.getCapturedScreen();
    }
    expect(screen, isNotNull);
    double x(Map b) =>
        ((b['left'] as num) + (b['right'] as num)) /
        2 /
        (screen!['width'] as int);
    double y(Map b) =>
        ((b['top'] as num) + (b['bottom'] as num)) /
        2 /
        (screen!['height'] as int);
    await platform.queueDrag(
      x: x(start),
      y: y(start),
      endX: x(end),
      endY: y(end),
      width: screen!['width'] as int,
      height: screen['height'] as int,
      rotation: screen['rotation'] as int,
      packageName: target,
      holdMs: 2000,
      durationMs: 800,
    );
    final holding = await platform.waitForUi(
      requestId: 'drag-holding',
      targetPackage: target,
      selector: 'text',
      value: 'Drag holding',
      timeoutMs: 6000,
    );
    expect(holding?['code'], 'UI_FOUND');
    await platform.cancelScreenActions();
    final stopped = await platform.waitForUi(
      requestId: 'drag-stopped',
      targetPackage: target,
      selector: 'text',
      value: 'Drag stopped',
      timeoutMs: 6000,
    );
    expect(stopped?['code'], 'UI_FOUND');
    expect((await platform.getPointTapResult())?['code'], 'DRAG_CANCELLED');
    debugPrint('DEVICE VERIFIED: Stop during drag hold prevented movement');
  });
  testWidgets('select exact input then replace and clear real text', (
    tester,
  ) async {
    Future<Map<String, dynamic>> field() async {
      final nodes = await platform.getUiTree(targetPackage: target);
      return nodes.firstWhere(
        (n) =>
            n['editable'] == true &&
            (n['contentDescription'] == 'Input target' ||
                n['text'] == 'seed' ||
                n['text'] == 'MP_FIELD_TEST'),
      );
    }

    var node = await field();
    await platform.editElementById(
      screenId: node['screenId'] as String,
      nodeId: node['nodeId'] as String,
      targetPackage: target,
      action: 'focus',
    );
    await Future<void>.delayed(const Duration(seconds: 1));
    node = await field();
    await platform.editElementById(
      screenId: node['screenId'] as String,
      nodeId: node['nodeId'] as String,
      targetPackage: target,
      action: 'replace',
      text: 'MP_FIELD_TEST',
    );
    final changed = await platform.waitForUi(
      requestId: 'input-replace',
      targetPackage: target,
      selector: 'text',
      value: 'Field value MP_FIELD_TEST',
      timeoutMs: 5000,
    );
    expect(changed?['code'], 'UI_FOUND');
    node = await field();
    await platform.editElementById(
      screenId: node['screenId'] as String,
      nodeId: node['nodeId'] as String,
      targetPackage: target,
      action: 'clear',
    );
    final cleared = await platform.waitForUi(
      requestId: 'input-clear',
      targetPackage: target,
      selector: 'text',
      value: 'Field cleared',
      timeoutMs: 5000,
    );
    expect(cleared?['code'], 'UI_FOUND');
    debugPrint('DEVICE VERIFIED: Exact field focused, replaced and cleared');
  });
  testWidgets('keyboard search next and enter affect the real fields', (
    tester,
  ) async {
    Map<dynamic, dynamic>? screen;
    for (final mode in ['search', 'next', 'enter']) {
      final label = {
        'search': 'Search target',
        'next': 'Next target',
        'enter': 'Enter target',
      }[mode];
      final nodes = await platform.getUiTree(targetPackage: target);
      final field = nodes.firstWhere(
        (n) =>
            n['editable'] == true &&
            (n['contentDescription'] == label ||
                n['text'] ==
                    {
                      'search': 'SEARCH_SEED',
                      'next': 'NEXT_SEED',
                      'enter': 'ENTER_SEED',
                    }[mode]),
      );
      await platform.editElementById(
        screenId: field['screenId'] as String,
        nodeId: field['nodeId'] as String,
        targetPackage: target,
        action: 'focus',
      );
      await Future<void>.delayed(const Duration(seconds: 1));
      if (screen == null) {
        await platform.armScreenCapture(targetPackage: target);
        for (var i = 0; i < 60 && screen == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          screen = await platform.getCapturedScreen();
        }
      }
      expect(screen, isNotNull);
      await platform.queueScreenAction(
        action: 'keyboard',
        packageName: target,
        width: screen!['width'] as int,
        height: screen['height'] as int,
        rotation: screen['rotation'] as int,
        text: mode,
      );
      final text = {
        'search': 'Search passed',
        'next': 'Next passed',
        'enter': 'Enter passed',
      }[mode]!;
      var resultObserved = false;
      for (var attempt = 0; attempt < 20 && !resultObserved; attempt++) {
        final tree = await platform.getUiTree(targetPackage: target);
        resultObserved = tree.any((node) => node['text'] == text);
        if (!resultObserved) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      }
      expect(
        resultObserved,
        isTrue,
        reason: '$mode should change fixture text in UI tree',
      );
      debugPrint('DEVICE VERIFIED: $text');
    }
  });
  testWidgets('waits for enabled button then changed native text', (
    tester,
  ) async {
    await platform.armScreenCapture(targetPackage: target);
    Map<dynamic, dynamic>? screen;
    for (var i = 0; i < 30 && screen == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      screen = await platform.getCapturedScreen();
    }
    expect(screen, isNotNull);
    Future<void> utility(String action) async {
      await platform.queueScreenAction(
        action: action,
        packageName: target,
        width: screen!['width'] as int,
        height: screen['height'] as int,
        rotation: screen['rotation'] as int,
      );
      await Future<void>.delayed(const Duration(milliseconds: 2300));
    }

    await utility('back');
    for (var i = 0; i < 3; i++) {
      await utility('scroll_up');
    }
    final ready = platform.waitForUi(
      requestId: 'state-enabled',
      targetPackage: target,
      selector: 'text',
      value: 'Ready button',
      timeoutMs: 10000,
      condition: 'enabled',
    );
    final triggerNodes = await platform.getUiTree(targetPackage: target);
    final trigger =
        triggerNodes.firstWhere((n) => n['text'] == 'Start states')['bounds']
            as Map;
    await platform.queuePointTap(
      x:
          ((trigger['left'] as num) + (trigger['right'] as num)) /
          2 /
          (screen!['width'] as int),
      y:
          ((trigger['top'] as num) + (trigger['bottom'] as num)) /
          2 /
          (screen['height'] as int),
      width: screen['width'] as int,
      height: screen['height'] as int,
      rotation: screen['rotation'] as int,
      packageName: target,
    );
    expect((await ready)?['code'], 'UI_ENABLED');
    debugPrint('DEVICE VERIFIED: Button enabled without clicking');
    final nodes = await platform.getUiTree(targetPackage: target);
    final input = nodes.firstWhere((n) => n['resourceId'] == 'inputtarget');
    await platform.editElementById(
      screenId: input['screenId'] as String,
      nodeId: input['nodeId'] as String,
      targetPackage: target,
      action: 'focus',
    );
    await Future<void>.delayed(const Duration(seconds: 1));
    final changed = platform.waitForUi(
      requestId: 'state-text',
      targetPackage: target,
      selector: 'resourceId',
      value: 'inputtarget',
      timeoutMs: 10000,
      condition: 'textChanged',
    );
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final editing = await platform.getUiTree(targetPackage: target);
    final field = editing.firstWhere(
      (n) => n['resourceId'] == 'inputtarget' && n['editable'] == true,
    );
    await platform.editElementById(
      screenId: field['screenId'] as String,
      nodeId: field['nodeId'] as String,
      targetPackage: target,
      action: 'replace',
      text: 'MP_STATE_CHANGED',
    );
    expect((await changed)?['code'], 'UI_TEXT_CHANGED');
    debugPrint('DEVICE VERIFIED: Exact fixture field text changed');
    await utility('back');
  });
  // The device-specific Settings labels are only valid for the Thai HONOR fixture.
  const runThaiSettingsTest = bool.fromEnvironment(
    'MOBILEPILOT_THAI_SETTINGS_TEST',
  );
  testWidgets('real Settings: scroll to About phone and verify page', (
    tester,
  ) async {
    const settings = 'com.android.settings';
    await platform.launchApp(settings);
    final found = await platform.scrollUntilUi(
      requestId: 'settings-about-scroll',
      targetPackage: settings,
      selector: 'text',
      value: 'เกี่ยวกับโทรศัพท์',
      timeoutMs: 30000,
      direction: 'down',
      maxScrolls: 20,
      distance: 'long',
    );
    expect(
      found?['code'],
      'UI_FOUND',
      reason: 'Scroll to About phone in Thai Settings',
    );
    debugPrint(
      'DEVICE VERIFIED: Settings About found after ${found?['scrollCount']} scrolls',
    );
    final action = await platform.tapElementByText(
      'เกี่ยวกับโทรศัพท์',
      targetPackage: settings,
    );
    expect(action?['code'], 'ACTION_DISPATCHED');
    final page = await platform.waitForUi(
      requestId: 'settings-about-page',
      targetPackage: settings,
      selector: 'text',
      value: 'ชื่ออุปกรณ์',
      timeoutMs: 10000,
    );
    expect(
      page?['code'],
      'UI_FOUND',
      reason: 'Verify the About phone screen appeared',
    );
    debugPrint('DEVICE VERIFIED: Settings About page opened');
  }, skip: !runThaiSettingsTest);
}
