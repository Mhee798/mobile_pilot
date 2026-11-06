import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:mobile_pilot/core/theme/app_colors.dart';

import '../../../../core/localization/app_localization.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/home_chat_session.dart';
import '../widgets/chat_bar.dart';
import '../widgets/chat_execution_card.dart';
import '../widgets/chat_message_bubble.dart';
import '../widgets/figma_background_widget.dart';

Future<void> runFloatingChat({required bool capsule}) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (capsule) {
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: const FloatingChatPage(capsule: true),
      ),
    );
    return;
  }
  await EasyLocalization.ensureInitialized();
  runApp(
    AppLocalization(
      child: Builder(
        builder: (context) => GestureDetector(
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark.copyWith(canvasColor: Colors.transparent),
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: const FloatingChatPage(),
          ),
        ),
      ),
    ),
  );
}

class FloatingChatPage extends StatefulWidget {
  const FloatingChatPage({super.key, this.capsule = false});

  final bool capsule;

  @override
  State<FloatingChatPage> createState() => _FloatingChatPageState();
}

class _FloatingChatPageState extends State<FloatingChatPage> {
  static const _platform = MethodChannel('com.mobilepilot/overlay_ui');
  final _draft = TextEditingController();
  final _scroll = ScrollController();
  Map _window = const {};
  Map _chat = const {};
  double _keyboardInset = 0;
  bool _sending = false;
  bool _picking = false;
  bool _startingChat = false;
  bool _loadingOlder = false;
  bool _choosingApp = false;
  ChatAttachment? _attachment;

  @override
  void initState() {
    super.initState();
    _platform.setMethodCallHandler(_update);
    unawaited(_platform.invokeMethod<void>('ready'));
  }

