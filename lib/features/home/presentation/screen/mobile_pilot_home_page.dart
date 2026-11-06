import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';

import '../../application/home_chat_session.dart';
import '../../../ai/application/ai_task_phase.dart';
import '../../../../core/settings/app_settings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../ai/application/ai_task_controller.dart';
import '../../../ai/application/gemini_chat_controller.dart';
import '../../../ai/data/markdown_speech_text.dart';
import '../../../ai/presentation/widgets/accessibility_required_action.dart';
import '../../../models/domain/model_entry.dart';
import '../../../settings/presentation/screen/settings_page.dart';
import '../../../models/presentation/model_selection_scope.dart';
import '../../../models/presentation/screen/model_selection_page.dart';
import '../widgets/bottom_glow_widget.dart';
import '../widgets/chat_bar.dart';
import '../widgets/chat_message_bubble.dart';
import '../widgets/chat_execution_card.dart';
import 'conversation_search_page.dart';
import '../widgets/figma_background_widget.dart';
import '../widgets/full_screen_swipe_menu.dart';
import '../widgets/home_menu_panel.dart';

export '../widgets/bottom_glow_widget.dart' show BottomGlowWidget;
export '../widgets/chat_bar.dart' show ChatBar, AudioWaveWidget;
export '../widgets/figma_background_widget.dart' show FigmaBackgroundWidget;

class MobilePilotHomePage extends StatefulWidget {
  const MobilePilotHomePage({super.key, this.cloudReply, this.session});
  final HomeChatSession? session;
  final GeminiReply? cloudReply;
  @override
  State<MobilePilotHomePage> createState() => _MobilePilotHomePageState();
}

