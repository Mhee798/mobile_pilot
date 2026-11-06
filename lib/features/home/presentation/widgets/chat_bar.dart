import 'package:easy_localization/easy_localization.dart';

import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/widgets/speech_input_button.dart';

import '../../../../core/theme/app_colors.dart';

/// Animated pulse widget indicating microphone sound input levels.
class AudioWaveWidget extends StatelessWidget {
  final double audioLevel;
  final double maxSize;
  final double minSize;
  final Color? color;

  const AudioWaveWidget({
    super.key,
    required this.audioLevel,
    this.maxSize = 40.0,
    this.minSize = 36.0,
    this.color,
  });

  double normalize(double value, double min, double max) {
    if (value.isNaN || value.isInfinite) return 0.0;
    final normalized = (value - min) / (max - min);
    return normalized.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    // Normalize audio level (-2 to 10) to 0.0-1.0
    final intensity = normalize(audioLevel, -2.0, 10.0);
    final effectiveMin = minSize <= maxSize ? minSize : maxSize * 0.8;
    // Guaranteed to scale between minSize and maxSize, never exceeding maxSize
    final currentSize = (effectiveMin + (intensity * (maxSize - effectiveMin)))
        .clamp(0.0, maxSize);

    final waveColor =
        color ?? context.appColors.primaryCyan.withValues(alpha: 0.35);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
      width: currentSize,
      height: currentSize,
      decoration: BoxDecoration(shape: BoxShape.circle, color: waveColor),
    );
  }
}

/// Chat input bar modeled after the Figma glassmorphic design specification:
/// - Container: 360w x 58h, rx: 24, fill: glassFill, stroke: borderGlassSubtle, backdrop blur
/// - Left action: 40x40 circle, fill: surfaceContainerHigh, stroke: outlineVariant, icon: +
/// - Input area: multiline text with hint "พิมพ์ข้อความสั่ง..."
/// - Mic button: 40x40 circle, fill: surfaceContainerHigh, stroke: outlineVariant, icon: mic
/// - Send button: 40x40 circle, gradient (primaryCyan -> glowDeep), glow, icon: paper plane
class ChatBar extends StatefulWidget {
  final void Function(String text)? onSend;
  final bool Function(String text)? onSubmit;
  final bool busy;
  final bool stopping;
  final VoidCallback? onStop;
  final VoidCallback? onVoiceStart;
  final VoidCallback? onPhoto;
  final VoidCallback? onFile;
  final Uint8List? imagePreviewBytes;
  final Widget? attachmentPreview;
  final VoidCallback? onClearImage;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hintText;
  final bool enabled;

  const ChatBar({
    super.key,
    this.onSend,
    this.onSubmit,
    this.busy = false,
    this.stopping = false,
    this.onStop,
    this.onVoiceStart,
    this.onPhoto,
    this.onFile,
    this.imagePreviewBytes,
    this.attachmentPreview,
    this.onClearImage,
    this.controller,
    this.focusNode,
    this.hintText,
    this.enabled = true,
  });

  @override
  State<ChatBar> createState() => _ChatBarState();
}

class _ChatBarState extends State<ChatBar> {
  FocusNode? _internalFocusNode;
  TextEditingController? _internalController;

  TextEditingController get _controller =>
      widget.controller ?? (_internalController ??= TextEditingController());

