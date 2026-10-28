import 'package:flutter/services.dart';

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';

import '../../../../core/platform/mobile_pilot_platform.dart';
import '../../data/ai_model_service.dart';
import '../../application/ai_task_controller.dart';
import '../../data/model_download.dart';
import 'ai_history_page.dart';

class AiTestPage extends StatefulWidget {
  const AiTestPage({
    super.key,
    this.capturedImage,
    this.uiSnapshot,
    this.targetPackage,
    this.service,
  });
  final Uint8List? capturedImage;
  final List<Map<String, dynamic>>? uiSnapshot;
  final String? targetPackage;
  final AiModelService? service;
  @override
  State<AiTestPage> createState() => _AiTestPageState();
}

class _AiTestPageState extends State<AiTestPage> {
  static const _models = {
    'Gemma 4 E2B · Vision (ประมาณ 2.6 GB)': 'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
    'Gemma 4 E4B · Vision (ประมาณ 3.7 GB)': 'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm',
    'ระบุลิงก์เอง': '',
  };
  final _prompt = TextEditingController();
  final _modelUrl = TextEditingController();
  late final AiTaskController _cubit;
  String _selection = _models.keys.first;
  ModelType _modelType = ModelType.gemma4;
  Uint8List? _attachedImage;
  bool _pickingImage = false;
  bool _visionEnabled = true;
  final _icons = <String, Future<Uint8List?>>{};

  Future<Uint8List?> _iconFor(String packageName) =>
      _icons.putIfAbsent(packageName, () async {
        try {
          return await const MobilePilotPlatform().getAppIcon(packageName);
        } catch (_) {
          return null;
        }
      });
  bool _toolsEnabled = false;
  static const _debugInput = MethodChannel('com.mobilepilot/debug_input');

  @override
  void initState() {
    super.initState();
    // Production tasks belong to the app, not the chat route.
    _cubit = widget.service != null
        ? AiTaskController(widget.service!)
        : context.read<AiTaskController>();
    if (!_cubit.state.busy && _cubit.state.messages.isEmpty) {
      _cubit.service.deviceTools.setInitialContext(
        snapshot: widget.uiSnapshot,
        targetPackage: widget.targetPackage,
      );
    }
    _toolsEnabled = _cubit.service.toolsEnabled;
    _visionEnabled = _cubit.service.visionEnabled;
    if (kDebugMode) {
      _debugInput.setMethodCallHandler((call) async {
        if (call.method != 'fillPrompt') throw MissingPluginException();
        final text = call.arguments;
        if (text is String && text.length <= 2000 && !_cubit.state.busy) {
          _prompt.text = text; // Never submit from an external intent.
        }
      });
    }
  }

  @override
  void dispose() {
    if (kDebugMode) _debugInput.setMethodCallHandler(null);
    _prompt.dispose();
    _modelUrl.dispose();
    if (widget.service != null) _cubit.close();
    super.dispose();
  }

  void _send() {
    final text = _prompt.text.trim();
    if (text.isEmpty && _attachedImage == null) return;
    if (_attachedImage != null && !_cubit.state.visionReady) return;
    final image = _attachedImage;
    _prompt.clear();
    setState(() => _attachedImage = null);
    _cubit.send(text, image: image);
  }