class _MobilePilotHomePageState extends State<MobilePilotHomePage>
    with WidgetsBindingObserver {
  late final AiTaskController _local;
  late final HomeChatSession _session;
  ChatAttachment? _attachment, _lastDraftAttachment;
  String _lastDraftText = '';
  bool _switchingChat = false,
      _pickingAttachment = false,
      _draftTouched = false;
  int _runUserIndex = 0;
  late final GeminiChatController _cloud;
  StreamSubscription<AiTaskState>? _subscription;
  final _scroll = ScrollController();
  final _composerKey = GlobalKey();
  double _composerHeight = 0;
  bool _composerMeasureScheduled = false;
  final _draft = TextEditingController();
  final _tts = FlutterTts();
  bool _resetting = false;
  Set<String> _previousRuns = {};
  String? _request;
  bool _scrollScheduled = false;
  String? _selectionKey;
  bool _follow = true;
  final _messageTimes = <String, DateTime>{};

  static const _floatingChat = MethodChannel('com.mobilepilot/floating_chat');
  Timer? _floatingUpdate;
  static const _floatingPageSize = 20;
  int _floatingLimit = _floatingPageSize;
  String? _floatingConversation;

  List<Map<String, String>> get _pendingApps {
    if (_isCloud) return _cloud.apps;
    final index = _local.state.pendingChoiceIndex;
    return index == null ? [] : _local.state.messages[index].apps;
  }

  Future<bool> _choosePendingApp(String packageName) async {
    if (!_pendingApps.any((app) => app['packageName'] == packageName)) {
      return false;
    }
    if (_isCloud) {
      _cloud.resolveChoice(packageName);
    } else {
      await _local.chooseApp(_local.state.pendingChoiceIndex!, packageName);
    }
    return true;
  }

  Map<String, Object?> _floatingSnapshot() {
    final run = _session.runs.values.lastOrNull;
    final steps = (run?['steps'] as List? ?? const []).whereType<Map>();
    final messages = _backendMessages;
    if (_floatingConversation != _session.id) {
      _floatingConversation = _session.id;
      _floatingLimit = _floatingPageSize;
    }
    final first = (messages.length - _floatingLimit).clamp(0, messages.length);
    final firstTime = first < _session.times.length
        ? _session.times[first]
        : null;
    return {
      'conversation': _session.id,
      'hasOlder': first > 0,
      'apps': _pendingApps,
      'modelLabel': ModelSelectionScope.maybeOf(context)?.selection?.label,
      'welcome': context.tr('chat.welcome'),
      'heading': firstTime == null
          ? null
          : '${MaterialLocalizations.of(context).formatShortDate(firstTime)} '
                '${TimeOfDay.fromDateTime(firstTime).format(context)}',
      'messages': [
        for (var index = first; index < messages.length; index++)
          {
            'index': index,
            'user': messages[index].isUser,
            'text': messages[index].text,
            'attachment': _session.attachments[index]?.name,
            'hasImage':
                messages[index].image != null ||
                _session.attachments[index]?.bytes != null,
            'timestamp': index < _session.times.length
                ? _session.times[index].toIso8601String()
                : null,
            'time': index < _session.times.length
                ? TimeOfDay.fromDateTime(_session.times[index]).format(context)
                : null,
            'failed': index < _session.failed.length && _session.failed[index],
          },
      ],
      'busy': _busy,
      'canAttachPhoto': _isCloud || _local.state.visionReady,
      'cloud': _isCloud,
      'runs': [
        for (final entry in _session.runs.entries)
          if (entry.key >= first)
            {
              'index': entry.key,
              'id': entry.value['id'],
              'state': entry.value['state'],
              'steps': entry.value['steps'],
            },
      ],
      'running': _isCloud ? _cloud.busy : _local.state.generating,
      'stopping': _isCloud
          ? _cloud.busy && _cloud.stopRequested
          : _local.state.stoppingGeneration,
      'labels': {
        for (final key in [
          'copy',
          'read',
          'retry',
          'retry_notice',
          'cancel',
          'failed',
          'stopping',
        ])
          key: context.tr('chat.$key'),
      },
      'icons': const <String, IconData>{
        'plus': TablerIcons.plus,
        'microphone': TablerIcons.microphone,
        'send': TablerIcons.send_2,
        'stop': TablerIcons.square,
        'robot': TablerIcons.robot,
        'close': TablerIcons.x,
      }.map((name, icon) => MapEntry(name, icon.codePoint)),
      'stepsTitle': context.tr('chat.steps'),
      'steps': [
        for (final step in steps)
          {
            'label': ChatExecutionCard.toolLabel(context, step['tool']),
            'status': context.tr(
              step['state'] == 'running' && run?['state'] == 'running'
                  ? 'chat.running'
                  : step['state'] != 'returned'
                  ? 'chat.unknown'
                  : step['result'] is Map &&
                        ((step['result'] as Map)['error'] != null ||
                            (step['result'] as Map)['success'] == false)
                  ? 'chat.failed'
                  : 'chat.returned',
            ),
          },
      ],
    };
  }

  Future<Object?> _handleFloatingChat(MethodCall call) async {
    if (!mounted) return null;
    switch (call.method) {
      case 'snapshot':
        return _floatingSnapshot();
      case 'loadOlder':
        if (call.arguments != _session.id ||
            _floatingConversation != _session.id) {
          return null;
        }
        _floatingLimit += _floatingPageSize;
        return _floatingSnapshot();
      case 'chooseApp':
        final choice = call.arguments as Map?;
        final packageName = choice?['packageName'];
        if (choice?['conversation'] != _session.id || packageName is! String) {
          return false;
        }
        return _choosePendingApp(packageName);
      case 'messageImage':
        final data = call.arguments as Map?;
        final index = data?['index'];
        final messages = _backendMessages;
        if (data?['conversation'] != _session.id ||
            index is! int ||
            index < 0 ||
            index >= messages.length) {
          return null;
        }
        return messages[index].image ?? _session.attachments[index]?.bytes;
      case 'newChat':
        return _newChat();
      case 'send':
        final arguments = call.arguments;
        final data = arguments is Map ? arguments : null;
        final text =
            ((data == null ? arguments : data['text']) as String?)?.trim() ??
            '';
        final attachment = data?['attachment'];
        return _send(
          text,
          fromOverlay: true,
          overlayAttachment: attachment is Map
              ? ChatAttachment.fromMap(attachment)
              : null,
        );
      case 'pick':
        return (await _pickAttachment(
          call.arguments == true,
          fromOverlay: true,
        ))?.toMap();
      case 'stop':
        _stopReply();
        return true;
      case 'retry':
        final arguments = call.arguments as Map?;
        final index = arguments?['index'];
        if (arguments?['conversation'] != _session.id ||
            index is! int ||
            index < 0 ||
            index >= _session.failed.length ||
            !_session.failed[index]) {
          return false;
        }
        return _retryMessage(index, fromOverlay: true);
      case 'read':
        final text = call.arguments as String?;
        if (text != null && text.isNotEmpty) unawaited(_read(text));
        return null;
      default:
        throw MissingPluginException();
    }
  }

  void _stopReply() {
    unawaited(_isCloud ? _cloud.stop() : _local.stopGeneration());
  }

  Future<void> _publishFloatingChat() async {
    try {
      await _floatingChat.invokeMethod<void>('update', _floatingSnapshot());
    } on MissingPluginException {
      // The native overlay is Android-only.
    } on PlatformException {
      // The overlay can disconnect while a reply is streaming.
    }
  }

  Future<void> _onTaskPhaseChanged() async {
    if (_local.taskPhase.value != AiTaskPhase.usingTool) return;
    try {
      await _floatingChat.invokeMethod<void>('toolStarted');
    } on MissingPluginException {
      // The native overlay is Android-only.
    } on PlatformException {
      // The overlay can disconnect while a tool starts.
    }
  }

  @override
  void initState() {
    super.initState();
    _floatingChat.setMethodCallHandler(_handleFloatingChat);
    WidgetsBinding.instance.addObserver(this);
    _session = widget.session ?? HomeChatSession();
    _session.addListener(_sessionChanged);
    _attachment = _session.draftAttachment;
    _draft.text = _session.draft;
    _lastDraftText = _draft.text;
    _lastDraftAttachment = _attachment;
    _draft.addListener(_draftChanged);
    unawaited(
      _session.initialize().then((_) {
        if (!mounted || _draftTouched) return;
        _attachment = _session.draftAttachment;
        _draft.text = _session.draft;
        _draftChanged();
        setState(() {});
      }),
    );
    _local = context.read<AiTaskController>();
    _local.taskPhase.addListener(_onTaskPhaseChanged);
    _cloud = GeminiChatController(
      reply: widget.cloudReply,
      taskController: _local,
      history: _local.service.history,
    );
    _cloud.setToolsEnabled(true);
    _cloud.addListener(_changed);
    _subscription = _local.stream.listen((_) => _changed());
    _local.service.history?.addListener(_changed);
    _local.service.toolsEnabled = true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final selection = ModelSelectionScope.maybeOf(context)?.selection;
    final key = '${selection?.location}:${selection?.id}';
    if (key != _selectionKey) {
      if (_selectionKey != null && !_switchingChat) _session.startNew();
      _selectionKey = key;
      _local.service.toolsEnabled = true;
      _cloud.setToolsEnabled(true);
      _messageTimes.clear();
      _request = null;
    }
    if (selection?.location == ModelLocation.cloud) {
      _cloud.setModel(selection!.id);
    }
    _scheduleFloatingUpdate();
  }

  bool get _preparingModel {
    final models = ModelSelectionScope.maybeOf(context);
    return models != null &&
        (models.busy || !models.loaded && models.errorKey == null);
  }

  bool get _busy =>
      _pickingAttachment ||
      _resetting ||
      _cloud.busy ||
      _local.state.busy ||
      _preparingModel;
  bool get _isCloud =>
      ModelSelectionScope.maybeOf(context)?.selection?.location ==
      ModelLocation.cloud;

  void _scheduleFloatingUpdate() {
    _floatingUpdate ??= Timer(const Duration(milliseconds: 80), () {
      _floatingUpdate = null;
      if (mounted) unawaited(_publishFloatingChat());
    });
  }

  void _changed() {
    if (!mounted) return;
    _scheduleFloatingUpdate();
    _syncSession();
    setState(() {});
    if (_follow && !_scrollScheduled) {
      _scrollScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollScheduled = false;
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  List<AiChatMessage> get _backendMessages => _isCloud
      ? _cloud.messages
            .map(
              (m) =>
                  AiChatMessage(isUser: m.user, text: m.text, image: m.image),
            )
            .toList()
      : _local.state.messages;

  void _sessionChanged() {
    if (mounted) setState(() {});
  }

  void _draftChanged() {
    if (_lastDraftText == _draft.text &&
        identical(_lastDraftAttachment, _attachment)) {
      return;
    }
    _lastDraftText = _draft.text;
    _lastDraftAttachment = _attachment;
    _draftTouched = true;
    _session.updateDraft(_draft.text, _attachment);
  }

  void _syncSession() {
    if (_switchingChat || ModelSelectionScope.maybeOf(context)?.busy == true) {
      return;
    }
    final messages = _backendMessages;
    if (messages.isEmpty) return;
    final phase = _isCloud ? _cloud.phase : _local.taskPhase.value;
    _session.sync(
      messages,
      selection: ModelSelectionScope.maybeOf(context)?.selection,
      lastFailed: _request != null && messages.length > _runUserIndex + 1
          ? phase == AiTaskPhase.failed || phase == AiTaskPhase.stopped
          : null,
    );
    final runIndices = <Object?, int>{};
    for (final entry in _session.runs.entries) {
      runIndices.putIfAbsent(entry.value['id'], () => entry.key);
    }
    for (final run
        in _local.service.history?.runs ?? <Map<String, dynamic>>[]) {
      final bound = runIndices[run['id']];
      if (bound != null) {
        _session.setRun(bound, run);
      } else if (!_previousRuns.contains(run['id']) &&
          run['request'] == _request) {
        _session.setRun(_runUserIndex, run);
      } else if (!_previousRuns.contains(run['id']) &&
          (run['request'] as String? ?? '').startsWith('เลือกแอป ')) {
        _session.setRun(messages.lastIndexWhere((m) => m.isUser), run);
      }
    }
    if (_isCloud &&
        _cloud.messages.isNotEmpty &&
        _cloud.messages.last.error &&
        _session.failed.isNotEmpty) {
      _session.failed[_session.failed.length - 1] = true;
    }
  }

  Future<ChatAttachment?> _pickAttachment(
    bool image, {
    bool fromOverlay = false,
  }) async {
    if (_busy || (image && !_isCloud && !_local.state.visionReady)) return null;
    setState(() => _pickingAttachment = true);
    try {
      final String name;
      final Stream<List<int>> chunks;
      String? imageMime;
      if (image) {
        final photo = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          requestFullMetadata: false,
        );
        if (photo == null) return null;
        name = photo.name;
        imageMime = switch (name.split('.').last.toLowerCase()) {
          'png' => 'image/png',
          'webp' => 'image/webp',
          'jpg' || 'jpeg' => 'image/jpeg',
          _ => throw const FormatException('PNG, JPG, JPEG, WebP'),
        };
        chunks = photo.openRead();
      } else {
        final file = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: ['txt', 'md', 'json', 'csv', 'log'],
        );
        if (file == null) return null;
        name = file.name;
        chunks = file.readAsByteStream();
      }
      final limit = image ? 20 * 1024 * 1024 : 1024 * 1024;
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in chunks) {
        if (bytes.length + chunk.length > limit) {
          throw FormatException(image ? '20 MB' : '1 MB');
        }
        bytes.add(chunk);
      }
      final data = bytes.takeBytes();
      if (data.isEmpty) throw const FormatException('Empty file');
      final attachment = image
          ? ChatAttachment(name: name, bytes: data, mime: imageMime!)
          : ChatAttachment(
              name: name,
              text: utf8.decode(data),
              mime: 'text/plain',
            );
      if (!mounted || fromOverlay) return attachment;
      setState(() => _attachment = attachment);
      _draftChanged();
      return attachment;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(
                'chat.attachment_error',
                namedArgs: {'error': '$error'},
              ),
            ),
          ),
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => _pickingAttachment = false);
    }
  }

  Future<void> _openConversation(String id) async {
    if (_busy) return;
    final record = _session.conversations
        .where((c) => c['id'] == id)
        .firstOrNull;
    if (record == null || record['model'] is! Map) return;
    final models = ModelSelectionScope.maybeOf(context);
    if (models == null) return;
    _switchingChat = true;
    setState(() => _resetting = true);
    try {
      await _stopReading();
      await _session.flush();
      final selected = ModelSelection.fromJson(record['model'] as Map);
      if (!models.ready ||
          models.selection?.location != selected.location ||
          models.selection?.id != selected.id) {
        switch (selected.location) {
          case ModelLocation.file:
            final entry = models.models
                .where((m) => m.id == selected.id)
                .firstOrNull;
            if (entry == null) {
              throw StateError('Saved model is missing from the library');
            }
            await models.selectFile(entry);
          case ModelLocation.nano:
            await models.selectNano();
          case ModelLocation.cloud:
            await models.selectCloud(selected.id, selected.label);
        }
      }
      if (!mounted) return;
      if (!models.ready ||
          models.selection?.id != selected.id ||
          models.selection?.location != selected.location) {
        throw StateError(context.tr(models.errorKey ?? 'chat.select_first'));
      }
      if (!_session.open(id)) return;
      final messages = List<AiChatMessage>.of(_session.messages);
      if (selected.location == ModelLocation.cloud) {
        _cloud.setModel(selected.id);
        _cloud.restoreMessages([
          for (var i = 0; i < messages.length; i++)
            GeminiMessage(
              messages[i].text,
              contextText:
                  messages[i].text +
                  (_session.attachments[i]?.promptText ?? ''),
              mimeType: _session.attachments[i]?.mime ?? 'image/jpeg',
              user: messages[i].isUser,
              error: _session.failed[i],
              image: messages[i].image,
            ),
        ]);
        // Keep attachment contents in model context without showing them as message text.
      } else {
        await _local.restoreChat(
          messages,
          contextTranscript: [
            for (var i = 0; i < messages.length; i++)
              '${messages[i].isUser ? 'User' : 'Assistant'}: ${messages[i].text}${_session.attachments[i]?.promptText ?? ''}',
          ].join('\n'),
        );
      }
      final textFile = _session.attachments.values
          .where((a) => a.text != null)
          .lastOrNull;
      if (textFile != null) {
        _local.service.deviceTools.selectTextFile(textFile.name, textFile.text);
        _cloud.setAttachedText(textFile.name, textFile.text!);
      }
      _request = null;
      _follow = true;
      _messageTimes.clear();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      _switchingChat = false;
      if (mounted) {
        setState(() => _resetting = false);
        _changed();
      }
    }
  }

  Future<void> _deleteConversation(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('chat.delete_title')),
        content: Text(context.tr('chat.delete_notice')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('chat.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('chat.delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _busy) return;
    if (_session.id == id && !await _newChat()) return;
    await _session.flush();
    await _session.delete(id);
  }

  Future<void> _searchConversations() async {
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) =>
            ConversationSearchPage(conversations: _session.conversations),
      ),
    );
    if (id != null && mounted) await _openConversation(id);
  }

  Future<void> _retry(int assistantIndex) async {
    if (_busy) return;
    final conversation = _session.id;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('chat.retry')),
        content: Text(context.tr('chat.retry_notice')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('chat.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('chat.retry')),
          ),
        ],
      ),
    );
    if (accepted == true && mounted && _session.id == conversation) {
      _retryMessage(assistantIndex);
    }
  }

  bool _retryMessage(int assistantIndex, {bool fromOverlay = false}) {
    if (_busy || assistantIndex >= _session.messages.length) return false;
    var index = assistantIndex - 1;
    while (index >= 0 && !_session.messages[index].isUser) {
      index--;
    }
    if (index < 0) return false;
    return _send(
      _session.messages[index].text,
      retrying: true,
      fromOverlay: fromOverlay,
      retryAttachment: _session.attachments[index],
    );
  }

  void _measureComposer() {
    if (_composerMeasureScheduled) return;
    _composerMeasureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _composerMeasureScheduled = false;
      if (!mounted) return;
      final box = _composerKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize || box.size.height == _composerHeight) {
        return;
      }
      _composerHeight = box.size.height;
      _changed();
    });
  }

  void _settings() {
    unawaited(_stopReading());
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsPage()));
  }

  void _models() {
    unawaited(_stopReading());
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ModelSelectionPage()));
  }

  bool _send(
    String text, {
    bool retrying = false,
    bool fromOverlay = false,
    ChatAttachment? retryAttachment,
    ChatAttachment? overlayAttachment,
  }) {
    final attachment = retrying
        ? retryAttachment
        : (fromOverlay ? overlayAttachment : _attachment);
    final models = ModelSelectionScope.maybeOf(context);
    if (_busy || (text.isEmpty && attachment == null)) return false;
    if (attachment?.bytes != null && !_isCloud && !_local.state.visionReady) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.tr('chat.no_vision'))));
      return false;
    }
    if (models?.ready != true || (!_isCloud && !_local.state.ready)) {
      if (fromOverlay) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('chat.select_first')),
          action: SnackBarAction(
            label: context.tr('settings.model'),
            onPressed: _models,
          ),
        ),
      );
      return false;
    }
    unawaited(_stopReading());
    _previousRuns = {
      for (final run
          in _local.service.history?.runs ?? <Map<String, dynamic>>[])
        run['id'] as String,
    };
    final displayText = text.isEmpty ? attachment!.name : text;
    final payload =
        '${retrying ? 'Retry requested explicitly by the user. Some earlier actions may have completed. Inspect the current screen before any further device actions; do not blindly repeat them.\n' : ''}$displayText${attachment?.promptText ?? ''}';
    _request = _isCloud ? displayText : payload;
    _runUserIndex = _backendMessages.length;
    _follow = true;
    final fileText = attachment?.text;
    if (attachment != null && fileText != null) {
      _local.service.deviceTools.selectTextFile(attachment.name, fileText);
      _cloud.setAttachedText(attachment.name, fileText);
    }
    var accepted = true;
    if (_isCloud) {
      _cloud.setModel(models!.selection!.id);
      accepted = _cloud.send(
        displayText,
        image: attachment?.bytes,
        mimeType: attachment?.mime ?? 'image/jpeg',
        fileText:
            '${attachment?.promptText ?? ''}${retrying ? '\nRetry requested: inspect the current screen before acting; earlier actions may have completed.' : ''}',
      );
    } else {
      unawaited(
        _local.send(
          payload,
          image: attachment?.bytes,
          displayText: displayText,
        ),
      );
    }
    if (accepted) {
      _syncSession();
      _session.attachToLastUser(attachment);
      if (!fromOverlay && !retrying) {
        _attachment = null;
        _draft.clear();
        _draftChanged();
      }
      unawaited(_session.flush());
    }
    return accepted;
  }

  Future<bool> _newChat() async {
    if (_busy) return false;
    setState(() => _resetting = true);
    _switchingChat = true;
    await _session.flush();
    try {
      await _stopReading();
      if (!mounted) return false;
      _cloud.reset();
      await _local.resetChat();
      if (!mounted || _local.state.messages.isNotEmpty) return false;
      _session.startNew();
      _attachment = null;
      setState(() {
        _request = null;
        _draft.clear();
        _messageTimes.clear();
      });
      _draftChanged();
      return true;
    } finally {
      _switchingChat = false;
      if (mounted) setState(() => _resetting = false);
    }
  }

  int _speechRequest = 0;

  Future<void> _stopReading() async {
    _speechRequest++;
    try {
      await _tts.stop();
    } catch (_) {
      /* Device speech service may be absent. */
    }
  }

  Future<void> _read(String text) async {
    final request = ++_speechRequest;
    try {
      await _tts.stop();
      if (!mounted || request != _speechRequest) return;
      await _tts.setLanguage(
        context.locale.languageCode == 'th' ? 'th-TH' : 'en-US',
      );
      if (!mounted || request != _speechRequest) return;
      await _tts.setSpeechRate(
        AppSettingsScope.maybeOf(context)?.speechRate ?? .5,
      );
      if (!mounted || request != _speechRequest) return;
      await _tts.speak(markdownSpeechText(text));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.tr('chat.voice_error'))));
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _syncSession();
      unawaited(_session.flush());
    }
  }

  @override
  void dispose() {
    _floatingUpdate?.cancel();
    _floatingChat.setMethodCallHandler(null);
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _local.service.history?.removeListener(_changed);
    _local.taskPhase.removeListener(_onTaskPhaseChanged);
    _cloud.removeListener(_changed);
    _cloud.dispose();
    unawaited(_stopReading());
    _session.removeListener(_sessionChanged);
    if (widget.session != null) unawaited(_session.flush());
    _draft.removeListener(_draftChanged);
    if (widget.session == null) _session.dispose();
    _draft.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _measureComposer();
    final colors = context.appColors;
    final models = ModelSelectionScope.maybeOf(context);
    final cloud = _isCloud;
    final messages = _backendMessages;
    if (messages.isEmpty) _messageTimes.clear();
    final busy = _busy;
    final generating = cloud ? _cloud.busy : _local.state.generating;
    final stopping = cloud
        ? _cloud.stopRequested
        : _local.state.stoppingGeneration;
    final apps = _pendingApps;

    return FullScreenSwipeMenu(
      bodyBuilder: (context, openMenu) => Scaffold(
        backgroundColor: colors.voidBase,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            onPressed: openMenu,
            tooltip: context.tr('chat.menu'),
            icon: const Icon(TablerIcons.menu_2),
          ),
          centerTitle: true,
          title: TextButton(
            onPressed: busy || models == null ? null : _models,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    models?.selection?.label ?? 'MobilePilot',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.textPrimary, fontSize: 14),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  TablerIcons.chevron_down,
                  size: 14,
                  color: colors.textSecondary,
                ),
              ],
            ),
          ),
          actions: [
            IconButton(
              onPressed: busy ? null : _settings,
              tooltip: context.tr('settings.title'),
              icon: const Icon(TablerIcons.settings),
            ),
          ],
        ),
        body: Stack(
          children: [
            const Positioned.fill(child: FigmaBackgroundWidget()),
            Positioned(
              left: -MediaQuery.sizeOf(context).width / 6,
              right: -MediaQuery.sizeOf(context).width / 6,
              bottom: -175,
              child: const BottomGlowWidget(),
            ),
            SafeArea(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: messages.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(28),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox.square(
                                    dimension: 80,
                                    child: OverflowBox(
                                      // The Figma export includes the glow outside the 80 dp orb.
                                      minWidth: 230,
                                      maxWidth: 230,
                                      minHeight: 230,
                                      maxHeight: 230,
                                      child: Image.asset(
                                        'assets/branding/mobilepilot_welcome_orb.png',
                                        excludeFromSemantics: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    context.tr('chat.welcome'),
                                    style: TextStyle(
                                      fontSize: 24,
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    context.tr('chat.intro'),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                  if (_session.errorKey != null)
                                    Text(
                                      context.tr(_session.errorKey!),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error,
                                      ),
                                    ),
                                  if (_preparingModel) ...[
                                    const SizedBox(height: 20),
                                    const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      context.tr(
                                        'chat.preparing_model',
                                        namedArgs: {
                                          'model':
                                              models?.selection?.label ??
                                              'MobilePilot',
                                        },
                                      ),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: colors.textSecondary,
                                      ),
                                    ),
                                  ],
                                  if (models?.errorKey != null &&
                                      models?.ready != true)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 16),
                                      child: Text(
                                        context.tr(models!.errorKey!),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                        ),
                                      ),
                                    ),
                                  if (models?.ready != true && !_preparingModel)
                                    TextButton(
                                      onPressed: models == null || busy
                                          ? null
                                          : _models,
                                      child: Text(
                                        context.tr('chat.select_first'),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          )
                        : NotificationListener<ScrollNotification>(
                            onNotification: (notification) {
                              if ((notification is ScrollUpdateNotification &&
                                      notification.dragDetails != null) ||
                                  notification is ScrollEndNotification) {
                                final following =
                                    notification.metrics.extentAfter < 80;
                                if (following != _follow) {
                                  setState(() => _follow = following);
                                }
                              }
                              return false;
                            },
                            child: ListView(
                              controller: _scroll,
                              padding: EdgeInsets.fromLTRB(
                                16,
                                16,
                                16,
                                _composerHeight + 8,
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Text(
                                    DateFormat.yMMMd(context.locale.toString())
                                        .format(
                                          _session.times.firstOrNull ??
                                              _messageTimes.putIfAbsent(
                                                '$cloud:date',
                                                DateTime.now,
                                              ),
                                        ),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ),
                                if (_session.errorKey != null)
                                  Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Text(
                                      context.tr(_session.errorKey!),
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error,
                                      ),
                                    ),
                                  ),
                                for (final (index, message)
                                    in messages.indexed) ...[
                                  if (message.text.isNotEmpty ||
                                      message.image != null)
                                    ChatMessageBubble(
                                      key: ValueKey('${_session.id}:$index'),
                                      timestamp: index < _session.times.length
                                          ? _session.times[index]
                                          : _messageTimes.putIfAbsent(
                                              '$cloud:$index',
                                              DateTime.now,
                                            ),
                                      text: message.text,
                                      user: message.isUser,
                                      attachmentName:
                                          _session.attachments[index]?.name,
                                      failed:
                                          index < _session.failed.length &&
                                          _session.failed[index],
                                      onRetry:
                                          !busy &&
                                              index < _session.failed.length &&
                                              _session.failed[index] &&
                                              !message.isUser
                                          ? () => _retry(index)
                                          : null,
                                      onCopy: message.text.isEmpty
                                          ? null
                                          : () async {
                                              await Clipboard.setData(
                                                ClipboardData(
                                                  text: message.text,
                                                ),
                                              );
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      context.tr('chat.copied'),
                                                    ),
                                                  ),
                                                );
                                              }
                                            },
                                      image: message.image == null
                                          ? null
                                          : ChatMessageImage(
                                              bytes: message.image!,
                                            ),
                                      onRead: !message.isUser && !generating
                                          ? () => _read(message.text)
                                          : null,
                                    ),
                                  if (_session.runs[index] case final run?)
                                    if ((run['steps'] as List? ?? [])
                                        .isNotEmpty)
                                      ChatExecutionCard(
                                        key: ValueKey(run['id']),
                                        steps: (run['steps'] as List)
                                            .whereType<Map>()
                                            .toList(),
                                        active: run['state'] == 'running',
                                      ),
                                ],
                                if (cloud
                                    ? _cloud.accessibilityNeeded
                                    : _local.state.accessibilityNeeded)
                                  AccessibilityRequiredAction(
                                    onStatus: cloud
                                        ? _cloud.updateAccessibility
                                        : _local.updateAccessibility,
                                  ),
                                for (final app in apps)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: OutlinedButton(
                                      onPressed: () {
                                        final packageName = app['packageName'];
                                        if (packageName != null) {
                                          unawaited(
                                            _choosePendingApp(packageName),
                                          );
                                        }
                                      },
                                      child: Text(
                                        app['label'] ??
                                            app['packageName'] ??
                                            'App',
                                      ),
                                    ),
                                  ),
                                if (generating)
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      children: [
                                        const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            stopping
                                                ? context.tr('chat.stopping')
                                                : cloud
                                                ? (_cloud.progress.isEmpty
                                                      ? context.tr(
                                                          'chat.thinking',
                                                        )
                                                      : _cloud.progress)
                                                : _local.state.status,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: colors.textSecondary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                  ),
                  if (!_follow && messages.isNotEmpty)
                    Positioned(
                      right: 24,
                      bottom: _composerHeight + 12,
                      child: FloatingActionButton.small(
                        heroTag: 'chat-latest',
                        tooltip: context.tr('chat.latest'),
                        onPressed: () {
                          setState(() => _follow = true);
                          _changed();
                        },
                        child: const Icon(Icons.arrow_downward),
                      ),
                    ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: NotificationListener<SizeChangedLayoutNotification>(
                      onNotification: (_) {
                        _measureComposer();
                        return true;
                      },
                      child: SizeChangedLayoutNotifier(
                        child: ChatBar(
                          key: _composerKey,
                          controller: _draft,
                          onPhoto: cloud || _local.state.visionReady
                              ? () => _pickAttachment(true)
                              : null,
                          onFile: () => _pickAttachment(false),
                          imagePreviewBytes: _attachment?.bytes,
                          attachmentPreview: _attachment == null
                              ? null
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (_attachment?.text != null)
                                      InputChip(
                                        label: Text(
                                          _attachment!.name,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        onDeleted: () {
                                          setState(() => _attachment = null);
                                          _draftChanged();
                                        },
                                      ),
                                    if (cloud)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 6,
                                        ),
                                        child: Text(
                                          context.tr('chat.attachment_notice'),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: colors.textSecondary,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                          onClearImage: () {
                            setState(() => _attachment = null);
                            _draftChanged();
                          },
                          onSubmit: _send,
                          enabled: !busy,
                          busy: generating,
                          stopping: stopping,
                          onVoiceStart: () => unawaited(_stopReading()),
                          onStop: _stopReply,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      menuBuilder: (context, closeMenu) => HomeMenuPanel(
        onClose: closeMenu,
        conversations: _session.conversations,
        selectedConversation: _session.id,
        onOpen: busy
            ? null
            : (id) {
                closeMenu();
                unawaited(_openConversation(id));
              },
        onDelete: busy ? null : (id) => unawaited(_deleteConversation(id)),
        onSearch: busy
            ? null
            : () {
                closeMenu();
                unawaited(_searchConversations());
              },
        onNewChat: busy ? null : () => unawaited(_newChat()),
        onSettings: busy
            ? null
            : () {
                closeMenu();
                _settings();
              },
      ),
    );
  }
}
