import 'package:mobile_pilot/features/home/presentation/screen/conversation_search_page.dart';

import 'helpers/memory_chat_box.dart';

import 'package:mobile_pilot/features/home/presentation/widgets/home_menu_panel.dart';

import 'package:mobile_pilot/features/home/application/home_chat_session.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/features/ai/application/ai_task_controller.dart';
import 'package:mobile_pilot/features/ai/application/ai_task_phase.dart';
import 'package:mobile_pilot/features/ai/application/gemini_chat_controller.dart';
import 'package:mobile_pilot/features/ai/data/ai_model_service.dart';
import 'package:mobile_pilot/features/home/presentation/screen/mobile_pilot_home_page.dart';
import 'package:mobile_pilot/features/home/presentation/widgets/chat_execution_card.dart';
import 'package:mobile_pilot/features/home/presentation/widgets/chat_message_bubble.dart';
import 'package:mobile_pilot/features/models/application/model_selection_controller.dart';
import 'package:mobile_pilot/features/models/domain/model_entry.dart';
import 'package:mobile_pilot/features/models/presentation/model_selection_scope.dart';

import 'helpers/fake_model_backend.dart';
import 'helpers/localized_test_app.dart';

class ChatService extends AiModelService {
  ChatService({super.history});
  Completer<void>? gate;
  bool stopped = false, fail = false;
  String? lastInput;
  Map<String, dynamic>? toolResult;
  @override
  bool get isReady => true;
  @override
  Future<bool> hasSavedModel() async => false;
  @override
  Future<void> resetChat() async {}
  @override
  Future<void> close() async {}
  @override
  Future<void> stopGeneration() async {
    stopped = true;
  }

