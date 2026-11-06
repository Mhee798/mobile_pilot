import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../ai/presentation/widgets/answer_markdown.dart';

class ChatMessageImage extends StatelessWidget {
  const ChatMessageImage({super.key, required this.bytes});

  final Uint8List bytes;
  static const double height = 160;

  @override
  Widget build(BuildContext context) => Image.memory(
    bytes,
    height: height,
    fit: BoxFit.contain,
    errorBuilder: (_, _, _) => Text(context.tr('chat.image_error')),
  );
}

class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    super.key,
    required this.text,
    required this.user,
    this.image,
    this.onRead,
    this.timestamp,
    this.onCopy,
    this.onRetry,
    this.failed = false,
    this.attachmentName,
  });
  final String text;
  final String? attachmentName;
  final bool failed;
  final VoidCallback? onCopy, onRetry;
  final bool user;
  final Widget? image;
  final VoidCallback? onRead;
  final DateTime? timestamp;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * (user ? .78 : .92),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: user
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: user ? null : colors.glassFill,
                  gradient: user
                      ? LinearGradient(
                          colors: [colors.primaryCyan, colors.glowDeep],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(user ? 16 : 2),
                    topRight: Radius.circular(user ? 2 : 16),
                    bottomLeft: const Radius.circular(16),
                    bottomRight: const Radius.circular(16),
                  ),
                  border: Border.all(color: colors.borderGlassSubtle),
                ),
                child: DefaultTextStyle.merge(
                  style: TextStyle(
                    color: user ? Colors.white : colors.textPrimary,
                    fontSize: 14,
                    height: 1.6,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ?image,
                      if (attachmentName != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.attach_file,
                                size: 14,
                                color: user
                                    ? Colors.white
                                    : colors.textSecondary,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  attachmentName!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (failed)
                        Text(
                          context.tr('chat.failed'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      if (text.isNotEmpty)
                        user ? SelectableText(text) : AnswerMarkdown(text),
                    ],
                  ),
                ),
              ),
              if (user && timestamp != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 4),
                  child: Text(
                    DateFormat.Hm(context.locale.toString()).format(timestamp!),
                    style: TextStyle(fontSize: 10, color: colors.textSecondary),
                  ),
                ),
              if (onRead != null || onCopy != null || onRetry != null)
                Wrap(
                  children: [
                    if (onCopy != null)
                      IconButton(
                        tooltip: context.tr('chat.copy'),
                        onPressed: onCopy,
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.copy_outlined,
                          size: 18,
                          color: colors.textSecondary,
                        ),
                      ),
                    if (onRetry != null)
                      IconButton(
                        tooltip: context.tr('chat.retry'),
                        onPressed: onRetry,
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.refresh,
                          size: 18,
                          color: colors.textSecondary,
                        ),
                      ),
                    if (onRead != null)
                      IconButton(
                        tooltip: context.tr('chat.read'),
                        onPressed: onRead,
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.volume_up_outlined,
                          size: 18,
                          color: colors.textSecondary,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
