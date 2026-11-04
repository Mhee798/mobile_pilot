import '../../../models/presentation/model_selection_scope.dart';
import '../../../models/domain/model_entry.dart';

import 'dart:convert';
import 'dart:typed_data' show BytesBuilder, Uint8List;

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../data/ai_run_history.dart';
import '../../data/ai_device_tools.dart';
import '../../data/gemini_device_chat.dart';
import '../../data/conversation_store.dart';
import '../../application/ai_task_controller.dart';
import '../../application/gemini_chat_controller.dart';
export '../../application/gemini_chat_controller.dart' show GeminiReply;
import 'ai_history_page.dart';
import '../widgets/app_icon_cache.dart';
import '../widgets/answer_speech_controls.dart';
import '../widgets/answer_markdown.dart';
import '../widgets/speech_input_button.dart';
import '../widgets/accessibility_required_action.dart';

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

class _GeminiTestPageState extends State<GeminiTestPage> {
  final _prompt = TextEditingController();
  final _scroll = ScrollController();
  final _icons = AppIconCache();
  late final GeminiChatController _chat;
  bool _pickingFile = false;
  String? _selectedFileName;

  List<GeminiMessage> get _messages => _chat.messages;
  bool get _busy => _chat.busy;
  bool get _toolsEnabled => _chat.toolsEnabled;
  bool get _allowImages => _chat.allowImages;
  bool get _stopRequested => _chat.stopRequested;
  String get _progress => _chat.progress;
  List<Map<String, String>> get _apps => _chat.apps;
  String get _model => _chat.model;

  @override
  void initState() {
    super.initState();
    _chat = GeminiChatController(
      reply: widget.reply,
      history: widget.history,
      taskController: widget.controller,
      deviceChat: GeminiDeviceChat(
        deviceTools: AiDeviceTools(
          snapshot: widget.uiSnapshot,
          targetPackage: widget.targetPackage,
        ),
      ),
    )..addListener(_onChatChanged);
    final selectedModel = context
        .getInheritedWidgetOfExactType<ModelSelectionScope>()
        ?.notifier
        ?.selection;
    if (selectedModel?.location == ModelLocation.cloud) {
      _chat.setModel(selectedModel!.id);
    }
    _openConversationStore();
  }

  Future<void> _openConversationStore() async {
    try {
      final store = await ConversationStore.open();
      if (mounted) _chat.attachStore(store);
    } catch (_) {
      if (mounted) _chat.reportStoreUnavailable();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('เปิดที่เก็บแชทไม่สำเร็จ แชทรอบนี้อาจไม่ถูกบันทึก'),
          ),
        );
      }
    }
  }

  Future<void> _showConversations() async {
    final records = _chat.savedConversations;
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: records.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('ยังไม่มีแชทที่บันทึกไว้'),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final record in records)
                    ListTile(
                      title: Text(
                        '${record['title'] ?? 'แชท'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text('${record['model'] ?? ''}'),
                      onTap: () =>
                          Navigator.pop(context, record['id'] as String),
                    ),
                ],
              ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _selectedFileName = null);
      _chat.openConversation(selected);
    }
  }

  void _onChatChanged() {
    if (mounted) {
      final nearBottom =
          !_scroll.hasClients ||
          _scroll.position.maxScrollExtent - _scroll.position.pixels < 100;
      setState(() {});
      if (nearBottom) _scrollToBottom();
    }
  }

  @override
  void dispose() {
    _chat.removeListener(_onChatChanged);
    _chat.dispose();
    _prompt.dispose();
    _scroll.dispose();
    super.dispose();
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
        _chat.selectTextFile(file.name, text);
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

  Future<void> _send() async {
    final text = _prompt.text.trim();
    if (text.isEmpty || _busy || _pickingFile) return;
    if (!_chat.send(text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('มีงาน AI อื่นกำลังทำงานอยู่')),
      );
      return;
    }
    _prompt.clear();
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
            IconButton(
              tooltip: 'แชทที่บันทึกไว้',
              onPressed: _busy || _chat.store == null
                  ? null
                  : _showConversations,
              icon: const Icon(Icons.forum_outlined),
            ),
            AnswerSpeechControls(
              answer:
                  _messages.isNotEmpty &&
                      !_messages.last.user &&
                      !_messages.last.error
                  ? _messages.last.text
                  : '',
              generating: _busy,
              completed:
                  _messages.isNotEmpty &&
                  !_messages.last.user &&
                  !_messages.last.error,
            ),
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
              onPressed: _busy ? null : _chat.reset,
              icon: const Icon(Icons.add_comment_outlined),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (_chat.storageError != null) Text(_chat.storageError!),
              if (_chat.accessibilityNeeded)
                AccessibilityRequiredAction(
                  onStatus: _chat.updateAccessibility,
                ),
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
                            items: [
                              for (final entry in cloudModels.entries)
                                DropdownMenuItem(
                                  value: entry.key,
                                  child: Text(entry.value),
                                ),
                            ],
                            onChanged: _busy
                                ? null
                                : (value) {
                                    if (value == null || value == _model) {
                                      return;
                                    }
                                    _chat.setModel(value);
                                  },
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('ให้ Gemini ใช้เครื่องมือมือถือ'),
                            subtitle: const Text(
                              'ข้อมูลหน้าจอที่อ่านจะส่งไปยัง Google',
                            ),
                            value: _toolsEnabled,
                            onChanged: _busy ? null : _chat.setToolsEnabled,
                          ),
                          if (_toolsEnabled)
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('อนุญาตส่งภาพหน้าจอให้ Gemini'),
                              subtitle: const Text(
                                'ภาพอาจมีข้อมูลส่วนตัว และจะถูกส่งไปยัง Google',
                              ),
                              value: _allowImages,
                              onChanged: _busy ? null : _chat.setAllowImages,
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
                              child: message.user || message.error
                                  ? SelectableText(message.text)
                                  : AnswerMarkdown(message.text),
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
                        onPressed: _stopRequested ? null : _chat.stop,
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
                          onTap: () => _chat.resolveChoice(app['packageName']),
                        ),
                      TextButton(
                        onPressed: () => _chat.resolveChoice(null),
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
                            _chat.selectTextFile(null, null);
                            _selectedFileName = null;
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
                    SpeechInputButton(
                      controller: _prompt,
                      enabled: !_busy && !_pickingFile,
                    ),
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
