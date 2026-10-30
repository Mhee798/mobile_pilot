import 'dart:async';
import 'dart:convert';
import 'dart:typed_data' show BytesBuilder;

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../../../firebase_options.dart';
import '../../data/ai_run_history.dart';
import '../../data/ai_device_tools.dart';
import '../../data/gemini_device_chat.dart';
import '../../application/ai_task_controller.dart';
import 'ai_history_page.dart';
import '../widgets/app_icon_cache.dart';

typedef GeminiReply = Future<String?> Function(
  String model,
  List<Content> history,
);

/// Cloud chat with opt-in device tools.
class GeminiTestPage extends StatefulWidget {
  const GeminiTestPage({
    super.key,
    this.reply,
    this.history,
    this.controller,
    this.uiSnapshot,
    this.targetPackage,
  });

  final GeminiReply? reply;
  final AiRunHistory? history;
  final AiTaskController? controller;
  final List<Map<String, dynamic>>? uiSnapshot;
  final String? targetPackage;

  @override
  State<GeminiTestPage> createState() => _GeminiTestPageState();
}

class _Message {
  const _Message(this.text, {required this.user, this.error = false});
  final String text;
  final bool user;
  final bool error;
}

class _GeminiTestPageState extends State<GeminiTestPage> {
  final _prompt = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_Message>[];
  final _history = <Content>[];
  late final _deviceChat = GeminiDeviceChat(
    deviceTools: AiDeviceTools(
      snapshot: widget.uiSnapshot,
      targetPackage: widget.targetPackage,
    ),
  );
  bool _busy = false;
  bool _toolsEnabled = false;
  bool _allowImages = false;
  bool _stopRequested = false;
  bool _pickingFile = false;
  String? _selectedFileName;
  String _progress = '';
  Completer<String?>? _choice;
  List<Map<String, String>> _apps = [];
  final _icons = AppIconCache();
  String _model = 'gemini-3.5-flash-lite';