  FocusNode get _focusNode =>
      widget.focusNode ?? (_internalFocusNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  void _onTextChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(ChatBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      (oldWidget.controller ?? _internalController)?.removeListener(
        _onTextChanged,
      );
      _controller.addListener(_onTextChanged);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _internalFocusNode)?.removeListener(
        _onFocusChanged,
      );
      _focusNode.addListener(_onFocusChanged);
    }
  }

  void _handleSend() {
    final text = _controller.text.trim();
    final hasImage =
        widget.imagePreviewBytes != null || widget.attachmentPreview != null;

    if ((text.isNotEmpty || hasImage) && widget.enabled && !widget.busy) {
      final accepted = widget.onSubmit?.call(text) ?? (widget.onSend != null);
      if (!accepted) return;
      if (widget.onSubmit == null) widget.onSend?.call(text);
      widget.onClearImage?.call();
      _controller.clear();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _controller.removeListener(_onTextChanged);
    _internalController?.dispose();
    _internalFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final colorScheme = Theme.of(context).colorScheme;
    final hasTextOrImage =
        _controller.text.trim().isNotEmpty ||
        widget.imagePreviewBytes != null ||
        widget.attachmentPreview != null;
    final hasFocus = _focusNode.hasFocus;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.attachmentPreview != null) widget.attachmentPreview!,
            // Optional image preview chip
            if (widget.imagePreviewBytes != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8, left: 8),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: colors.voidElevated.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        widget.imagePreviewBytes!,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: widget.onClearImage,
                        child: Container(
                          decoration: BoxDecoration(
                            color: colors.voidBase.withValues(alpha: 0.7),
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(3),
                          child: Icon(
                            TablerIcons.x,
                            size: 14,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Main Glassmorphism Chat Bar Container
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: hasFocus
                    ? [
                        BoxShadow(
                          color: colors.primaryCyan.withValues(alpha: 0.2),
                          blurRadius: 8,
                          spreadRadius: 0,
                          offset: const Offset(0, 0),
                          blurStyle: BlurStyle.outer,
                        ),
                      ]
                    : [],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 58),
                    decoration: BoxDecoration(
                      // Reveal the conversation behind the frosted composer in both themes.
                      color: colors.glassFill.withValues(alpha: .5),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: hasFocus
                            ? colors.borderGlassActive
                            : colors.borderGlassSubtle,
                        width: 1,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 7,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // 1. Plus (+) button (40x40 circle)
                        _buildPlusButton(context),

                        const SizedBox(width: 8),

                        // 2. Input TextField
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            enabled: widget.enabled,
                            style: TextStyle(
                              fontSize: 14,
                              color: colors.textPrimary,
                            ),
                            cursorColor: colors.primaryCyan,
                            textAlignVertical: TextAlignVertical.center,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _handleSend(),
                            minLines: 1,
                            maxLines: 4,
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 8,
                              ),
                              filled: false,
                              hintText:
                                  widget.hintText ?? context.tr('chat.hint'),
                              hintStyle: TextStyle(
                                fontSize: 14,
                                color: colors.textSecondary,
                              ),
                              border: InputBorder.none,
                            ),
                          ),
                        ),

                        const SizedBox(width: 6),

                        // 3. Microphone Button (36x36 circle)
                        _buildMicButton(context),

                        const SizedBox(width: 6),

                        // 4. Send Button (40x40 circle with gradient and glow)
                        _buildSendButton(context, hasTextOrImage),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Plus attachment button with a popup menu.
  Widget _buildPlusButton(BuildContext context) {
    final colors = context.appColors;
    final colorScheme = Theme.of(context).colorScheme;

    return PopupMenuButton<int>(
      enabled:
          widget.enabled && (widget.onPhoto != null || widget.onFile != null),
      requestFocus: false,
      offset: Offset(
        0,
        widget.onPhoto != null && widget.onFile != null ? -102 : -54,
      ),
      color: colorScheme.surfaceContainer,
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.zero,
      menuPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      itemBuilder: (context) => [
        if (widget.onPhoto != null)
          PopupMenuItem(
            value: 1,
            onTap: widget.onPhoto,
            child: Row(
              children: [
                Icon(
                  TablerIcons.photo,
                  size: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  context.tr('chat.photo'),
                  style: TextStyle(color: colors.textPrimary),
                ),
              ],
            ),
          ),
        if (widget.onFile != null)
          PopupMenuItem(
            value: 2,
            onTap: widget.onFile,
            child: Row(
              children: [
                Icon(
                  TablerIcons.file,
                  size: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  context.tr('chat.file'),
                  style: TextStyle(color: colors.textPrimary),
                ),
              ],
            ),
          ),
      ],
      child: TextFieldTapRegion(child: _plusContainer(context)),
    );
  }

  Widget _plusContainer(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.7),
        shape: BoxShape.circle,
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Icon(
        TablerIcons.plus,
        color: colorScheme.onSurfaceVariant,
        size: 20,
      ),
    );
  }

  /// Microphone button (36x36 circle)
  Widget _buildMicButton(BuildContext context) {
    final colors = context.appColors;
    final colorScheme = Theme.of(context).colorScheme;

    return SpeechInputButton(
      controller: _controller,
      enabled: widget.enabled,
      builder: (context, listening, soundLevel, onPressed) => SizedBox(
        width: 40,
        height: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (listening)
              AudioWaveWidget(
                audioLevel: soundLevel * 12 - 2,
                maxSize: 40,
                minSize: 20,
                color: colors.primaryCyan.withValues(alpha: 0.35),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.7),
                shape: BoxShape.circle,
                border: Border.all(
                  color: listening
                      ? colors.primaryCyan
                      : colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              child: IconButton(
                tooltip: listening
                    ? context.tr('speech.stop')
                    : context.tr('speech.start'),
                onPressed: onPressed == null
                    ? null
                    : () {
                        if (!listening) widget.onVoiceStart?.call();
                        onPressed();
                      },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 40,
                  height: 40,
                ),
                icon: Icon(
                  TablerIcons.microphone,
                  color: listening ? colors.primaryCyan : colors.textPrimary,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Send button (40x40 circle with cyan-to-indigo gradient and glow)
  Widget _buildSendButton(BuildContext context, bool hasTextOrImage) {
    final colors = context.appColors;

    if (widget.busy) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFFF87171), Color(0xFFDC2626), Color(0xFF7F1D1D)],
            stops: [0, .5, 1],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: .2)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40F87171),
              offset: Offset(0, 4),
              blurRadius: 6,
              spreadRadius: -4,
            ),
            BoxShadow(
              color: Color(0x40F87171),
              offset: Offset(0, 10),
              blurRadius: 15,
              spreadRadius: -3,
            ),
          ],
        ),
        child: IconButton(
          tooltip: context.tr(widget.stopping ? 'chat.stopping' : 'chat.stop'),
          onPressed: widget.stopping ? null : widget.onStop,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          icon: widget.stopping
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
        ),
      );
    }
    return Semantics(
      button: true,
      label: context.tr('chat.send'),
      child: GestureDetector(
        onTap: widget.enabled && hasTextOrImage ? _handleSend : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: hasTextOrImage ? 1.0 : 0.65,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [colors.primaryCyan, colors.glowDeep],
              ),
              border: Border.all(color: colors.glassHairline, width: 1),
              boxShadow: hasTextOrImage
                  ? [
                      BoxShadow(
                        color: colors.primaryCyan.withValues(alpha: 0.4),
                        blurRadius: 10,
                        offset: const Offset(1, 0),
                        spreadRadius: -2,
                      ),
                      BoxShadow(
                        color: colors.glowDeep.withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(-1, 0),
                        spreadRadius: -1,
                      ),
                    ]
                  : [],
            ),
            child: const Center(
              child: Icon(TablerIcons.send_2, color: Colors.white, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}