  Future<void> _pickImage() async {
    setState(() => _pickingImage = true);
    try {
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file == null) return;
      final length = await file.length();
      if (length != null && length > 20 * 1024 * 1024) {
        throw const FormatException('รูปภาพต้องมีขนาดไม่เกิน 20 MB');
      }
      final data = BytesBuilder(copy: false);
      await for (final chunk in file.readAsByteStream()) {
        if (data.length + chunk.length > 20 * 1024 * 1024) {
          throw const FormatException('รูปภาพต้องมีขนาดไม่เกิน 20 MB');
        }
        data.add(chunk);
      }
      final bytes = data.takeBytes();
      if (bytes.isEmpty) {
        throw const FormatException('ไฟล์ภาพว่างหรือมีขนาดเกิน 20 MB');
      }
      if (mounted) setState(() => _attachedImage = bytes);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('เลือกภาพไม่สำเร็จ: $error')));
      }
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  Future<void> _attach() async {
    final useCapture = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('เลือกรูปจากเครื่อง'),
              onTap: () => Navigator.pop(context, false),
            ),
            if (widget.capturedImage != null)
              ListTile(
                leading: const Icon(Icons.screenshot),
                title: const Text('ใช้ภาพหน้าจอล่าสุดที่จับไว้'),
                onTap: () => Navigator.pop(context, true),
              ),
          ],
        ),
      ),
    );
    if (!mounted || useCapture == null) return;
    if (useCapture) {
      setState(() => _attachedImage = widget.capturedImage);
    } else {
      await _pickImage();
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<AiTaskController, AiTaskState>(
    bloc: _cubit,
    builder: (context, state) {
      final colors = Theme.of(context).colorScheme;
      return PopScope(
        canPop: !state.busy && !_pickingImage,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('ทดสอบ AI'),
            actions: [
              if (_cubit.service.history case final history?)
                IconButton(
                  tooltip: 'ประวัติการทำงาน AI',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AiHistoryPage(history: history),
                    ),
                  ),
                  icon: const Icon(Icons.history),
                ),
              IconButton(
                tooltip: 'เริ่มแชทใหม่',
                onPressed: state.busy || !state.ready ? null : _cubit.resetChat,
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
                      maxHeight: MediaQuery.sizeOf(context).height * 0.4,
                    ),
                    child: SingleChildScrollView(child: _modelSettings(state)),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        state.ready
                            ? Icons.check_circle_outline
                            : Icons.info_outline,
                        size: 18,
                        color: state.ready
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          state.status,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                if (state.interruptedRequest case final request?)
                  Card(
                    child: ListTile(
                      title: const Text('มีงานที่ขาดตอนจากครั้งก่อน'),
                      subtitle: Text(
                        '$request\nบางคำสั่งอาจทำไปแล้ว กรุณาตรวจสถานะจริงก่อนสั่งต่อ ระบบจะไม่ทำซ้ำอัตโนมัติ',
                      ),
                      trailing: TextButton(
                        onPressed: state.busy
                            ? null
                            : _cubit.dismissInterrupted,
                        child: const Text('รับทราบ'),
                      ),
                    ),
                  ),
                if (state.toolsUsed.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'เครื่องมือที่ใช้รอบล่าสุด: ${state.toolsUsed.join(', ')}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (_toolsEnabled &&
                    !state.busy &&
                    state.messages.isNotEmpty &&
                    state.toolsUsed.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'รอบนี้ AI ไม่ได้เรียกเครื่องมือ',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                for (final result in state.toolResults)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      result,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (state.waitingForUi)
                  OutlinedButton.icon(
                    onPressed: state.openingReadTarget
                        ? null
                        : _cubit.openReadTarget,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('เปิดแอปเป้าหมายเพื่ออ่านหน้าจอ'),
                  ),
                if (state.busy && !state.canCancel && state.messages.isEmpty)
                  const LinearProgressIndicator(),
                if (state.progress case final stats?)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LinearProgressIndicator(
                          value: stats.total == null || stats.total == 0
                              ? null
                              : stats.received / stats.total!,
                        ),
                        Text(
                          'ดาวน์โหลด ${formatDownloadSize(stats.received)} / ${stats.total == null ? 'ไม่ทราบขนาด' : formatDownloadSize(stats.total!)}${stats.bytesPerSecond == null ? '' : ' · เฉลี่ย ${formatDownloadSize(stats.bytesPerSecond!)}/วินาที'}',
                        ),
                      ],
                    ),
                  ),
                if (state.canCancel)
                  TextButton(
                    onPressed: _cubit.cancelDownload,
                    child: const Text('ยกเลิกดาวน์โหลด'),
                  ),
                if (state.generating)
                  TextButton.icon(
                    onPressed: state.stoppingGeneration
                        ? null
                        : _cubit.stopGeneration,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text(
                      state.stoppingGeneration ? 'กำลังหยุด' : 'หยุดสร้างคำตอบ',
                    ),
                  ),
                Expanded(
                  child: state.messages.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.forum_outlined,
                                  size: 48,
                                  color: colors.primary,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'เริ่มบทสนทนา',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  state.ready
                                      ? 'ส่งข้อความเพื่อทดลองคุยกับ AI'
                                      : 'โหลดโมเดลจากเมนูด้านบนก่อนเริ่มแชท',
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          reverse: true,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                          itemCount: state.messages.length,
                          itemBuilder: (context, index) {
                            final messageIndex =
                                state.messages.length - index - 1;
                            final message = state.messages[messageIndex];
                            final canChoose =
                                state.pendingChoiceIndex == messageIndex;
                            return Align(
                              alignment: message.isUser
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                constraints: const BoxConstraints(
                                  maxWidth: 520,
                                ),
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: message.isUser
                                      ? colors.primaryContainer
                                      : colors.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          message.isUser ? 'คุณ' : 'AI',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium,
                                        ),
                                        SizedBox(width: 4),
                                        Icon(
                                          message.isUser
                                              ? Icons.person_rounded
                                              : Icons.smart_toy_rounded,
                                          size: 16,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    if (message.image != null)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        child: Image.memory(
                                          message.image!,
                                          height: 160,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    SelectableText(
                                      message.isUser && message.text.isEmpty
                                          ? ''
                                          : message.text.isEmpty
                                          ? (state.busy
                                                ? 'กำลังตอบ…'
                                                : 'ไม่มีคำตอบ')
                                          : message.text,
                                    ),
                                    for (final app in message.apps)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: InkWell(
                                          onTap: canChoose && !state.busy
                                              ? () => _cubit.chooseApp(
                                                  messageIndex,
                                                  app['packageName']!,
                                                )
                                              : null,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.all(8),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                FutureBuilder<Uint8List?>(
                                                  future: _iconFor(
                                                    app['packageName']!,
                                                  ),
                                                  builder:
                                                      (
                                                        context,
                                                        snapshot,
                                                      ) => snapshot.data == null
                                                      ? const Icon(
                                                          Icons.apps,
                                                          size: 40,
                                                        )
                                                      : Image.memory(
                                                          snapshot.data!,
                                                          width: 40,
                                                          height: 40,
                                                          errorBuilder:
                                                              (_, _, _) =>
                                                                  const Icon(
                                                                    Icons.apps,
                                                                    size: 40,
                                                                  ),
                                                        ),
                                                ),
                                                const SizedBox(width: 10),
                                                Flexible(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(app['label']!),
                                                      Text(
                                                        app['packageName']!,
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .bodySmall,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                if (canChoose)
                                                  const Icon(
                                                    Icons.chevron_right,
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    if (canChoose)
                                      const Text('แตะรายการเพื่อเปิดแอป'),
                                    if (canChoose)
                                      TextButton(
                                        onPressed: state.busy
                                            ? null
                                            : () => _cubit.cancelChoice(
                                                messageIndex,
                                              ),
                                        child: const Text('ยกเลิกการเลือกแอป'),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                if (_attachedImage != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Image.memory(
                          _attachedImage!,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(child: Text('ภาพที่จะแนบ')),
                        IconButton(
                          tooltip: 'เอาภาพออก',
                          onPressed: state.busy
                              ? null
                              : () => setState(() => _attachedImage = null),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: 'แนบรูป',
                        onPressed:
                            state.busy || !state.visionReady || _pickingImage
                            ? null
                            : _attach,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _prompt,
                          enabled: !state.busy && state.ready,
                          minLines: 1,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            hintText: 'พิมพ์ข้อความ',
                            labelText: 'ข้อความทดสอบ',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: 'ส่งข้อความ',
                        onPressed:
                            state.busy ||
                                !state.ready ||
                                _pickingImage ||
                                (_attachedImage != null && !state.visionReady)
                            ? null
                            : _send,
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
    },
  );

  Widget _modelSettings(AiTaskState state) => ExpansionTile(
    title: const Text('จัดการโมเดล'),
    subtitle: Text(
      state.ready ? 'โมเดลพร้อมใช้งาน' : 'เลือก ดาวน์โหลด หรือโหลดโมเดล',
    ),
    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    children: [
      SwitchListTile(
        value: _toolsEnabled,
        title: const Text('ให้ AI ทดลองใช้เครื่องมือ'),
        subtitle: const Text(
          'ค้นหาและเปิดแอป รวมถึงอ่าน UI tree ที่บันทึกไว้ เปิดก่อนเริ่มแชท',
        ),
        onChanged: state.busy || state.messages.isNotEmpty
            ? null
            : (value) => setState(() {
                _toolsEnabled = value;
                _cubit.service.toolsEnabled = value;
              }),
      ),
      SwitchListTile(
        value: _visionEnabled,
        title: const Text('เปิด Vision สำหรับโมเดลที่โหลดถัดไป'),
        subtitle: const Text('ปิดสำหรับโมเดลที่รองรับข้อความเท่านั้น'),
        onChanged: state.busy
            ? null
            : (value) => setState(() {
                _visionEnabled = value;
                _cubit.service.visionEnabled = value;
              }),
      ),
      const Text(
        'ดาวน์โหลดโมเดลหรือเลือกไฟล์ .litertlm ที่มีอยู่ การดาวน์โหลดต้องใช้อินเทอร์เน็ตและพื้นที่ว่าง',
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: _selection,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'โมเดลที่จะดาวน์โหลด'),
        items: _models.keys
            .map((name) => DropdownMenuItem(value: name, child: Text(name)))
            .toList(),
        onChanged: state.busy
            ? null
            : (value) {
                if (value != null) setState(() => _selection = value);
              },
      ),
      if (_selection == 'ระบุลิงก์เอง')
        TextField(
          controller: _modelUrl,
          enabled: !state.busy,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'ลิงก์ HTTPS ของไฟล์ .litertlm',
          ),
        ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: state.busy
            ? null
            : () => _cubit.download(
                _selection == 'ระบุลิงก์เอง'
                    ? _modelUrl.text
                    : _models[_selection]!,
                _selection == 'ระบุลิงก์เอง' ? _modelType : ModelType.gemma4,
              ),
        icon: const Icon(Icons.download),
        label: const Text('ดาวน์โหลดโมเดล'),
      ),
      if (state.saved)
        OutlinedButton(
          onPressed: state.busy ? null : _cubit.loadSaved,
          child: const Text('ใช้โมเดลที่บันทึกไว้'),
        ),
      DropdownButtonFormField<ModelType>(
        initialValue: _modelType,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'รุ่นสำหรับลิงก์หรือไฟล์ที่เลือกเอง',
        ),
        items: const [
          DropdownMenuItem(value: ModelType.gemma4, child: Text('Gemma 4')),
          DropdownMenuItem(
            value: ModelType.gemmaIt,
            child: Text('Gemma 3 และรุ่นก่อน'),
          ),
        ],
        onChanged: state.busy
            ? null
            : (value) {
                if (value != null) setState(() => _modelType = value);
              },
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: state.busy ? null : () => _cubit.importModel(_modelType),
        icon: const Icon(Icons.folder_open),
        label: const Text('เลือกและโหลดโมเดล'),
      ),
    ],
  );
}