  Future<void> _update(MethodCall call) async {
    final data = call.arguments;
    if (!mounted) return;
    if (call.method == 'keyboard' && data is num) {
      setState(() => _keyboardInset = data.toDouble());
      return;
    }
    if (data is! Map) return;
    switch (call.method) {
      case 'window':
        final opening = _window['mode'] == 'bubble' && data['mode'] != 'bubble';
        if (_window['mode'] == 'expanded' && data['mode'] == 'bubble') {
          FocusManager.instance.primaryFocus?.unfocus();
        }
        setState(() => _window = data);
        if (opening) _followLatest();
      case 'chat':
        final previousFirst = _firstMessageIndex(_chat);
        final nextFirst = _firstMessageIndex(data);
        final prepended =
            _chat['conversation'] == data['conversation'] &&
            previousFirst != null &&
            nextFirst != null &&
            nextFirst < previousFirst &&
            _scroll.hasClients;
        final previousExtent = prepended
            ? _scroll.position.maxScrollExtent
            : 0.0;
        final follow =
            _chat['conversation'] != data['conversation'] ||
            !_scroll.hasClients ||
            _scroll.position.extentAfter < 40;
        setState(() => _chat = data);
        if (prepended) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted ||
                !_scroll.hasClients ||
                _chat['conversation'] != data['conversation']) {
              return;
            }
            final position = _scroll.position;
            position.jumpTo(
              (position.pixels + position.maxScrollExtent - previousExtent)
                  .clamp(position.minScrollExtent, position.maxScrollExtent),
            );
          });
        } else if (follow) {
          _followLatest();
        }
    }
  }

  int? _firstMessageIndex(Map snapshot) {
    final messages = snapshot['messages'] as List?;
    return (messages?.firstOrNull as Map?)?['index'] as int?;
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || _chat['hasOlder'] != true) return;
    final conversation = _chat['conversation'];
    setState(() => _loadingOlder = true);
    try {
      final snapshot = await _platform.invokeMethod<Map>(
        'loadOlder',
        conversation,
      );
      if (mounted &&
          snapshot != null &&
          _chat['conversation'] == conversation) {
        await _update(MethodCall('chat', snapshot));
      }
    } on PlatformException {
      if (mounted) _notice(context.tr('chat.failed'));
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  Future<void> _chooseApp(String packageName) async {
    if (_choosingApp) return;
    setState(() => _choosingApp = true);
    try {
      final accepted = await _platform.invokeMethod<bool>('chooseApp', {
        'conversation': _chat['conversation'],
        'packageName': packageName,
      });
      if (mounted && accepted != true) _notice(context.tr('chat.failed'));
    } on PlatformException {
      if (mounted) _notice(context.tr('chat.failed'));
    } finally {
      if (mounted) setState(() => _choosingApp = false);
    }
  }

  void _followLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _platform.setMethodCallHandler(null);
    _draft.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      final attachment = _attachment;
      final accepted = await _platform.invokeMethod<bool>('send', {
        'text': text,
        'attachment': attachment?.toMap(),
      });
      if (!mounted) return;
      if (accepted == true) {
        if (_draft.text.trim() == text) _draft.clear();
        if (_attachment == attachment) setState(() => _attachment = null);
        _followLatest();
      } else {
        _notice(context.tr('chat.select_first'));
      }
    } on PlatformException {
      if (mounted) _notice(context.tr('chat.failed'));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pick(bool image) async {
    if (_picking) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _picking = true);
    try {
      final data = await _platform.invokeMethod<Map>('pick', image);
      if (mounted && data != null) {
        setState(() => _attachment = ChatAttachment.fromMap(data));
      }
    } on PlatformException {
      if (mounted) _notice(context.tr('chat.failed'));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _notice(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _retry(Map message) async {
    final conversation = _chat['conversation'];
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('chat.retry')),
        content: Text(context.tr('chat.retry_notice')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('chat.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('chat.retry')),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    final retried = await _platform.invokeMethod<bool>('retry', {
      'conversation': conversation,
      'index': message['index'],
    });
    if (mounted && retried != true) _notice(context.tr('chat.failed'));
  }

  Future<void> _newChat() async {
    setState(() => _startingChat = true);
    try {
      final created = await _platform.invokeMethod<bool>('newChat');
      if (!mounted) return;
      if (created == true) {
        _draft.clear();
        setState(() => _attachment = null);
      } else {
        _notice(context.tr('chat.failed'));
      }
    } on PlatformException {
      if (mounted) _notice(context.tr('chat.failed'));
    } finally {
      if (mounted) setState(() => _startingChat = false);
    }
  }

  Future<void> _openApp() async {
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await _platform.invokeMethod<void>('openApp');
    } on PlatformException {
      if (mounted) _notice(context.tr('sidebar.open_app_failed'));
    }
  }

  void _mode(String mode) {
    if (mode == 'bubble') FocusManager.instance.primaryFocus?.unfocus();
    unawaited(_platform.invokeMethod<void>('mode', mode));
  }

  Widget _capsule({required bool collapsed}) {
    final overTarget = _window['overTarget'] == true;
    return Semantics(
      button: true,
      label: 'MobilePilot',
      child: GestureDetector(
        onTap: () => _mode(collapsed ? 'expanded' : 'bubble'),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: overTarget ? Colors.white : const Color(0xff9ba6ba),
            ),
            gradient: const LinearGradient(
              colors: [Color(0xff05afdb), Color(0xff2d3e9d)],
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Icon(TablerIcons.robot, color: Colors.white, size: 24),
              if (collapsed)
                const Positioned(
                  right: 2,
                  bottom: 2,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0xff2acb95),
                      shape: BoxShape.circle,
                    ),
                    child: SizedBox.square(dimension: 8),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _message(Map message) {
    final conversation = _chat['conversation'];
    final user = message['user'] == true;
    final text = message['text'] as String? ?? '';
    final failed = message['failed'] == true;
    return ChatMessageBubble(
      key: ValueKey((conversation, message['index'])),
      text: text,
      user: user,
      attachmentName: message['attachment'] as String?,
      image: message['hasImage'] == true
          ? _FloatingMessageImage(
              load: () => _platform.invokeMethod<Uint8List>('messageImage', {
                'conversation': conversation,
                'index': message['index'],
              }),
            )
          : null,
      timestamp: DateTime.tryParse(message['timestamp'] as String? ?? ''),
      failed: failed,
      onRetry: failed && !user && _chat['busy'] != true
          ? () => _retry(message)
          : null,
      onRead: !user && text.isNotEmpty
          ? () => unawaited(_platform.invokeMethod<void>('read', text))
          : null,
      onCopy: text.isEmpty
          ? null
          : () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (mounted) _notice(context.tr('chat.copied'));
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    final expanded = _window['mode'] == 'expanded';
    final messages = (_chat['messages'] as List? ?? const []).whereType<Map>();
    final runs = (_chat['runs'] as List? ?? const []).whereType<Map>();
    final apps = (_chat['apps'] as List? ?? const []).whereType<Map>();
    final byIndex = {for (final run in runs) run['index']: run};
    final headerButtonStyle = IconButton.styleFrom(
      fixedSize: const Size.square(48),
      shape: const CircleBorder(),
      padding: EdgeInsets.zero,
      backgroundColor: const Color(0xff87929a),
      foregroundColor: Colors.white,
      side: const BorderSide(color: Color(0x663e484f)),
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: widget.capsule
          ? Center(child: _capsule(collapsed: true))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _mode('bubble'),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8, bottom: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: context.tr('sidebar.open_app'),
                                style: headerButtonStyle,
                                onPressed: _openApp,
                                icon: const Icon(TablerIcons.external_link),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: context.tr('sidebar.new_chat'),
                                style: headerButtonStyle,
                                onPressed:
                                    _chat['busy'] == true ||
                                        _sending ||
                                        _picking ||
                                        _startingChat
                                    ? null
                                    : _newChat,
                                icon: const Icon(TablerIcons.edit_circle),
                              ),
                              const SizedBox(width: 8),
                              _capsule(collapsed: false),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: expanded ? 1 : 0),
                    duration: const Duration(milliseconds: 200),
                    builder: (_, progress, child) => Opacity(
                      opacity: progress,
                      child: Transform.translate(
                        offset: Offset(0, 20 * (1 - progress)),
                        child: child,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const FigmaBackgroundWidget(),
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            top: 0,
                            left: 0,
                            right: 0,
                            bottom: _keyboardInset,
                            child: Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: Text(
                                    _chat['modelLabel'] as String? ??
                                        'MobilePilot',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: messages.isEmpty
                                      ? Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
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
                                                color: AppColors.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              context.tr('chat.intro'),
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                          ],
                                        )
                                      : NotificationListener<
                                          ScrollUpdateNotification
                                        >(
                                          onNotification: (notification) {
                                            if (notification.dragDetails !=
                                                    null &&
                                                (notification.scrollDelta ??
                                                        0) <
                                                    0 &&
                                                notification
                                                        .metrics
                                                        .extentBefore <
                                                    80) {
                                              unawaited(_loadOlder());
                                            }
                                            return false;
                                          },
                                          child: ListView(
                                            controller: _scroll,
                                            padding: const EdgeInsets.fromLTRB(
                                              16,
                                              12,
                                              16,
                                              8,
                                            ),
                                            children: [
                                              if (_chat['hasOlder'] == true)
                                                Center(
                                                  child: TextButton(
                                                    onPressed: _loadingOlder
                                                        ? null
                                                        : _loadOlder,
                                                    child: Text(
                                                      context.tr(
                                                        'chat.load_older',
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              if (_chat['heading']
                                                  case final String heading)
                                                Center(child: Text(heading)),
                                              for (final message
                                                  in messages) ...[
                                                if ((message['text']
                                                                as String? ??
                                                            '')
                                                        .isNotEmpty ||
                                                    message['attachment'] !=
                                                        null ||
                                                    message['hasImage'] ==
                                                        true ||
                                                    message['failed'] == true)
                                                  _message(message),
                                                if (byIndex[message['index']]
                                                    case final Map run)
                                                  ChatExecutionCard(
                                                    key: ValueKey(run['id']),
                                                    steps:
                                                        (run['steps']
                                                                    as List? ??
                                                                const [])
                                                            .whereType<Map>()
                                                            .toList(),
                                                    active:
                                                        run['state'] ==
                                                        'running',
                                                  ),
                                              ],
                                              for (final app in apps)
                                                if (app['packageName']
                                                    case final String
                                                        packageName)
                                                  OutlinedButton(
                                                    onPressed: _choosingApp
                                                        ? null
                                                        : () => _chooseApp(
                                                            packageName,
                                                          ),
                                                    child: Text(
                                                      app['label'] as String? ??
                                                          packageName,
                                                    ),
                                                  ),
                                            ],
                                          ),
                                        ),
                                ),
                                SafeArea(
                                  top: false,
                                  left: false,
                                  right: false,
                                  minimum: const EdgeInsets.only(bottom: 16),
                                  child: ChatBar(
                                    controller: _draft,
                                    enabled:
                                        !_sending &&
                                        !_picking &&
                                        !_startingChat &&
                                        (_chat['busy'] != true ||
                                            _chat['running'] == true),
                                    busy: _chat['running'] == true,
                                    stopping: _chat['stopping'] == true,
                                    onStop: () => unawaited(
                                      _platform.invokeMethod<void>('stop'),
                                    ),
                                    onPhoto: _chat['canAttachPhoto'] == true
                                        ? () => _pick(true)
                                        : null,
                                    onFile: () => _pick(false),
                                    imagePreviewBytes: _attachment?.bytes,
                                    attachmentPreview: _attachment == null
                                        ? null
                                        : Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              if (_attachment?.text != null)
                                                InputChip(
                                                  label: Text(
                                                    _attachment!.name,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  onDeleted: () => setState(
                                                    () => _attachment = null,
                                                  ),
                                                ),
                                              if (_chat['cloud'] == true)
                                                Text(
                                                  context.tr(
                                                    'chat.attachment_notice',
                                                  ),
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall,
                                                ),
                                            ],
                                          ),
                                    onClearImage: () =>
                                        setState(() => _attachment = null),
                                    onSubmit: (text) {
                                      unawaited(_send(text));
                                      return false;
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _FloatingMessageImage extends StatefulWidget {
  const _FloatingMessageImage({required this.load});

  final Future<Uint8List?> Function() load;

  @override
  State<_FloatingMessageImage> createState() => _FloatingMessageImageState();
}

class _FloatingMessageImageState extends State<_FloatingMessageImage> {
  late final _image = widget.load();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _image,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(height: ChatMessageImage.height);
        }
        final bytes = snapshot.data;
        if (bytes == null) return Text(context.tr('chat.image_error'));
        return ChatMessageImage(bytes: bytes);
      },
    );
  }
}
