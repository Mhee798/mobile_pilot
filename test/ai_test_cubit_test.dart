import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_pilot/features/ai/data/ai_model_service.dart';
import 'package:mobile_pilot/core/platform/ai_task_overlay.dart';
import 'package:mobile_pilot/features/ai/presentation/cubit/ai_test_cubit.dart';
import 'package:mobile_pilot/features/ai/data/ai_device_tools.dart';
import 'package:mobile_pilot/features/ai/presentation/screen/ai_test_page.dart';

class FakeTaskOverlay extends AiTaskOverlay {
  Future<void> Function()? stop;
  final updates = <({String status, bool running})>[];
  bool disposed = false;
  @override
  void listen(Future<void> Function() callback) => stop = callback;
  @override
  Future<void> publish({required String status, required bool running}) async {
    updates.add((status: status, running: running));
  }

  @override
  void dispose() => disposed = true;
}

class FakeDeviceTools extends AiDeviceTools {
  Completer<void>? openGate;
  final opened = <String>[];
  String result = 'opened';
  String? testTarget;
  int readTargetOpens = 0;
  @override
  String? get targetPackage => testTarget;
  @override
  Future<void> openTargetForReading() async {
    readTargetOpens++;
  }

  @override
  Future<Map<String, dynamic>> openSelected(String packageName) async {
    await openGate?.future;
    opened.add(packageName);
    return {'status': result};
  }
}

class FakeAiService extends AiModelService {
  FakeAiService({super.deviceTools});
  bool ready = false;
  int resetCount = 0;
  Uint8List? receivedImage;
  bool returnApps = false;
  bool returnChoices = false;
  bool failGeneration = false;
  final prompts = <String>[];
  Map<String, dynamic>? reportedToolResult;
  Completer<void>? readGate;
  Completer<void>? generationGate;
  String? choiceResult;
  @override
  bool get isReady => ready;
  @override
  bool get supportsImages => ready;
  @override
  Future<bool> hasSavedModel() async => true;
  @override
  Future<void> loadSaved() async => ready = true;
  @override
  Future<void> generate(
    String text,
    void Function(String) onToken, {
    Uint8List? image,
    void Function(String)? onToolCall,
    void Function(String, Map<String, dynamic>)? onToolResult,
  }) async {
    prompts.add(text);
    receivedImage = image;
    if (failGeneration) throw StateError('test generation failure');
    if (reportedToolResult != null) {
      onToolCall?.call('open_app');
      onToolResult?.call('open_app', reportedToolResult!);
    }
    if (generationGate != null) {
      await generationGate!.future;
      throw StateError('cancelled');
    }
    if (readGate != null) {
      onToolCall?.call('read_current_ui');
      await readGate!.future;
      onToolResult?.call('read_current_ui', {'status': 'ok', 'total': 3});
    }
    onToken('สวัสดี');
    if (returnApps && prompts.length == 1) {
      onToolResult?.call('find_apps', {
        'apps': [
          {'label': 'Shopee', 'packageName': 'example.shopee'},
        ],
      });
    }
    if (returnChoices && prompts.length == 1) {
      onToolResult?.call('open_app', {
        'status': 'ambiguous',
        'apps': [
          {'label': 'Shop A', 'packageName': 'shop.a'},
          {'label': 'Shop B', 'packageName': 'shop.b'},
        ],
      });
    }
    onToken('ครับ');
  }

  @override
  Future<void> close() async {}
  @override
  Future<void> stopGeneration() async => generationGate?.complete();
  @override
  void recordChoiceResult(String result) {
    choiceResult = result;
  }

  @override
  Future<void> resetChat() async {
    resetCount++;
  }
}