  @override
  Future<void> generate(
    String text,
    void Function(String) onToken, {
    Uint8List? image,
    void Function(String)? onToolCall,
    void Function(String, Map<String, dynamic>)? onToolResult,
  }) async {
    if (toolResult != null) onToolResult?.call('read_current_ui', toolResult!);
    lastInput = text;
    onToken('คำตอบ');
    if (fail) throw StateError('offline');
    await gate?.future;
    if (stopped) throw StateError('stopped');
    onToken('เสร็จแล้ว');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ChatService service;
  late HomeChatSession session;
  late AiTaskController task;
  late ModelSelectionController models;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() async {
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      (_) async => 1,
    );
    session = HomeChatSession(openStore: () async => MemoryChatBox());
    await session.initialize();
    service = ChatService();
    task = AiTaskController(service);
    models = ModelSelectionController(FakeModelBackend());
    await models.initialize();
    await task.changeModel(() async {});
  });
  tearDown(() async {
    models.dispose();
    session.dispose();
    await task.close();
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      null,
    );
  });
  Future<void> show(WidgetTester tester, {GeminiReply? reply}) async {
    await tester.pumpWidget(
      BlocProvider.value(
        value: task,
        child: ModelSelectionScope(
          controller: models,
          child: LocalizedTestApp(
            home: MobilePilotHomePage(cloudReply: reply, session: session),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> send(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
  }

  test(
    'late cloud completion cannot update a disposed phase notifier',
    () async {
      final other = AiTaskController(ChatService());
      expect(other.beginExternalTask(() async {}), isTrue);
      await other.close();
      expect(() {
        other.setExternalPhase(AiTaskPhase.responded);
        other.updateExternalTask('done');
        other.endExternalTask('done');
      }, returnsNormally);
      expect(other.beginExternalTask(() async {}), isFalse);
    },
  );

  testWidgets(
    'restores saved model on startup and accepts chat after loading',
    (tester) async {
      models.dispose();
      final backend = FakeModelBackend()
        ..saved = const ModelSelection(
          ModelLocation.file,
          'first',
          'Test Gemma',
        )
        ..activationGate = Completer<void>();
      models = ModelSelectionController(backend);
      final starting = models.initialize();
      await tester.pumpWidget(
        BlocProvider.value(
          value: task,
          child: ModelSelectionScope(
            controller: models,
            child: LocalizedTestApp(
              home: MobilePilotHomePage(session: session),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('กำลังเตรียม Test Gemma…'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      backend.activationGate!.complete();
      await starting;
      await tester.pumpAndSettle();
      expect(models.ready, isTrue);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
      await send(tester, 'เริ่มคุยได้เลย');
      await tester.pumpAndSettle();
      expect(find.text('คำตอบเสร็จแล้ว'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'startup storage failure shows an error and permits model navigation',
    (tester) async {
      models.dispose();
      models = ModelSelectionController(FakeModelBackend()..failLoad = true);
      await models.initialize();
      await show(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('เปิดคลังโมเดลไม่สำเร็จ'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'MobilePilot'))
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('keeps draft when no model is ready', (tester) async {
    await show(tester);
    await send(tester, 'อย่าล้างข้อความ');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'อย่าล้างข้อความ',
    );
    expect(task.state.messages, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('floating chat shares messages and preserves the home draft', (
    tester,
  ) async {
    await models.selectFile(testModel);
    await show(tester);
    await tester.enterText(find.byType(TextField), 'เก็บร่างนี้ไว้');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const codec = StandardMethodCodec();

    Future<Object?> invoke(String method, [Object? arguments]) async {
      Object? result;
      await messenger.handlePlatformMessage(
        'com.mobilepilot/floating_chat',
        codec.encodeMethodCall(MethodCall(method, arguments)),
        (data) => result = codec.decodeEnvelope(data!),
      );
      return result;
    }

    expect(await invoke('send', 'ข้อความจากหน้าลอย'), isTrue);
    await tester.pumpAndSettle();
    final snapshot = await invoke('snapshot') as Map;
    final messages = (snapshot['messages'] as List).cast<Map>();
    expect(messages.map((message) => message['text']), [
      'ข้อความจากหน้าลอย',
      'คำตอบเสร็จแล้ว',
    ]);
    expect(messages.map((message) => message['user']), [true, false]);
    expect(messages.map((message) => message['index']), [0, 1]);
    expect((snapshot['icons'] as Map)['close'], TablerIcons.x.codePoint);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'เก็บร่างนี้ไว้',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('local streaming, stop and new chat use the shared session', (
    tester,
  ) async {
    await models.selectFile(testModel);
    service.gate = Completer<void>();
    await show(tester);
    await send(tester, 'ช่วยหน่อย');
    expect(
      find.descendant(
        of: find.byType(ChatMessageBubble),
        matching: find.text('ช่วยหน่อย'),
      ),
      findsOneWidget,
    );
    expect(task.state.answer, 'คำตอบ');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    await tester.tap(find.byTooltip('หยุดคำตอบ'));
    await tester.pump();
    expect(service.stopped, isTrue);
    expect(find.byTooltip('กำลังหยุด…'), findsOneWidget);
    service.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byTooltip('หยุดคำตอบ'), findsNothing);
    await tester.tap(find.byIcon(TablerIcons.menu_2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('แชทใหม่'));
    await tester.pumpAndSettle();
    expect(task.state.messages, isEmpty);
    expect(find.text('สวัสดี'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cloud preserves context and clears it when the model changes', (
    tester,
  ) async {
    await models.selectCloud('cloud-one', 'Cloud one');
    final lengths = <int>[];
    await show(
      tester,
      reply: (model, history) async {
        lengths.add(history.length);
        return 'ตอบจาก $model';
      },
    );
    await send(tester, 'หนึ่ง');
    await tester.pumpAndSettle();
    expect(find.text('ตอบจาก cloud-one'), findsOneWidget);
    await send(tester, 'สอง');
    await tester.pumpAndSettle();
    expect(lengths, [1, 3]);
    await models.selectCloud('cloud-two', 'Cloud two');
    await tester.pumpAndSettle();
    expect(find.text('ตอบจาก cloud-one'), findsNothing);
    await send(tester, 'สาม');
    await tester.pumpAndSettle();
    expect(lengths.last, 1);
    expect(find.text('ตอบจาก cloud-two'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('device tools stay enabled across new chat and model changes', (
    tester,
  ) async {
    await models.selectFile(testModel);
    await show(tester);
    expect(service.toolsEnabled, isTrue);
    expect(find.byType(FilterChip), findsNothing);
    expect(find.text('ควบคุมเครื่อง'), findsNothing);
    await send(tester, 'แชทเดิม');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(TablerIcons.menu_2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('แชทใหม่'));
    await tester.pumpAndSettle();
    expect(service.toolsEnabled, isTrue);
    expect(task.state.messages, isEmpty);
    await models.selectCloud('cloud', 'Cloud');
    await tester.pumpAndSettle();
    expect(service.toolsEnabled, isTrue);
    expect(find.byType(FilterChip), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('fits narrow screen with keyboard', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);
    await models.selectFile(testModel);
    await show(tester);
    await send(tester, List.filled(30, 'ทดสอบข้อความยาว').join('\n'));
    await tester.pumpAndSettle();
    expect(find.text('คำตอบเสร็จแล้ว'), findsOneWidget);
    final viewport = tester.getRect(find.byType(ListView).last);
    final composer = tester.getRect(find.byType(ChatBar));
    expect(viewport.bottom, closeTo(composer.bottom, .1));
    expect(
      tester.getRect(find.byType(ChatMessageBubble).last).bottom,
      lessThanOrEqualTo(composer.top),
    );
    await tester.enterText(
      find.byType(TextField),
      'บรรทัด 1\nบรรทัด 2\nบรรทัด 3\nบรรทัด 4',
    );
    await tester.pumpAndSettle();
    final expandedComposer = tester.getRect(find.byType(ChatBar));
    expect(expandedComposer.height, greaterThan(composer.height));
    await tester.drag(find.byType(ListView).last, const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(find.byTooltip('ข้อความล่าสุด'), findsOneWidget);
    await tester.tap(find.byTooltip('ข้อความล่าสุด'));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byType(ChatMessageBubble).last).bottom,
      lessThanOrEqualTo(expandedComposer.top),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Accessibility failure is visible even if the model omits it from its answer',
    (tester) async {
      await models.selectFile(testModel);
      service.toolResult = {
        'code': 'ACCESSIBILITY_DISABLED',
        'error': 'disabled',
      };
      await show(tester);
      await send(tester, 'อ่านหน้าจอ');
      await tester.pumpAndSettle();
      expect(find.text('คำตอบเสร็จแล้ว'), findsOneWidget);
      expect(
        find.text(
          'ยังไม่ได้เปิด MobilePilot Accessibility จึงยังควบคุมหน้าจอต่อไม่ได้',
        ),
        findsOneWidget,
      );
      expect(
        find.text('เปิด Accessibility เพื่อใช้เครื่องมือ'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('saved chat opens from sidebar with its transcript', (
    tester,
  ) async {
    await models.selectFile(testModel);
    await show(tester);
    await send(tester, 'บทสนทนาที่บันทึก');
    await tester.pumpAndSettle();
    await session.flush();
    expect(session.conversations, hasLength(1));
    final id = session.id;
    await tester.tap(find.byIcon(TablerIcons.menu_2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('แชทใหม่'));
    await tester.pumpAndSettle();
    expect(task.state.messages, isEmpty);
    await tester.tap(find.byIcon(TablerIcons.menu_2));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(HomeMenuPanel),
        matching: find.text('บทสนทนาที่บันทึก'),
      ),
    );
    await tester.pumpAndSettle();
    expect(session.id, id);
    expect(task.state.messages.map((m) => m.text), [
      'บทสนทนาที่บันทึก',
      'คำตอบเสร็จแล้ว',
    ]);
    await send(tester, 'คุยต่อ');
    await tester.pumpAndSettle();
    expect(task.state.messages, hasLength(4));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'search opens matching saved chat and copy uses displayed answer',
    (tester) async {
      await models.selectFile(testModel);
      await show(tester);
      await send(tester, 'ข้อความสำหรับค้นหา');
      await tester.pumpAndSettle();
      await session.flush();
      await tester.tap(find.byIcon(TablerIcons.menu_2));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('ค้นหาแชท'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(ConversationSearchPage),
          matching: find.byType(TextField),
        ),
        'ไม่มีคำนี้',
      );
      await tester.pumpAndSettle();
      expect(find.text('ไม่พบแชทที่ค้นหา'), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byType(ConversationSearchPage),
          matching: find.byType(TextField),
        ),
        'สำหรับค้นหา',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(ConversationSearchPage),
          matching: find.text('ข้อความสำหรับค้นหา'),
        ),
      );
      await tester.pumpAndSettle();
      expect(task.state.messages, hasLength(2));
      String? copied;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.tap(find.byTooltip('คัดลอก').last);
      await tester.pumpAndSettle();
      expect(copied, 'คำตอบเสร็จแล้ว');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('retry is explicit and preserves an unrelated draft', (
    tester,
  ) async {
    await models.selectFile(testModel);
    service.fail = true;
    await show(tester);
    await send(tester, 'เปิดแอป');
    await tester.pumpAndSettle();
    expect(find.byTooltip('ลองใหม่'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'ข้อความที่ยังไม่ส่ง');
    service.fail = false;
    await tester.tap(find.byTooltip('ลองใหม่'));
    await tester.pumpAndSettle();
    expect(task.state.messages, hasLength(2));
    await tester.tap(find.widgetWithText(FilledButton, 'ลองใหม่'));
    await tester.pumpAndSettle();
    expect(task.state.messages, hasLength(4));
    expect(service.lastInput, contains('Inspect the current screen'));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'ข้อความที่ยังไม่ส่ง',
    );
    expect(session.failed[1], isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'text attachment reaches model without exposing raw contents in bubble',
    (tester) async {
      await models.selectFile(testModel);
      session.updateDraft(
        'สรุปไฟล์',
        const ChatAttachment(
          name: 'notes.txt',
          text: 'private file contents',
          mime: 'text/plain',
        ),
      );
      await show(tester);
      expect(find.widgetWithText(InputChip, 'notes.txt'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'สรุปไฟล์');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      expect(service.lastInput, contains('<attached_file>'));
      expect(service.lastInput, contains('private file contents'));
      expect(task.state.messages.first.text, 'สรุปไฟล์');
      expect(find.text('notes.txt'), findsOneWidget);
      expect(find.byType(InputChip), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('finished run never leaves a step spinning', (tester) async {
    await tester.pumpWidget(
      const LocalizedTestApp(
        home: Scaffold(
          body: ChatExecutionCard(
            active: false,
            steps: [
              {'state': 'running', 'tool': 'read_current_ui'},
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.text('แผนการดำเนินการอัตโนมัติ'));
    await tester.pumpAndSettle();
    expect(find.text('ยังไม่ยืนยันผล'), findsOneWidget);
  });
}