  @override
  void dispose() {
    if (_busy) {
      _stopRequested = true;
      _resolveChoice(null);
      _deviceChat.cancel();
    }
    _prompt.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _resolveChoice(String? packageName) {
    final choice = _choice;
    _choice = null;
    if (choice != null && !choice.isCompleted) choice.complete(packageName);
    _apps = [];
  }

  Future<void> _selectFile() async {
    setState(() => _pickingFile = true);
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['txt', 'md', 'json', 'csv'],
      );
      if (file == null || !mounted) return;
      final size = await file.length();
      if (size != null && size > 32768) {
        throw const FormatException('ไฟล์ต้องไม่เกิน 32 KB');
      }
      final buffer = BytesBuilder(copy: false);
      await for (final chunk in file.readAsByteStream()) {
        if (buffer.length + chunk.length > 32768) {
          throw const FormatException('ไฟล์ต้องไม่เกิน 32 KB');
        }
        buffer.add(chunk);
      }
      final text = utf8.decode(buffer.takeBytes());
      if (!mounted) return;
      setState(() {
        _selectedFileName = file.name;
        _deviceChat.selectTextFile(file.name, text);
        _history.clear();
        _messages.clear();
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('อ่านไฟล์ไม่สำเร็จ: $error')));
      }
    } finally {
      if (mounted) setState(() => _pickingFile = false);
    }
  }

  Future<String?> _chooseApp(List<Map<String, String>> apps) {
    if (!mounted || _stopRequested || apps.isEmpty) return Future.value(null);
    final choice = Completer<String?>();
    setState(() {
      _choice = choice;
      _apps = apps;
      _progress = 'เลือกแอปเพื่อทำงานต่อ';
    });
    widget.controller?.updateExternalTask('รอเลือกแอป');
    _scrollToBottom();
    return choice.future;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<String?> _cloudReply(String model, List<Content> history) async {
    await _initializeFirebase();
    final response = await FirebaseAI.googleAI()
        .generativeModel(model: model)
        .generateContent(history);
    return response.text;
  }

  Future<void> _initializeFirebase() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
    );
  }

  Future<void> _send() async {
    final text = _prompt.text.trim();
    if (text.isEmpty || _busy || _pickingFile) return;
    final controller = widget.controller;
    if (controller != null && !controller.beginExternalTask(_stop)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('มีงาน AI อื่นกำลังทำงานอยู่')),
      );
      return;
    }
    _prompt.clear();
    setState(() {
      _busy = true;
      _stopRequested = false;
      _progress = 'Gemini กำลังตอบ...';
      _messages.add(_Message(text, user: true));
    });
    _scrollToBottom();
    controller?.updateExternalTask('Gemini กำลังตอบ');
    final userContent = Content.text(text);
    final timer = Stopwatch()..start();
    String? runId;
    var runState = 'responded';
    var runReason = '';
    var runAnswer = '';
    try {
      runId = await widget.history?.start(
        text,
        'Gemini Cloud · $_model',
        tools: _toolsEnabled,
        image: false,
      );
      if (_stopRequested) throw StateError('ยกเลิกแล้ว');
      String? result;
      List<Content>? toolHistory;
      if (_toolsEnabled && widget.reply == null) {
        await _initializeFirebase();
        if (_stopRequested) throw StateError('ยกเลิกแล้ว');
        final output = await _deviceChat.run(
          model: _model,
          history: [..._history, userContent],
          allowImages: _allowImages,
          progress: (value) {
            controller?.updateExternalTask(value);
            if (mounted) setState(() => _progress = value);
          },
          onOutcome: (state, reason) {
            runState = state;
            runReason = reason;
          },
          chooseApp: _chooseApp,
          onStepStart: (name, args) => runId == null
              ? null
              : widget.history?.beginStep(runId, name, args),
          onStepEnd: (step, result, elapsed) async {
            if (runId != null) {
              await widget.history?.endStep(runId, step, result, elapsed);
            }
          },
        );
        result = output.$1;
        toolHistory = output.$2;
      } else {
        result = await (widget.reply ?? _cloudReply)(_model, [
          ..._history,
          userContent,
        ]).timeout(const Duration(seconds: 60));
      }
      if (_stopRequested) throw StateError('ยกเลิกแล้ว');
      final answer = result?.trim();
      runAnswer = answer ?? '';
      if (!mounted) return;
      if (answer == null || answer.isEmpty) {
        setState(
          () => _messages.add(
            const _Message(
              'โมเดลไม่ได้ส่งข้อความตอบ ลองส่งใหม่อีกครั้ง',
              user: false,
              error: true,
            ),
          ),
        );
      } else {
        if (toolHistory != null && toolHistory.length > _history.length) {
          _history
            ..clear()
            ..addAll(toolHistory);
        } else {
          _history.addAll([
            userContent,
            Content.model([TextPart(answer)]),
          ]);
        }
        setState(() => _messages.add(_Message(answer, user: false)));
      }
    } catch (error) {
      runState = _stopRequested ? 'cancelled' : 'failed';
      runReason = '$error';
      if (mounted) {
        setState(
          () => _messages.add(
            _Message('ส่งข้อความไม่สำเร็จ: $error', user: false, error: true),
          ),
        );
      }
    } finally {
      if (runId != null) {
        await widget.history?.finish(
          runId,
          runState,
          runReason,
          runAnswer,
          timer.elapsedMilliseconds,
        );
      }
      controller?.endExternalTask(
        _stopRequested
            ? 'หยุดงาน Gemini แล้ว'
            : runState == 'failed'
            ? 'งาน Gemini ไม่สำเร็จ'
            : 'Gemini ตอบแล้ว',
      );
      if (mounted) {
        setState(() => _busy = false);
        _scrollToBottom();
      }
    }
  }

  Future<void> _stop() async {
    if (!_busy || _stopRequested) return;
    _stopRequested = true;
    _resolveChoice(null);
    if (_toolsEnabled) _deviceChat.cancel();
    widget.controller?.updateExternalTask('กำลังหยุด Gemini');
    if (mounted) setState(() => _progress = 'กำลังหยุด...');
  }

  void _reset() {
    setState(() {
      _history.clear();
      _messages.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_busy && !_pickingFile,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('แชท Gemini Cloud'),
          actions: [
            if (widget.history != null)
              IconButton(
                tooltip: 'ประวัติการทำงาน AI',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AiHistoryPage(history: widget.history!),
                  ),
                ),
                icon: const Icon(Icons.history),
              ),
            IconButton(
              tooltip: 'เริ่มแชทใหม่',
              onPressed: _busy ? null : _reset,
              icon: const Icon(Icons.add_comment_outlined),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (MediaQuery.viewInsetsOf(context).bottom == 0)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .4,
                  ),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'ข้อความและประวัติแชทจะส่งไปยัง Gemini ผ่าน Firebase',
                          ),
                          DropdownButton<String>(
                            value: _model,
                            isExpanded: true,
                            items: const [
                              DropdownMenuItem(
                                value: 'gemini-3.5-flash-lite',
                                child: Text('Gemini 3.5 Flash-Lite'),
                              ),
                              DropdownMenuItem(
                                value: 'gemini-3.8-flash',
                                child: Text('Gemini 3.8 Flash'),
                              ),
                            ],
                            onChanged: _busy
                                ? null
                                : (value) {
                                    if (value == null || value == _model) {
                                      return;
                                    }
                                    setState(() {
                                      _model = value;
                                      _history.clear();
                                      _messages.clear();
                                    });
                                  },
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('ให้ Gemini ใช้เครื่องมือมือถือ'),
                            subtitle: const Text(
                              'ข้อมูลหน้าจอที่อ่านจะส่งไปยัง Google',
                            ),
                            value: _toolsEnabled,
                            onChanged: _busy
                                ? null
                                : (value) => setState(() {
                                    _toolsEnabled = value;
                                    if (!value) _allowImages = false;
                                    _history.clear();
                                    _messages.clear();
                                  }),
                          ),
                          if (_toolsEnabled)
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('อนุญาตส่งภาพหน้าจอให้ Gemini'),
                              subtitle: const Text(
                                'ภาพอาจมีข้อมูลส่วนตัว และจะถูกส่งไปยัง Google',
                              ),
                              value: _allowImages,
                              onChanged: _busy
                                  ? null
                                  : (value) => setState(() {
                                      _allowImages = value;
                                      _history.clear();
                                      _messages.clear();
                                    }),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: _messages.isEmpty
                    ? const Center(child: Text('ส่งข้อความเพื่อเริ่มสนทนา'))
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          return Align(
                            alignment: message.user
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              constraints: const BoxConstraints(maxWidth: 600),
                              decoration: BoxDecoration(
                                color: message.error
                                    ? colors.errorContainer
                                    : message.user
                                    ? colors.primaryContainer
                                    : colors.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: SelectableText(message.text),
                            ),
                          );
                        },
                      ),
              ),
              if (_busy)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Expanded(child: Text(_progress)),
                      TextButton(
                        onPressed: _stopRequested ? null : _stop,
                        child: const Text('หยุด'),
                      ),
                    ],
                  ),
                ),
              if (_apps.isNotEmpty)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .3,
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text('เลือกแอปที่ต้องการ'),
                      ),
                      for (final app in _apps)
                        ListTile(
                          leading: FutureBuilder<Uint8List?>(
                            future: _icons.get(app['packageName']!),
                            builder: (context, snapshot) =>
                                snapshot.data == null
                                ? const Icon(Icons.apps)
                                : Image.memory(
                                    snapshot.data!,
                                    width: 36,
                                    height: 36,
                                  ),
                          ),
                          title: Text(app['label']!),
                          subtitle: Text(app['packageName']!),
                          onTap: () => setState(
                            () => _resolveChoice(app['packageName']),
                          ),
                        ),
                      TextButton(
                        onPressed: () => setState(() => _resolveChoice(null)),
                        child: const Text('ยกเลิกการเลือกแอป'),
                      ),
                    ],
                  ),
                ),
              if (_selectedFileName != null)
                ListTile(
                  dense: true,
                  title: Text(
                    'ไฟล์: $_selectedFileName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: const Text(
                    'เนื้อหาอาจส่งไป Google เมื่อ AI อ่านไฟล์',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'เอาไฟล์ออก',
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _deviceChat.selectTextFile(null, null);
                            _selectedFileName = null;
                            _history.clear();
                            _messages.clear();
                          }),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: 'เลือกไฟล์ข้อความ',
                      onPressed: _busy || _pickingFile || !_toolsEnabled
                          ? null
                          : _selectFile,
                      icon: const Icon(Icons.attach_file),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _prompt,
                        enabled: !_busy,
                        minLines: 1,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText: 'พิมพ์ข้อความ',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _busy ? null : _send,
                      tooltip: 'ส่งข้อความ',
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