void main() {
  testWidgets('debug Thai input fills the field but never sends a request', (
    tester,
  ) async {
    final service = FakeAiService();
    await tester.pumpWidget(MaterialApp(home: AiTestPage(service: service)));
    await tester.pumpAndSettle();
    final reply = Completer<void>();
    // ignore: deprecated_member_use
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'com.mobilepilot/debug_input',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('fillPrompt', 'เปิดแอปตั้งค่าแล้วอ่านหน้าจอ'),
      ),
      (_) => reply.complete(),
    );
    await reply.future;
    await tester.pump();
    expect(find.text('เปิดแอปตั้งค่าแล้วอ่านหน้าจอ'), findsOneWidget);
    expect(service.prompts, isEmpty);
  });
  test('Stop while opening a chosen app prevents resuming the task', () async {
    final tools = FakeDeviceTools();
    final service = FakeAiService(deviceTools: tools)..returnChoices = true;
    final controller = AiTestCubit(service);
    addTearDown(controller.close);
    await controller.loadSaved();
    await controller.send('เปิด Shop แล้วอ่านหน้าจอ');
    tools.openGate = Completer<void>();
    final choice = controller.chooseApp(
      controller.state.pendingChoiceIndex!,
      'shop.a',
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.generating, isTrue);
    await controller.stopGeneration();
    tools.openGate!.complete();
    await choice;
    expect(service.prompts.length, 1);
    expect(controller.state.generating, isFalse);
  });
  test('fallback lists repeated tool outcomes only once', () {
    final result = <String, dynamic>{
      'status': 'ok',
      'total': 47,
      'next_offset': 10,
      'elements': [
        {'text': 'Wi-Fi'},
      ],
    };
    final text = describeEmptyResponse([
      (name: 'read_current_ui', result: result),
      (name: 'read_current_ui', result: result),
    ], stalledReason: 'ui_action: invalid reference');
    expect('Wi-Fi'.allMatches(text).length, 1);
    expect('47 รายการ'.allMatches(text).length, 1);
    expect(text, contains('หยุดเพราะเครื่องมือผิดพลาดซ้ำ'));
    expect(text, isNot(contains('ถึงขีดจำกัดรอบ')));
  });
  test('choosing an app resumes the original task exactly once', () async {
    final tools = FakeDeviceTools();
    final service = FakeAiService(deviceTools: tools)..returnChoices = true;
    final controller = AiTestCubit(service);
    addTearDown(controller.close);
    await controller.loadSaved();
    const request = 'เปิด Shop แล้วอ่านรายการในหน้าจอ';
    await controller.send(request);
    final choiceIndex = controller.state.pendingChoiceIndex!;
    await controller.chooseApp(choiceIndex, 'shop.b');
    expect(tools.opened, ['shop.b']);
    expect(service.prompts.length, 2);
    expect(service.prompts.last, contains(request));
    expect(service.prompts.last, contains('shop.b'));
    expect(service.prompts.last, contains('ไม่ต้องค้นหาหรือเปิดแอปซ้ำ'));
    expect(controller.state.messages.where((m) => m.isUser).length, 2);
    expect(controller.state.messages.last.text, 'สวัสดีครับ');
    await controller.chooseApp(choiceIndex, 'shop.b');
    expect(service.prompts.length, 2);
  });

  test('unconfirmed app selection does not resume the task', () async {
    final tools = FakeDeviceTools()..result = 'unconfirmed';
    final service = FakeAiService(deviceTools: tools)..returnChoices = true;
    final controller = AiTestCubit(service);
    addTearDown(controller.close);
    await controller.loadSaved();
    await controller.send('เปิด Shop แล้วอ่านหน้าจอ');
    await controller.chooseApp(controller.state.pendingChoiceIndex!, 'shop.a');
    expect(service.prompts.length, 1);
    expect(controller.state.status, contains('ยังยืนยัน'));
  });
  test('actual tool errors retain their tool name, code and cause', () async {
    final service = FakeAiService()
      ..reportedToolResult = {
        'error': 'Enable Accessibility first',
        'code': 'SERVICE_UNAVAILABLE',
      };
    final controller = AiTestCubit(service);
    addTearDown(controller.close);
    await controller.loadSaved();
    await controller.send('เปิดตั้งค่า');
    expect(controller.state.toolsUsed, ['open_app']);
    expect(controller.state.toolResults.single, contains('open_app'));
    expect(
      controller.state.toolResults.single,
      contains('SERVICE_UNAVAILABLE'),
    );
    expect(
      controller.state.toolResults.single,
      contains('Enable Accessibility first'),
    );
    expect(controller.state.busy, isFalse);
  });
  test(
    'generation failure appears in the conversation and allows retry',
    () async {
      final service = FakeAiService()..failGeneration = true;
      final controller = AiTestCubit(service);
      addTearDown(controller.close);
      await controller.loadSaved();
      await controller.send('อ่านตั้งค่า');
      expect(
        controller.state.messages.last.text,
        contains('สร้างคำตอบไม่สำเร็จ'),
      );
      expect(controller.state.answer, isNotEmpty);
      expect(controller.state.busy, isFalse);
      service.failGeneration = false;
      await controller.send('สวัสดี');
      expect(controller.state.messages.last.text, 'สวัสดีครับ');
    },
  );

  test(
    'tool limit reports observed screen labels and incomplete pagination',
    () {
      final text = describeEmptyResponse([
        (
          name: 'read_current_ui',
          result: <String, dynamic>{
            'status': 'ok',
            'total': 47,
            'next_offset': 10,
            'elements': [
              {'text': 'Wi-Fi'},
              {'text': '', 'contentDescription': 'บลูทูธ'},
              {'text': 'Wi-Fi'},
            ],
          },
        ),
      ], toolLimitReached: true);
      expect(text, contains('ถึงขีดจำกัดรอบเครื่องมือ'));
      expect(text, contains('- Wi-Fi'));
      expect(text, contains('- บลูทูธ'));
      expect('- Wi-Fi'.allMatches(text).length, 1);
      expect(text, contains('ยังมีรายการในหน้าถัดไป'));
      expect(text, contains('โมเดลจะไม่จำบริบทเดิม'));
    },
  );
  test(
    'floating stop cancels generation and publishes confirmed completion',
    () async {
      final overlay = FakeTaskOverlay();
      final service = FakeAiService()..generationGate = Completer<void>();
      final controller = AiTestCubit(service, overlay: overlay);
      await controller.loadSaved();
      final task = controller.send('เล่าเรื่อง');
      await Future<void>.delayed(Duration.zero);
      expect(overlay.updates.last.running, isTrue);
      await overlay.stop!();
      await task;
      await Future<void>.delayed(Duration.zero);
      expect(overlay.updates.last.running, isFalse);
      expect(overlay.updates.last.status, contains('หยุดการสร้างคำตอบแล้ว'));
      await controller.close();
      expect(overlay.disposed, isTrue);
    },
  );
  test(
    'closing task owner stops generation before releasing the model',
    () async {
      final service = FakeAiService()..generationGate = Completer<void>();
      final controller = AiTestCubit(service);
      await controller.loadSaved();
      final task = controller.send('สวัสดี');
      expect(controller.state.generating, isTrue);
      await controller.close();
      await task;
      expect(service.generationGate!.isCompleted, isTrue);
      expect(controller.isClosed, isTrue);
    },
  );
  testWidgets('app-owned task survives removing and reopening chat', (
    tester,
  ) async {
    final service = FakeAiService()..readGate = Completer<void>();
    final controller = AiTestCubit(service);
    addTearDown(controller.close);
    await controller.loadSaved();
    service.toolsEnabled = true;
    final task = controller.send('อ่านหน้าจอ');
    await tester.pumpWidget(
      BlocProvider<AiTestCubit>.value(
        value: controller,
        child: const MaterialApp(home: AiTestPage()),
      ),
    );
    await tester.pump();
    expect(controller.state.busy, isTrue);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(controller.isClosed, isFalse);
    expect(controller.state.busy, isTrue);
    service.readGate!.complete();
    await task;
    await tester.pumpWidget(
      BlocProvider<AiTestCubit>.value(
        value: controller,
        child: const MaterialApp(home: AiTestPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.state.ready, isTrue);
    expect(controller.state.busy, isFalse);
    expect(controller.state.messages.last.text, 'สวัสดีครับ');
    expect(find.text('สวัสดีครับ'), findsWidgets);
    expect(service.toolsEnabled, isTrue);
  });
  test(
    'empty model reply reports the verified tool result and lost context',
    () {
      final text = describeEmptyResponse([
        (
          name: 'open_app',
          result: <String, dynamic>{
            'status': 'opened',
            'app': {'label': 'ตั้งค่า'},
          },
        ),
      ]);
      expect(text, contains('เปิด ตั้งค่า แล้ว'));
      expect(text, contains('โมเดลจะไม่จำบริบทเดิม'));
      final failure = describeEmptyResponse([
        (name: 'open_app', result: <String, dynamic>{'status': 'unconfirmed'}),
      ]);
      expect(failure, isNot(contains('ยืนยันว่าอยู่ด้านหน้า')));
    },
  );
  test('stops a pending reply and enables another message', () async {
    final service = FakeAiService()..generationGate = Completer<void>();
    final cubit = AiTestCubit(service);
    addTearDown(cubit.close);
    await cubit.loadSaved();
    final pending = cubit.send('ทดสอบ');
    expect(cubit.state.generating, isTrue);
    await cubit.stopGeneration();
    await pending;
    expect(cubit.state.busy, isFalse);
    expect(cubit.state.status, contains('หยุดการสร้างคำตอบ'));
    service.generationGate = null;
    await cubit.send('ลองใหม่');
    expect(cubit.state.answer, 'สวัสดีครับ');
  });
  test('loads a saved model and streams the reply into state', () async {
    final cubit = AiTestCubit(FakeAiService());
    addTearDown(cubit.close);
    await cubit.loadSaved();
    expect(cubit.state.ready, isTrue);
    await cubit.send('ทดสอบ');
    expect(cubit.state.answer, 'สวัสดีครับ');
    expect(cubit.state.busy, isFalse);
    await cubit.send('คำถามต่อ');
    expect(cubit.state.messages.map((message) => message.text), [
      'ทดสอบ',
      'สวัสดีครับ',
      'คำถามต่อ',
      'สวัสดีครับ',
    ]);
    await cubit.resetChat();
    expect(cubit.state.messages, isEmpty);
    expect(cubit.state.ready, isTrue);
    expect(
      cubit.service is FakeAiService &&
          (cubit.service as FakeAiService).resetCount == 1,
      isTrue,
    );
  });

  test('rejects invalid model links before starting a download', () async {
    final cubit = AiTestCubit(FakeAiService());
    addTearDown(cubit.close);
    await cubit.download('http://example.com/model.litertlm', ModelType.gemma4);
    expect(cubit.state.busy, isFalse);
    expect(cubit.state.status, contains('HTTPS'));
  });

  test('keeps app results on the reply while more text streams', () async {
    final service = FakeAiService()..returnApps = true;
    final cubit = AiTestCubit(service);
    addTearDown(cubit.close);
    await cubit.loadSaved();
    await cubit.send('หาแอป');
    expect(cubit.state.messages.last.text, 'สวัสดีครับ');
    expect(cubit.state.messages.last.apps, [
      {'label': 'Shopee', 'packageName': 'example.shopee'},
    ]);
  });

  test(
    'search results can be opened only after the user selects an app',
    () async {
      final tools = FakeDeviceTools();
      final service = FakeAiService(deviceTools: tools)..returnApps = true;
      final cubit = AiTestCubit(service);
      addTearDown(cubit.close);
      await cubit.loadSaved();
      await cubit.send('หา Shopee');
      final index = cubit.state.pendingChoiceIndex!;
      expect(tools.opened, isEmpty);
      await cubit.chooseApp(index, 'example.shopee');
      expect(tools.opened, ['example.shopee']);
      expect(cubit.state.pendingChoiceIndex, isNull);
    },
  );

  test('only the current ambiguous choices can be selected once', () async {
    final tools = FakeDeviceTools();
    final service = FakeAiService(deviceTools: tools)..returnChoices = true;
    final cubit = AiTestCubit(service);
    addTearDown(cubit.close);
    await cubit.loadSaved();
    await cubit.send('เปิด Shop');
    final index = cubit.state.pendingChoiceIndex!;
    await cubit.chooseApp(index, 'unknown.app');
    expect(tools.opened, isEmpty);
    await cubit.chooseApp(index, 'shop.b');
    expect(tools.opened, ['shop.b']);
    expect(cubit.state.pendingChoiceIndex, isNull);
    expect(service.choiceResult, contains('ยืนยันว่าอยู่ด้านหน้า'));
    expect(cubit.state.status, 'ตอบเสร็จแล้ว');
    await cubit.chooseApp(index, 'shop.a');
    expect(tools.opened, ['shop.b']);
  });

  test('cancelled choices cannot open an app', () async {
    final tools = FakeDeviceTools();
    final service = FakeAiService(deviceTools: tools)..returnChoices = true;
    final cubit = AiTestCubit(service);
    addTearDown(cubit.close);
    await cubit.loadSaved();
    await cubit.send('เปิด Shop');
    final index = cubit.state.pendingChoiceIndex!;
    cubit.cancelChoice(index);
    await cubit.chooseApp(index, 'shop.a');
    expect(tools.opened, isEmpty);
    expect(service.choiceResult, 'ยกเลิกการเลือกแอปแล้ว');
  });

  test('offers opening the target while the live UI read is waiting', () async {
    final tools = FakeDeviceTools()..testTarget = 'example.target';
    final gate = Completer<void>();
    final service = FakeAiService(deviceTools: tools)..readGate = gate;
    final cubit = AiTestCubit(service);
    addTearDown(cubit.close);
    await cubit.loadSaved();
    final operation = cubit.send('อ่านหน้าจอ');
    expect(cubit.state.waitingForUi, isTrue);
    await cubit.openReadTarget();
    expect(tools.readTargetOpens, 1);
    gate.complete();
    await operation;
    expect(cubit.state.waitingForUi, isFalse);
    expect(cubit.state.toolResults.single, contains('3 รายการ'));
  });

  testWidgets('shows tappable app choices from a search result', (
    tester,
  ) async {
    final tools = FakeDeviceTools();
    final service = FakeAiService(deviceTools: tools)..returnApps = true;
    await tester.pumpWidget(MaterialApp(home: AiTestPage(service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('จัดการโมเดล'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ใช้โมเดลที่บันทึกไว้'));
    await tester.tap(find.text('ใช้โมเดลที่บันทึกไว้'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('จัดการโมเดล'));
    await tester.tap(find.text('จัดการโมเดล'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'หา Shopee');
    await tester.tap(find.byTooltip('ส่งข้อความ'));
    await tester.pumpAndSettle();
    expect(find.text('แตะรายการเพื่อเปิดแอป'), findsOneWidget);
    await tester.tap(find.text('Shopee'));
    await tester.pumpAndSettle();
    expect(tools.opened, ['example.shopee']);
    expect(find.textContaining('ยืนยันว่าอยู่ด้านหน้า'), findsWidgets);
  });

  test('does not claim success when selected app cannot be verified', () async {
    final tools = FakeDeviceTools()..result = 'unconfirmed';
    final service = FakeAiService(deviceTools: tools)..returnChoices = true;
    final cubit = AiTestCubit(service);
    addTearDown(cubit.close);
    await cubit.loadSaved();
    await cubit.send('เปิด Shop');
    await cubit.chooseApp(cubit.state.pendingChoiceIndex!, 'shop.a');
    expect(cubit.state.status, contains('ยังยืนยัน'));
  });

  test(
    'passes an attached image to the model and retains it in the chat',
    () async {
      final service = FakeAiService();
      final cubit = AiTestCubit(service);
      addTearDown(cubit.close);
      await cubit.loadSaved();
      final image = Uint8List.fromList([1, 2, 3]);
      await cubit.send('ภาพนี้คืออะไร', image: image);
      expect(service.receivedImage, image);
      expect(cubit.state.messages.first.image, image);
    },
  );
}
